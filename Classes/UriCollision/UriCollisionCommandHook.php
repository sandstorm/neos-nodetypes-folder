<?php

declare(strict_types=1);

namespace Sandstorm\NodeTypes\Folder\UriCollision;

use Neos\ContentRepository\Core\CommandHandler\CommandHookInterface;
use Neos\ContentRepository\Core\CommandHandler\CommandInterface;
use Neos\ContentRepository\Core\CommandHandler\Commands;
use Neos\ContentRepository\Core\EventStore\PublishedEvents;
use Neos\ContentRepository\Core\Feature\NodeCreation\Command\CreateNodeAggregateWithNode;
use Neos\ContentRepository\Core\Feature\NodeModification\Command\SetNodeProperties;
use Neos\ContentRepository\Core\Feature\NodeMove\Command\MoveNodeAggregate;
use Neos\ContentRepository\Core\Feature\NodeVariation\Command\CreateNodeVariant;
use Neos\ContentRepository\Core\Projection\ContentGraph\VisibilityConstraints;
use Neos\ContentRepository\Core\SharedModel\ContentRepository\ContentRepositoryId;
use Neos\ContentRepository\Core\SharedModel\Node\NodeAggregateId;
use Neos\Neos\FrontendRouting\Exception\NodeNotFoundException;
use Neos\Neos\FrontendRouting\Projection\DocumentNodeInfo;
use Neos\Neos\FrontendRouting\Projection\DocumentUriPathFinder;
use Neos\ContentRepositoryRegistry\ContentRepositoryRegistry;
use Sandstorm\NodeTypes\Folder\FrontendRouting\Projection\FolderUriPathLogic;

