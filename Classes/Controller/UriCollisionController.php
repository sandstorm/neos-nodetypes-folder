<?php

declare(strict_types=1);

namespace Sandstorm\NodeTypes\Folder\Controller;

use GuzzleHttp\Psr7\Response;
use Neos\ContentRepository\Core\DimensionSpace\OriginDimensionSpacePoint;
use Neos\ContentRepository\Core\SharedModel\Node\NodeAggregateId;
use Neos\ContentRepository\Core\SharedModel\Workspace\WorkspaceName;
use Neos\Flow\Annotations as Flow;
use Neos\Flow\Mvc\Controller\ActionController;
use Neos\Neos\FrontendRouting\SiteDetection\SiteDetectionResult;
use Sandstorm\NodeTypes\Folder\UriCollision\Collision;
use Sandstorm\NodeTypes\Folder\UriCollision\CollisionList;
use Sandstorm\NodeTypes\Folder\UriCollision\UriCollisionCheck;

/**
 * HTTP endpoint backing the editor-side (Defense B) async validator on the
 * `uriPathSegment` and `hideSegmentInUriPath` inspector properties.
 *
 * The inspector POSTs the prospective state of a node before the user hits
 * Apply; the controller asks {@see UriCollisionCheck} whether saving would
 * collide with any existing row in the live projection. 200 with `{ok:true}`
 * means save is safe; 409 with `conflicts[]` blocks the inspector.
 *
 * Defense A (the command hook) is still the authoritative line of defense;
 * this controller exists only to surface the same answer before the command
 * is dispatched so the editor sees an inline error instead of a backend
 * exception.
 *
 * @internal HTTP wiring class — the validation logic lives in
 *   {@see UriCollisionCheck}.
 */
final class UriCollisionController extends ActionController
{
    #[Flow\Inject]
    protected UriCollisionCheck $uriCollisionCheck;

    /**
     * POST neos/folder/check-uri-collision
     *
     * Body (JSON):
     * ```
     * {
     *   "workspaceName": "user-jdoe",
     *   "nodeAggregateId": "bd69f893-..." | null,
     *   "parentNodeAggregateId": "...",
     *   "dimensions": {"language": ["en"]},
     *   "propertyValues": {
     *     "uriPathSegment": "foo",
     *     "hideSegmentInUriPath": true
     *   }
     * }
     * ```
     *
     * `contentRepositoryId` is resolved server-side from the request via
     * {@see SiteDetectionResult::fromRequest()} (populated by
     * `SiteDetectionMiddleware` before routing) — same source the rest of
     * the Neos backend uses, so the editor doesn't have to know it.
     *
     * `dimensions` is accepted in the legacy
     * `{dimensionName: [valueList]}` shape that the Neos.Neos.Ui store
     * exposes; we normalize to the DSP `{dimensionName: value}` shape here
     * rather than asking every caller to do it.
     */
    public function checkAction(): Response
    {
        $body = (string)$this->request->getHttpRequest()->getBody();
        /** @var array<string, mixed> $payload */
        $payload = json_decode($body, true, 512, JSON_THROW_ON_ERROR);

        $contentRepositoryId = SiteDetectionResult::fromRequest(
            $this->request->getHttpRequest(),
        )->contentRepositoryId;
        $workspaceName = WorkspaceName::fromString((string)($payload['workspaceName'] ?? 'live'));
        $selfId = isset($payload['nodeAggregateId']) && $payload['nodeAggregateId'] !== ''
            ? NodeAggregateId::fromString((string)$payload['nodeAggregateId'])
            : null;
        $originDsp = OriginDimensionSpacePoint::fromArray(
            self::normalizeDimensions((array)($payload['dimensions'] ?? [])),
        );

        /** @var array<string, mixed> $propertyValues */
        $propertyValues = (array)($payload['propertyValues'] ?? []);
        $segment = isset($propertyValues['uriPathSegment']) ? (string)$propertyValues['uriPathSegment'] : null;
        $hide = array_key_exists('hideSegmentInUriPath', $propertyValues)
            ? (bool)$propertyValues['hideSegmentInUriPath']
            : null;

        $collisions = CollisionList::empty();

        if ($segment !== null && isset($payload['parentNodeAggregateId'])) {
            $collisions = $collisions->merge($this->uriCollisionCheck->check(
                $contentRepositoryId,
                $workspaceName,
                $selfId,
                NodeAggregateId::fromString((string)$payload['parentNodeAggregateId']),
                $segment,
                $hide ?? false,
                $originDsp,
            ));
        }

        if ($hide !== null && $selfId !== null) {
            $collisions = $collisions->merge($this->uriCollisionCheck->checkHideToggle(
                $contentRepositoryId,
                $workspaceName,
                $selfId,
                $hide,
            ));
        }

        if ($collisions->isEmpty()) {
            return $this->jsonResponse(200, ['ok' => true]);
        }

        return $this->jsonResponse(409, [
            'ok' => false,
            'conflicts' => array_map(
                static fn(Collision $c): array => [
                    'dimensionSpacePointHash' => $c->dimensionSpacePoint->hash,
                    'dimensionSpacePoint' => $c->dimensionSpacePoint->coordinates,
                    'uriPath' => $c->uriPath,
                    'otherNodeAggregateId' => $c->otherNodeAggregateId->value,
                    'otherNodeTypeName' => $c->otherNodeTypeName,
                    'otherNodeLabel' => $c->otherNodeLabel,
                ],
                iterator_to_array($collisions),
            ),
        ]);
    }

    /**
     * Neos.Neos.Ui's `ContentDimensions.active` store keeps the legacy
     * "list of values per dimension" shape (`{language: ["en"]}`); core's
     * `DimensionSpacePoint::fromArray()` wants `{language: "en"}`. The
     * editor is "active view" — always exactly one value per dimension —
     * so the conversion is trivial. Already-flat payloads are pass-through.
     *
     * @param array<string, mixed> $raw
     * @return array<string, string>
     */
    private static function normalizeDimensions(array $raw): array
    {
        $out = [];
        foreach ($raw as $name => $value) {
            if (is_array($value)) {
                if ($value !== []) {
                    $out[(string)$name] = (string)reset($value);
                }
                continue;
            }
            $out[(string)$name] = (string)$value;
        }
        return $out;
    }

    /**
     * @param array<string, mixed> $body
     */
    private function jsonResponse(int $code, array $body): Response
    {
        return new Response(
            $code,
            ['Content-Type' => 'application/json'],
            json_encode($body, JSON_THROW_ON_ERROR),
        );
    }
}
