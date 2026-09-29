<?php

declare(strict_types=1);

namespace Sandstorm\NodeTypes\Folder\UriCollision;

use Doctrine\DBAL\Connection;
use Neos\ContentRepository\Core\DimensionSpace\DimensionSpacePoint;
use Neos\ContentRepository\Core\DimensionSpace\OriginDimensionSpacePoint;
use Neos\ContentRepository\Core\Feature\SubtreeTagging\Dto\SubtreeTags;
use Neos\ContentRepository\Core\Projection\ContentGraph\Filter\FindAncestorNodesFilter;
use Neos\ContentRepository\Core\Projection\ContentGraph\Filter\FindChildNodesFilter;
use Neos\ContentRepository\Core\Projection\ContentGraph\Filter\PropertyValue\Criteria\PropertyValueEquals;
use Neos\ContentRepository\Core\Projection\ContentGraph\VisibilityConstraints;
use Neos\ContentRepository\Core\SharedModel\ContentRepository\ContentRepositoryId;
use Neos\ContentRepository\Core\SharedModel\Node\NodeAggregateId;
use Neos\ContentRepository\Core\SharedModel\Node\PropertyName;
use Neos\ContentRepository\Core\SharedModel\Workspace\WorkspaceName;
use Neos\ContentRepositoryRegistry\ContentRepositoryRegistry;
use Neos\Neos\Domain\Model\SiteNodeName;
use Neos\Neos\Domain\Service\NodeTypeNameFactory;
use Neos\Neos\Domain\SubtreeTagging\NeosSubtreeTag;
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
     * @param bool $candidateIsUnroutableFolder Whether the candidate is a
     *  transparent `noTarget` folder, see {@see FolderUriPathLogic::isUnroutableFolder()}.
     *  Its own row always stores parent_prefix/segment regardless of the hide
     *  flag; the flag's effect on descendants is handled via checkHideToggle().
     */
    public function check(
        ContentRepositoryId $contentRepositoryId,
        WorkspaceName $workspaceName,
        ?NodeAggregateId $selfId,
        NodeAggregateId $parentId,
        string $candidateUriPathSegment,
        bool $candidateIsUnroutableFolder,
        OriginDimensionSpacePoint $originDimensionSpacePoint,
    ): CollisionList {
        // workspaceName is part of the contract for Defense B; the
        // DocumentUriPath projection is currently single-workspace per CR.

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
                $this->queryCollisions($tableNamePrefix . '_uri', $dsp, $candidateUriPath, $parent->getSiteNodeName(), $selfId, $contentRepositoryId, $workspaceName, $folderLogic, $candidateIsUnroutableFolder ? $parentId : null),
            );
        }

        return $collisions;
    }

    /**
     * Reject a uriPathSegment that a document sibling under the same parent
     * already uses — checked in the command's workspace via the content graph.
     *
     * The projection-based checks only see live (the DocumentUriPath
     * projection ignores all other workspaces), so without this two
     * unpublished siblings could share a segment until one of them is
     * published. Siblings always collide; the unroutable-folder exception
     * of {@see self::queryCollisions()} does not apply.
     */
    public function checkSiblings(
        ContentRepositoryId $contentRepositoryId,
        WorkspaceName $workspaceName,
        ?NodeAggregateId $selfId,
        NodeAggregateId $parentId,
        string $candidateUriPathSegment,
        DimensionSpacePoint $dimensionSpacePoint,
    ): CollisionList {
        $contentRepository = $this->contentRepositoryRegistry->get($contentRepositoryId);
        $contentGraph = $contentRepository->getContentGraph($workspaceName);
        $finder = $contentRepository->projectionState(DocumentUriPathFinder::class);
        $folderLogic = new FolderUriPathLogic(
            $finder,
            $this->dbal,
            DocumentUriPathProjectionFactory::projectionTableNamePrefix($contentRepositoryId),
        );
        // Like `removed = 0` in queryCollisions(): trashed siblings free their segment.
        $visibilityConstraints = VisibilityConstraints::excludeSubtreeTags(SubtreeTags::create(NeosSubtreeTag::removed()));
        $filter = FindChildNodesFilter::create(
            nodeTypes: NodeTypeNameFactory::NAME_DOCUMENT,
            propertyValue: PropertyValueEquals::create(PropertyName::fromString('uriPathSegment'), $candidateUriPathSegment, true),
        );

        $collisions = CollisionList::empty();
        foreach ($contentRepository->getVariationGraph()->getSpecializationSet($dimensionSpacePoint, true) as $dsp) {
            $subgraph = $contentGraph->getSubgraph($dsp, $visibilityConstraints);
            $siblings = $subgraph->findChildNodes($parentId, $filter);
            if ($siblings->isEmpty()) {
                continue;
            }
            // The site is the ancestor directly below the Neos.Neos:Sites root.
            $chain = array_values(array_filter([
                $subgraph->findNodeById($parentId),
                ...$subgraph->findAncestorNodes($parentId, FindAncestorNodesFilter::create()),
            ]));
            // Children of the root are site nodes, whose segments never appear in URLs.
            $siteNodeName = ($chain[count($chain) - 2] ?? null)?->name;
            if ($siteNodeName === null) {
                continue;
            }
            $siteNodeName = SiteNodeName::fromNodeName($siteNodeName);
            // The parent may be unpublished itself, i.e. without projection row.
            try {
                $uriPath = $folderLogic->buildChildUriPath(
                    $candidateUriPathSegment,
                    $finder->getByIdAndDimensionSpacePointHash($parentId, $dsp->hash),
                    $dsp,
                );
            } catch (NodeNotFoundException) {
                $uriPath = $candidateUriPathSegment;
            }
            foreach ($siblings as $sibling) {
                if ($selfId !== null && $sibling->aggregateId->equals($selfId)) {
                    continue;
                }
                $title = $sibling->getProperty('title');
                $label = is_string($title) ? $title : null;
                $collisions = $collisions->with(new Collision(
                    $dsp,
                    $uriPath,
                    $siteNodeName,
                    $sibling->aggregateId,
                    $sibling->nodeTypeName->value,
                    $label,
                ));
            }
        }

        return $collisions;
    }

    /**
     * Whether an existing node is an unroutable folder once the given property
     * changes are applied: changed values win, everything else comes from the
     * node in the given workspace and dimension (not the live-only projection,
     * so unpublished folders are judged correctly too). Feeds `$candidateIsUnroutableFolder`
     * of {@see self::check()} for renames and target-mode changes.
     *
     * @param array<string, mixed> $changedPropertyValues
     */
    public function isUnroutableFolderAfterChange(
        ContentRepositoryId $contentRepositoryId,
        WorkspaceName $workspaceName,
        NodeAggregateId $nodeAggregateId,
        OriginDimensionSpacePoint $originDimensionSpacePoint,
        array $changedPropertyValues,
    ): bool {
        $node = $this->contentRepositoryRegistry->get($contentRepositoryId)
            ->getContentGraph($workspaceName)
            ->getSubgraph($originDimensionSpacePoint->toDimensionSpacePoint(), VisibilityConstraints::createEmpty())
            ->findNodeById($nodeAggregateId);
        if ($node === null) {
            return false;
        }

        $values = [...$node->properties->serialized()->getPlainValues(), ...$changedPropertyValues];
        return FolderUriPathLogic::isUnroutableFolderFor(
            (bool)($values['hideSegmentInUriPath'] ?? false),
            is_string($values['targetMode'] ?? null) ? $values['targetMode'] : null,
        );
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
                'SELECT nodeAggregateId, nodetypename, uriPath, parentnodeaggregateid, hideurisegment, shortcuttarget FROM ' . $tableName . '
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
                $descendant = new DocumentNodeInfo($row);
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
                        $folderInfo->getSiteNodeName(),
                        NodeAggregateId::fromString($row['nodeAggregateId']),
                        $contentRepositoryId,
                        $workspaceName,
                        $folderLogic,
                        // The toggle only moves descendants; their own routability and parent are unchanged.
                        $folderLogic->isUnroutableFolder($descendant) ? $descendant->getParentNodeAggregateId() : null,
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
                $this->queryCollisions($tableNamePrefix . '_uri', $dsp, $candidateUriPath, $newParent->getSiteNodeName(), $nodeAggregateId, $contentRepositoryId, $workspaceName, $folderLogic, $folderLogic->isUnroutableFolder($current) ? $newParentId : null),
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
                $this->queryCollisions($tableNamePrefix . '_uri', $dsp, $candidateUriPath, $parent->getSiteNodeName(), $nodeAggregateId, $contentRepositoryId, $workspaceName, $folderLogic, $folderLogic->isUnroutableFolder($sourceRow) ? $parentId : null),
            );
        }

        return $collisions;
    }

    private function queryCollisions(
        string $tableName,
        DimensionSpacePoint $dimensionSpacePoint,
        string $candidateUriPath,
        SiteNodeName $siteNodeName,
        ?NodeAggregateId $selfId,
        ContentRepositoryId $contentRepositoryId,
        WorkspaceName $workspaceName,
        FolderUriPathLogic $folderLogic,
        ?NodeAggregateId $unroutableCandidateParentId,
    ): CollisionList {
        // uriPaths are site-relative: the same path on two different sites is
        // legal (the router disambiguates via the request's site), so only
        // rows of the candidate's own site can collide.
        // Excludes `removed = 1` rows: the Neos UI's "Delete" action never
        // issues RemoveNodeAggregate (hard delete) -- it tags the subtree as
        // removed (soft delete/trash, see Neos.Neos.Ui's Remove change and
        // {@see NeosSubtreeTag::removed()}), which leaves the row in place.
        // Without this filter, a trashed page permanently blocks its own
        // uriPathSegment from ever being reused.
        $sql = 'SELECT nodeAggregateId, nodetypename, parentnodeaggregateid, hideurisegment, shortcuttarget FROM ' . $tableName . '
                WHERE dimensionSpacePointHash = :dsp AND uriPath = :uri AND siteNodeName = :site
                AND removed = 0';
        $params = ['dsp' => $dimensionSpacePoint->hash, 'uri' => $candidateUriPath, 'site' => $siteNodeName->value];
        if ($selfId !== null) {
            $sql .= ' AND nodeAggregateId != :selfId';
            $params['selfId'] = $selfId->value;
        }

        $subgraph = $this->contentRepositoryRegistry->get($contentRepositoryId)
            ->getContentGraph($workspaceName)
            ->getSubgraph($dimensionSpacePoint, VisibilityConstraints::withoutRestrictions());

        $collisions = CollisionList::empty();
        foreach ($this->dbal->fetchAllAssociative($sql, $params) as $row) {
            // Two unroutable folders under different parents sharing a uriPath
            // are no collision: neither URL can be reached (see
            // FolderUriPathLogic::isUnroutableFolder()). Siblings still collide —
            // segments stay unique per parent.
            // The row is partial, but carries exactly the columns read here.
            if ($unroutableCandidateParentId !== null) {
                $existing = new DocumentNodeInfo($row);
                if (
                    $folderLogic->isUnroutableFolder($existing)
                    && !$existing->getParentNodeAggregateId()->equals($unroutableCandidateParentId)
                ) {
                    continue;
                }
            }
            $nodeId = NodeAggregateId::fromString($row['nodeAggregateId']);
            $node = $subgraph->findNodeById($nodeId);
            $label = $node?->hasProperty('title') ? (string)$node->getProperty('title') : null;
            $collisions = $collisions->with(new Collision(
                $dimensionSpacePoint,
                $candidateUriPath,
                $siteNodeName,
                $nodeId,
                (string)$row['nodetypename'],
                $label,
            ));
        }
        return $collisions;
    }
}