/**
 * Rejects commands that would write a node with an effective uriPath that
 * already exists in the projection — for any client of the content
 * repository (UI, API, import, CLI). Pairs with the editor-side validator
 * (Defense B), which shares {@see UriCollisionCheck}.
 *
 * @internal wiring class — instantiated by {@see UriCollisionCommandHookFactory}
 *   per content-repository preset.
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
            $command instanceof MoveNodeAggregate           => $this->checkMove($command),
            $command instanceof CreateNodeVariant           => $this->checkVariant($command),
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
        // Hooks run before the CR merges NodeType defaults into the event, so
        // without this a folder created via the UI (which sends neither
        // hideSegmentInUriPath nor targetMode) would look opaque/redirecting.
        $nodeType = $this->contentRepositoryRegistry->get($this->contentRepositoryId)
            ->getNodeTypeManager()
            ->getNodeType($command->nodeTypeName);
        $values = array_merge(
            $nodeType?->getDefaultValuesForProperties() ?? [],
            $command->initialPropertyValues->values,
        );

        return $this->uriCollisionCheck->check(
            $this->contentRepositoryId,
            $command->workspaceName,
            $command->nodeAggregateId,
            $command->parentNodeAggregateId,
            $segment,
            FolderUriPathLogic::isUnroutableFolderFor(
                (bool)($values['hideSegmentInUriPath'] ?? false),
                is_string($values['targetMode'] ?? null) ? $values['targetMode'] : null,
            ),
            $command->originDimensionSpacePoint,
        )->merge($this->uriCollisionCheck->checkSiblings(
            $this->contentRepositoryId,
            $command->workspaceName,
            $command->nodeAggregateId,
            $command->parentNodeAggregateId,
            $segment,
            $command->originDimensionSpacePoint->toDimensionSpacePoint(),
        ));
    }

    private function checkSetProperties(SetNodeProperties $command): ?CollisionList
    {
        $values = $command->propertyValues->values;
        $segmentChanged = array_key_exists('uriPathSegment', $values) && $values['uriPathSegment'] !== null;
        $hideChanged = array_key_exists('hideSegmentInUriPath', $values);
        // A folder's own URL becomes reachable when it stops being `noTarget`.
        $targetModeChanged = array_key_exists('targetMode', $values);

        if (!$segmentChanged && !$hideChanged && !$targetModeChanged) {
            return null;
        }

        $contentRepository = $this->contentRepositoryRegistry->get($this->contentRepositoryId);
        $finder = $contentRepository->projectionState(DocumentUriPathFinder::class);

        $collisions = CollisionList::empty();

        if ($segmentChanged || $targetModeChanged) {
            // Resolve the node's parent from the projection (any covered DSP
            // is fine — UriCollisionCheck walks the full covered set itself).
            $node = $this->findAnyNodeRow($finder, $command->nodeAggregateId);
            if ($node !== null) {
                $collisions = $collisions->merge($this->uriCollisionCheck->check(
                    $this->contentRepositoryId,
                    $command->workspaceName,
                    $command->nodeAggregateId,
                    $node->getParentNodeAggregateId(),
                    $segmentChanged ? (string)$values['uriPathSegment'] : basename($node->getUriPath()),
                    $this->uriCollisionCheck->isUnroutableFolderAfterChange($this->contentRepositoryId, $command->workspaceName, $command->nodeAggregateId, $command->originDimensionSpacePoint, $values),
                    $command->originDimensionSpacePoint,
                ));
            }
        }

        $newSegment = $values['uriPathSegment'] ?? null;
        if (is_string($newSegment) && $newSegment !== '') {
            // The projection only knows live; the parent from the workspace's
            // content graph also covers nodes that are not published yet.
            $parent = $contentRepository->getContentGraph($command->workspaceName)
                ->getSubgraph($command->originDimensionSpacePoint->toDimensionSpacePoint(), VisibilityConstraints::createEmpty())
                ->findParentNode($command->nodeAggregateId);
            if ($parent !== null) {
                $collisions = $collisions->merge($this->uriCollisionCheck->checkSiblings(
                    $this->contentRepositoryId,
                    $command->workspaceName,
                    $command->nodeAggregateId,
                    $parent->aggregateId,
                    $newSegment,
                    $command->originDimensionSpacePoint->toDimensionSpacePoint(),
                ));
            }
        }

        if ($hideChanged) {
            $collisions = $collisions->merge($this->uriCollisionCheck->checkHideToggle(
                $this->contentRepositoryId,
                $command->workspaceName,
                $command->nodeAggregateId,
                (bool)$values['hideSegmentInUriPath'],
            ));
        }

        return $collisions;
    }

    private function checkMove(MoveNodeAggregate $command): ?CollisionList
    {
        if ($command->newParentNodeAggregateId === null) {
            // Sibling reorder under the same parent cannot shift the path.
            return null;
        }
        $collisions = $this->uriCollisionCheck->checkMove(
            $this->contentRepositoryId,
            $command->workspaceName,
            $command->nodeAggregateId,
            $command->newParentNodeAggregateId,
            $command->dimensionSpacePoint,
        );

        // Read the segment from the workspace: the moved node may be unpublished.
        $movedNode = $this->contentRepositoryRegistry->get($this->contentRepositoryId)
            ->getContentGraph($command->workspaceName)
            ->getSubgraph($command->dimensionSpacePoint, VisibilityConstraints::createEmpty())
            ->findNodeById($command->nodeAggregateId);
        $segment = $movedNode?->getProperty('uriPathSegment');
        if (!is_string($segment) || $segment === '') {
            return $collisions;
        }

        return $collisions->merge($this->uriCollisionCheck->checkSiblings(
            $this->contentRepositoryId,
            $command->workspaceName,
            $command->nodeAggregateId,
            $command->newParentNodeAggregateId,
            $segment,
            $command->dimensionSpacePoint,
        ));
    }

    private function checkVariant(CreateNodeVariant $command): ?CollisionList
    {
        return $this->uriCollisionCheck->checkVariant(
            $this->contentRepositoryId,
            $command->workspaceName,
            $command->nodeAggregateId,
            $command->sourceOrigin,
            $command->targetOrigin,
        );
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
    ): ?DocumentNodeInfo {
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
