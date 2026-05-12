<?php

declare(strict_types=1);

namespace Sandstorm\NodeTypes\Folder\FrontendRouting\CatchUpHook;

use Neos\ContentRepository\Core\DimensionSpace\DimensionSpacePoint;
use Neos\ContentRepository\Core\EventStore\EventInterface;
use Neos\ContentRepository\Core\Feature\NodeModification\Event\NodePropertiesWereSet;
use Neos\ContentRepository\Core\Projection\CatchUpHook\CatchUpHookInterface;
use Neos\ContentRepository\Core\SharedModel\Node\NodeAggregateId;
use Neos\ContentRepository\Core\SharedModel\Node\PropertyName;
use Neos\ContentRepository\Core\Subscription\SubscriptionStatus;
use Neos\EventStore\Model\EventEnvelope;
use Neos\Flow\Mvc\Routing\RouterCachingService;
use Neos\Neos\FrontendRouting\Exception\NodeNotFoundException;
use Neos\Neos\FrontendRouting\Projection\DocumentNodeInfo;
use Neos\Neos\FrontendRouting\Projection\DocumentUriPathFinder;

final class FolderRouterCacheHook implements CatchUpHookInterface
{
    /**
     * Runtime cache to collect tags until they can get flushed.
     * @var string[]
     */
    private array $tagsToFlush = [];

    public function __construct(
        private readonly DocumentUriPathFinder $documentUriPathFinder,
        private readonly RouterCachingService $routerCachingService,
    ) {
    }

    public function onBeforeCatchUp(SubscriptionStatus $subscriptionStatus): void
    {
        // Nothing to do here
    }

    public function onBeforeEvent(EventInterface $eventInstance, EventEnvelope $eventEnvelope): void
    {
        if (!$eventInstance instanceof NodePropertiesWereSet || !$eventInstance->workspaceName->isLive()) {
            return;
        }

        $newPropertyValues = $eventInstance->propertyValues->getPlainValues();
        $unsetPropertyNames = array_flip(array_map(
            fn (PropertyName $propertyName) => $propertyName->value,
            iterator_to_array($eventInstance->propertiesToUnset)
        ));

        if (!isset($newPropertyValues['hideSegmentInUriPath']) && !isset($unsetPropertyNames['hideSegmentInUriPath'])) {
            return;
        }

        foreach ($eventInstance->affectedDimensionSpacePoints as $dimensionSpacePoint) {
            $node = $this->findDocumentNodeInfoByIdAndDimensionSpacePoint($eventInstance->nodeAggregateId, $dimensionSpacePoint);
            if ($node === null) {
                // Probably not a document node
                continue;
            }

            $this->collectTagsToFlush($node);

            $descendantsOfNode = $this->documentUriPathFinder->getDescendantsOfNode($node);
            array_map($this->collectTagsToFlush(...), iterator_to_array($descendantsOfNode));
        }
    }

    public function onAfterEvent(EventInterface $eventInstance, EventEnvelope $eventEnvelope): void
    {
        if ($eventInstance instanceof NodePropertiesWereSet) {
            $this->flushAllCollectedTags();
        }
    }

    public function onAfterBatchCompleted(): void
    {
        // Nothing to do here
    }

    public function onAfterCatchUp(): void
    {
        // Nothing to do here
    }

    private function collectTagsToFlush(DocumentNodeInfo $node): void
    {
        array_push($this->tagsToFlush, ...$node->getRouteTags()->getTags());
    }

    private function flushAllCollectedTags(): void
    {
        if ($this->tagsToFlush === []) {
            return;
        }

        $this->routerCachingService->flushCachesByTags($this->tagsToFlush);
        $this->tagsToFlush = [];
    }

    private function findDocumentNodeInfoByIdAndDimensionSpacePoint(NodeAggregateId $nodeAggregateId, DimensionSpacePoint $dimensionSpacePoint): ?DocumentNodeInfo
    {
        try {
            return $this->documentUriPathFinder->getByIdAndDimensionSpacePointHash(
                $nodeAggregateId,
                $dimensionSpacePoint->hash
            );
        } catch (NodeNotFoundException $_) {
            /** @noinspection BadExceptionsProcessingInspection */
            return null;
        }
    }
}
