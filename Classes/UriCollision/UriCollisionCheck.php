<?php

declare(strict_types=1);

namespace Sandstorm\NodeTypes\Folder\UriCollision;

use Doctrine\DBAL\Connection;
use Neos\ContentRepository\Core\DimensionSpace\DimensionSpacePoint;
use Neos\ContentRepository\Core\DimensionSpace\OriginDimensionSpacePoint;
use Neos\ContentRepository\Core\Projection\ContentGraph\VisibilityConstraints;
use Neos\ContentRepository\Core\SharedModel\ContentRepository\ContentRepositoryId;
use Neos\ContentRepository\Core\SharedModel\Node\NodeAggregateId;
use Neos\ContentRepository\Core\SharedModel\Workspace\WorkspaceName;
use Neos\ContentRepositoryRegistry\ContentRepositoryRegistry;
use Neos\Neos\FrontendRouting\Exception\NodeNotFoundException;
use Neos\Neos\FrontendRouting\Projection\DocumentNodeInfo;
use Neos\Neos\FrontendRouting\Projection\DocumentUriPathFinder;
use Sandstorm\NodeTypes\Folder\FrontendRouting\Projection\DocumentUriPathProjectionFactory;
use Sandstorm\NodeTypes\Folder\FrontendRouting\Projection\FolderUriPathLogic;

/**
 * Shared collision check for Defense A (command hook) and Defense B
 * (editor-side endpoint). Queries the same projection rows the router would
 * resolve at runtime, so it surfaces exactly the conflict that would manifest.
 *
 * @api shared by {@see UriCollisionCommandHook} (Defense A) and the planned
 *   Defense B HTTP endpoint, which is why it lives outside both call sites.
 */
