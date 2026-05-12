<?php

declare(strict_types=1);

namespace Sandstorm\NodeTypes\Folder\UriCollision;

use Neos\ContentRepository\Core\CommandHandler\CommandHookInterface;
use Neos\ContentRepository\Core\CommandHandler\CommandInterface;
use Neos\ContentRepository\Core\CommandHandler\Commands;
use Neos\ContentRepository\Core\EventStore\PublishedEvents;
use Neos\ContentRepository\Core\Feature\NodeCreation\Command\CreateNodeAggregateWithNode;
use Neos\ContentRepository\Core\Feature\NodeModification\Command\SetNodeProperties;
use Neos\ContentRepository\Core\SharedModel\ContentRepository\ContentRepositoryId;
use Neos\ContentRepository\Core\SharedModel\Node\NodeAggregateId;
use Neos\Neos\FrontendRouting\Exception\NodeNotFoundException;
use Neos\Neos\FrontendRouting\Projection\DocumentUriPathFinder;
use Neos\ContentRepositoryRegistry\ContentRepositoryRegistry;

/**
 * Rejects commands that would write a node with an effective uriPath that
 * already exists in the projection — for any client of the content
 * repository (UI, API, import, CLI). Pairs with the editor-side validator
 * (Defense B), which shares {@see UriCollisionCheck}.
 */
final readonly class UriCollisionCommandHook implements CommandHookInterface
{
    public function __construct(
        private UriCollisionCheck $uriCollisionCheck,
        private ContentRepositoryRegistry $contentRepositoryRegistry,
        private ContentRepositoryId $contentRepositoryId,
    ) {
    }

    public function onBeforeHandle(CommandInterface $command): CommandInterface
    {
        $collisions = match (true) {
            $command instanceof CreateNodeAggregateWithNode => $this->checkCreate($command),
            $command instanceof SetNodeProperties           => $this->checkSetProperties($command),
            default                                         => null,
        };

        if ($collisions !== null && !$collisions->isEmpty()) {
            throw new UriPathCollisionDetected($collisions);
        }

        return $command;
    }

    public function onAfterHandle(CommandInterface $command, PublishedEvents $events): Commands
    {
        return Commands::createEmpty();
    }

    private function checkCreate(CreateNodeAggregateWithNode $command): ?CollisionList
    {
        $segment = $this->stringProperty($command->initialPropertyValues->values, 'uriPathSegment');
        if ($segment === null) {
            return null;
        }
        $hide = (bool)($command->initialPropertyValues->values['hideSegmentInUriPath'] ?? false);

        return $this->uriCollisionCheck->check(
            $this->contentRepositoryId,
            $command->workspaceName,
            $command->nodeAggregateId,
            $command->parentNodeAggregateId,
            $segment,
            $hide,
            $command->originDimensionSpacePoint,
        );
    }

    private function checkSetProperties(SetNodeProperties $command): ?CollisionList
    {
        $values = $command->propertyValues->values;
        $segmentChanged = array_key_exists('uriPathSegment', $values) && $values['uriPathSegment'] !== null;
        $hideChanged = array_key_exists('hideSegmentInUriPath', $values);

        if (!$segmentChanged && !$hideChanged) {
            return null;
        }

        $contentRepository = $this->contentRepositoryRegistry->get($this->contentRepositoryId);
        $finder = $contentRepository->projectionState(DocumentUriPathFinder::class);

        $collisions = CollisionList::empty();

        if ($segmentChanged) {
            // Resolve the node's parent from the projection (any covered DSP
            // is fine — UriCollisionCheck walks the full covered set itself).
            $node = $this->findAnyNodeRow($finder, $command->nodeAggregateId);
            if ($node !== null) {
                $hide = $hideChanged
                    ? (bool)$values['hideSegmentInUriPath']
                    : (bool)($node->toArray()['hideurisegment'] ?? false);
                $collisions = $collisions->merge($this->uriCollisionCheck->check(
                    $this->contentRepositoryId,
                    $command->workspaceName,
                    $command->nodeAggregateId,
                    $node->getParentNodeAggregateId(),
                    (string)$values['uriPathSegment'],
                    $hide,
                    $command->originDimensionSpacePoint,
                ));
            }
        }

        if ($hideChanged) {
            $collisions = $collisions->merge($this->uriCollisionCheck->checkHideToggle(
                $this->contentRepositoryId,
                $command->nodeAggregateId,
                (bool)$values['hideSegmentInUriPath'],
            ));
        }

        return $collisions;
    }

    private function stringProperty(array $values, string $key): ?string
    {
        if (!array_key_exists($key, $values)) {
            return null;
        }
        $value = $values[$key];
        if ($value === null || $value === '') {
            return null;
        }
        return (string)$value;
    }

    private function findAnyNodeRow(
        DocumentUriPathFinder $finder,
        NodeAggregateId $nodeAggregateId,
    ): ?\Neos\Neos\FrontendRouting\Projection\DocumentNodeInfo {
        // The projection doesn't expose a "first row across DSPs" lookup, so
        // we ask the variation graph for the full set and try each until one
        // exists. Any one is enough — UriCollisionCheck re-derives the full
        // covered set internally.
        $cr = $this->contentRepositoryRegistry->get($this->contentRepositoryId);
        foreach ($cr->getVariationGraph()->getDimensionSpacePoints() as $dsp) {
            try {
                return $finder->getByIdAndDimensionSpacePointHash($nodeAggregateId, $dsp->hash);
            } catch (NodeNotFoundException) {
                continue;
            }
        }
        return null;
    }
}
