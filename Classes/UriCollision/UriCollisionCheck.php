<?php

declare(strict_types=1);

namespace Sandstorm\NodeTypes\Folder\UriCollision;

use Doctrine\DBAL\Connection;
use Neos\ContentRepository\Core\DimensionSpace\DimensionSpacePoint;
use Neos\ContentRepository\Core\DimensionSpace\OriginDimensionSpacePoint;
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
        unset($workspaceName, $candidateHideSegmentInUriPath);
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
                $this->queryCollisions($tableNamePrefix . '_uri', $dsp->hash, $candidateUriPath, $selfId),
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

        foreach ($rows as $folderRow) {
            if ((bool)($folderRow['hideurisegment'] ?? false) === $newHide) {
                continue;
            }
            $folderInfo = new DocumentNodeInfo($folderRow);
            $dsp = DimensionSpacePoint::fromJsonString($folderRow['dimensionspacepoint']);

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
                        $dsp->hash,
                        $newPath,
                        NodeAggregateId::fromString($row['nodeAggregateId']),
                    ),
                );
            }
        }

        return $collisions;
    }

    private function queryCollisions(
        string $tableName,
        string $dimensionSpacePointHash,
        string $candidateUriPath,
        ?NodeAggregateId $selfId,
    ): CollisionList {
        $sql = 'SELECT nodeAggregateId, nodetypename FROM ' . $tableName . '
                WHERE dimensionSpacePointHash = :dsp AND uriPath = :uri';
        $params = ['dsp' => $dimensionSpacePointHash, 'uri' => $candidateUriPath];
        if ($selfId !== null) {
            $sql .= ' AND nodeAggregateId != :selfId';
            $params['selfId'] = $selfId->value;
        }
        $collisions = CollisionList::empty();
        foreach ($this->dbal->fetchAllAssociative($sql, $params) as $row) {
            $collisions = $collisions->with(new Collision(
                $dimensionSpacePointHash,
                $candidateUriPath,
                NodeAggregateId::fromString($row['nodeAggregateId']),
                (string)$row['nodetypename'],
            ));
        }
        return $collisions;
    }
}