final readonly class UriCollisionCheck
{
    public function __construct(
        private ContentRepositoryRegistry $contentRepositoryRegistry,
        private Connection $dbal,
    ) {
    }

    /**
     * Check whether placing/renaming a node with the given prospective segment
     * under the given parent would collide with any existing row in any
     * dimension covered from $originDsp.
     *
     * @param NodeAggregateId|null $selfId Node id to exclude from collision
     *  matches. For brand-new nodes pass the prospective id (already chosen
     *  by the time the command is built); pass null only if it is not yet
     *  known (no row in projection to ignore).
     */
    public function check(
        ContentRepositoryId $contentRepositoryId,
        WorkspaceName $workspaceName,
        ?NodeAggregateId $selfId,
        NodeAggregateId $parentId,
        string $candidateUriPathSegment,
        bool $candidateHideSegmentInUriPath,
        OriginDimensionSpacePoint $originDimensionSpacePoint,
    ): CollisionList {
        unset($candidateHideSegmentInUriPath);
        // workspaceName is part of the contract for Defense B; the
        // DocumentUriPath projection is currently single-workspace per CR.
        // The candidate's own hide flag does not affect its own row's uriPath
        // (the row always stores parent_prefix/segment) — but it does affect
        // its descendants, handled separately via checkHideToggle().

        $contentRepository = $this->contentRepositoryRegistry->get($contentRepositoryId);
        $finder = $contentRepository->projectionState(DocumentUriPathFinder::class);
        $tableNamePrefix = DocumentUriPathProjectionFactory::projectionTableNamePrefix($contentRepositoryId);
        $folderLogic = new FolderUriPathLogic($finder, $this->dbal, $tableNamePrefix);

        $coveredDsps = $contentRepository->getVariationGraph()->getSpecializationSet(
            $originDimensionSpacePoint->toDimensionSpacePoint(),
            true,
        );

        $collisions = CollisionList::empty();
        foreach ($coveredDsps as $dsp) {
            try {
                $parent = $finder->getByIdAndDimensionSpacePointHash($parentId, $dsp->hash);
            } catch (NodeNotFoundException) {
                continue;
            }
            $candidateUriPath = $folderLogic->buildChildUriPath($candidateUriPathSegment, $parent, $dsp);
            $collisions = $collisions->merge(
                $this->queryCollisions($tableNamePrefix . '_uri', $dsp, $candidateUriPath, $selfId, $contentRepositoryId, $workspaceName),
            );
        }

        return $collisions;
    }

    /**
     * Check that toggling the hideSegmentInUriPath flag on an existing folder
     * does not collapse two URL spaces into a collision among already-saved
     * descendants/siblings.
     */
    public function checkHideToggle(
        ContentRepositoryId $contentRepositoryId,
        WorkspaceName $workspaceName,
        NodeAggregateId $folderId,
        bool $newHide,
    ): CollisionList {
        $contentRepository = $this->contentRepositoryRegistry->get($contentRepositoryId);
        $finder = $contentRepository->projectionState(DocumentUriPathFinder::class);
        $tableNamePrefix = DocumentUriPathProjectionFactory::projectionTableNamePrefix($contentRepositoryId);
        $tableName = $tableNamePrefix . '_uri';
        $folderLogic = new FolderUriPathLogic($finder, $this->dbal, $tableNamePrefix);

        $collisions = CollisionList::empty();

        $rows = $this->dbal->fetchAllAssociative(
            'SELECT * FROM ' . $tableName . ' WHERE nodeAggregateId = :id',
            ['id' => $folderId->value],
        );

        $allDsps = $contentRepository->getVariationGraph()->getDimensionSpacePoints();
        foreach ($rows as $folderRow) {
            if ((bool)($folderRow['hideurisegment'] ?? false) === $newHide) {
                continue;
            }
            $folderInfo = new DocumentNodeInfo($folderRow);
            // The projection stores only the DSP hash. Reconstruct the full DSP from the
            // variation graph so {@see FolderUriPathLogic::buildParentUriPath()} has a
            // value to walk parents with.
            $dsp = $allDsps[$folderRow['dimensionspacepointhash']] ?? null;
            if ($dsp === null) {
                continue;
            }

            try {
                $parent = $finder->getByIdAndDimensionSpacePointHash(
                    $folderInfo->getParentNodeAggregateId(),
                    $dsp->hash,
                );
            } catch (NodeNotFoundException) {
                continue;
            }
            $folderUriPath = $folderInfo->getUriPath();
            $effectiveParentPrefix = $folderLogic->buildParentUriPath($parent, $dsp);

            $descendantRows = $this->dbal->fetchAllAssociative(
                'SELECT nodeAggregateId, nodetypename, uriPath FROM ' . $tableName . '
                 WHERE dimensionSpacePointHash = :dsp
                   AND nodeAggregateId != :folderId
                   AND nodeAggregateIdPath LIKE :pathPrefix',
                [
                    'dsp' => $dsp->hash,
                    'folderId' => $folderId->value,
                    'pathPrefix' => $folderInfo->getNodeAggregateIdPath() . '/%',
                ],
            );

            foreach ($descendantRows as $row) {
                $newPath = $folderLogic->computeHideToggledDescendantPath(
                    $row['uriPath'],
                    $folderUriPath,
                    $effectiveParentPrefix,
                    $newHide,
                );
                $collisions = $collisions->merge(
                    $this->queryCollisions(
                        $tableName,
                        $dsp,
                        $newPath,
                        NodeAggregateId::fromString($row['nodeAggregateId']),
                        $contentRepositoryId,
                        $workspaceName,
                    ),
                );
            }
        }

        return $collisions;
    }

    /**
     * Reject a {@see \Neos\ContentRepository\Core\Feature\NodeMove\Command\MoveNodeAggregate}
     * when the moved node's prospective uriPath under the new parent would
     * collide with an existing row in any DSP it currently covers.
     *
     * Walks the variation graph's specialization set from the command's
     * dimensionSpacePoint — that over-covers the scatter strategy, but the
     * per-DSP `getByIdAndDimensionSpacePointHash` skip prevents false positives.
     */
    public function checkMove(
        ContentRepositoryId $contentRepositoryId,
        WorkspaceName $workspaceName,
        NodeAggregateId $nodeAggregateId,
        NodeAggregateId $newParentId,
        DimensionSpacePoint $dimensionSpacePoint,
    ): CollisionList {
        $contentRepository = $this->contentRepositoryRegistry->get($contentRepositoryId);
        $finder = $contentRepository->projectionState(DocumentUriPathFinder::class);
        $tableNamePrefix = DocumentUriPathProjectionFactory::projectionTableNamePrefix($contentRepositoryId);
        $folderLogic = new FolderUriPathLogic($finder, $this->dbal, $tableNamePrefix);

        $coveredDsps = $contentRepository->getVariationGraph()->getSpecializationSet($dimensionSpacePoint, true);

        $collisions = CollisionList::empty();
        foreach ($coveredDsps as $dsp) {
            try {
                $current = $finder->getByIdAndDimensionSpacePointHash($nodeAggregateId, $dsp->hash);
                $newParent = $finder->getByIdAndDimensionSpacePointHash($newParentId, $dsp->hash);
            } catch (NodeNotFoundException) {
                continue;
            }
            $segment = basename($current->getUriPath());
            if ($segment === '') {
                continue;
            }
            $candidateUriPath = $folderLogic->buildChildUriPath($segment, $newParent, $dsp);
            $collisions = $collisions->merge(
                $this->queryCollisions($tableNamePrefix . '_uri', $dsp, $candidateUriPath, $nodeAggregateId, $contentRepositoryId, $workspaceName),
            );
        }

        return $collisions;
    }

    /**
     * Reject a {@see \Neos\ContentRepository\Core\Feature\NodeVariation\Command\CreateNodeVariant}
     * when the resulting variant rows (one per DSP covered from $targetOrigin)
     * would collide with existing rows in the target dimension — typically
     * because the parent's effective uriPath differs from source to target.
     */
    public function checkVariant(
        ContentRepositoryId $contentRepositoryId,
        WorkspaceName $workspaceName,
        NodeAggregateId $nodeAggregateId,
        OriginDimensionSpacePoint $sourceOrigin,
        OriginDimensionSpacePoint $targetOrigin,
    ): CollisionList {
        $contentRepository = $this->contentRepositoryRegistry->get($contentRepositoryId);
        $finder = $contentRepository->projectionState(DocumentUriPathFinder::class);
        $tableNamePrefix = DocumentUriPathProjectionFactory::projectionTableNamePrefix($contentRepositoryId);
        $folderLogic = new FolderUriPathLogic($finder, $this->dbal, $tableNamePrefix);

        try {
            $sourceRow = $finder->getByIdAndDimensionSpacePointHash(
                $nodeAggregateId,
                $sourceOrigin->toDimensionSpacePoint()->hash,
            );
        } catch (NodeNotFoundException) {
            return CollisionList::empty();
        }
        $segment = basename($sourceRow->getUriPath());
        if ($segment === '') {
            return CollisionList::empty();
        }
        $parentId = $sourceRow->getParentNodeAggregateId();

        $coveredDsps = $contentRepository->getVariationGraph()->getSpecializationSet(
            $targetOrigin->toDimensionSpacePoint(),
            true,
        );

        $collisions = CollisionList::empty();
        foreach ($coveredDsps as $dsp) {
            try {
                $parent = $finder->getByIdAndDimensionSpacePointHash($parentId, $dsp->hash);
            } catch (NodeNotFoundException) {
                continue;
            }
            $candidateUriPath = $folderLogic->buildChildUriPath($segment, $parent, $dsp);
            $collisions = $collisions->merge(
                $this->queryCollisions($tableNamePrefix . '_uri', $dsp, $candidateUriPath, $nodeAggregateId, $contentRepositoryId, $workspaceName),
            );
        }

        return $collisions;
    }

    private function queryCollisions(
        string $tableName,
        DimensionSpacePoint $dimensionSpacePoint,
        string $candidateUriPath,
        ?NodeAggregateId $selfId,
        ContentRepositoryId $contentRepositoryId,
        WorkspaceName $workspaceName,
    ): CollisionList {
        $sql = 'SELECT nodeAggregateId, nodetypename FROM ' . $tableName . '
                WHERE dimensionSpacePointHash = :dsp AND uriPath = :uri';
        $params = ['dsp' => $dimensionSpacePoint->hash, 'uri' => $candidateUriPath];
        if ($selfId !== null) {
            $sql .= ' AND nodeAggregateId != :selfId';
            $params['selfId'] = $selfId->value;
        }

        $subgraph = $this->contentRepositoryRegistry->get($contentRepositoryId)
            ->getContentGraph($workspaceName)
            ->getSubgraph($dimensionSpacePoint, VisibilityConstraints::withoutRestrictions());

        $collisions = CollisionList::empty();
        foreach ($this->dbal->fetchAllAssociative($sql, $params) as $row) {
            $nodeId = NodeAggregateId::fromString($row['nodeAggregateId']);
            $node = $subgraph->findNodeById($nodeId);
            $label = $node?->hasProperty('title') ? (string)$node->getProperty('title') : null;
            $collisions = $collisions->with(new Collision(
                $dimensionSpacePoint,
                $candidateUriPath,
                $nodeId,
                (string)$row['nodetypename'],
                $label,
            ));
        }
        return $collisions;
    }
}
