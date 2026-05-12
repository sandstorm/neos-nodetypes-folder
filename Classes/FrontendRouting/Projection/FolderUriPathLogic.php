<?php

declare(strict_types=1);

namespace Sandstorm\NodeTypes\Folder\FrontendRouting\Projection;

use Neos\ContentRepository\Core\DimensionSpace\DimensionSpacePoint;
use Neos\ContentRepository\Core\NodeType\NodeTypeManager;
use Neos\Neos\FrontendRouting\Exception\NodeNotFoundException;
use Neos\Neos\FrontendRouting\Projection\DocumentNodeInfo;
use Neos\Neos\FrontendRouting\Projection\DocumentUriPathFinder;

/**
 * Folder-specific URI-path logic. Kept in a separate class so the forked
 * DocumentUriPathProjection stays close to Neos.Neos core.
 *
 * Re-sync strategy: copy upstream's projection over ours, then re-apply the
 * marked `PATCH(Folder)` hunks — each is a single delegation into this class.
 *
 * Will grow in subsequent commits with:
 *  - isTransparentFolder() — swap NodeTypeManager check for a row-column read
 *  - hideUriSegmentForInsert() — pure function over event property values
 *  - applyHideToggle() — rewrites descendant uriPaths when the toggle changes
 */
final class FolderUriPathLogic
{
    public function __construct(
        private readonly NodeTypeManager $nodeTypeManager,
        private readonly DocumentUriPathFinder $documentUriPathFinder,
    ) {
    }

    /**
     * Build the uriPath for a new descendant of $parent with given segment by
     * walking the parent chain in $dsp and skipping transparent folders.
     *
     * Walk is load-bearing, not defensive: a transparent folder's own row stores
     * its own segment in `uriPath`, but descendants must exclude it. The walk
     * reconciles the two rules.
     */
    public function buildChildUriPath(
        string $uriPathSegment,
        DocumentNodeInfo $parent,
        DimensionSpacePoint $dimensionSpacePoint,
    ): string {
        $uriPath = $uriPathSegment;
        $current = $parent;
        while (!$current->isRoot()) {
            if (!$this->isTransparentFolder($current)) {
                $basename = basename($current->getUriPath());
                if ($basename !== '') {
                    $uriPath = $basename . '/' . $uriPath;
                }
            }
            $current = $this->findParent($current, $dimensionSpacePoint);
            if ($current === null) {
                break;
            }
        }
        return $uriPath;
    }

    /**
     * Like buildChildUriPath but for the parent path only (no own segment) —
     * used by move handling to recompute a new parent prefix in the moved dim.
     */
    public function buildParentUriPath(
        DocumentNodeInfo $parent,
        DimensionSpacePoint $dimensionSpacePoint,
    ): string {
        $segments = [];
        $current = $parent;
        while (!$current->isRoot()) {
            if (!$this->isTransparentFolder($current)) {
                $basename = basename($current->getUriPath());
                if ($basename !== '') {
                    array_unshift($segments, $basename);
                }
            }
            $current = $this->findParent($current, $dimensionSpacePoint);
            if ($current === null) {
                break;
            }
        }
        return implode('/', $segments);
    }

    /**
     * Placeholder — reads NodeTypeManager today (pre-existing tech debt copied
     * from the prior generateUriPath implementation). C4 swaps this for a
     * `hideurisegment` column read off $node->toArray() so the projection no
     * longer asks the NodeTypeManager at apply time.
     */
    private function isTransparentFolder(DocumentNodeInfo $node): bool
    {
        $nodeType = $this->nodeTypeManager->getNodeType($node->getNodeTypeName());
        return $nodeType !== null && $nodeType->isOfType('Sandstorm.NodeTypes.Folder:Document.Folder');
    }

    private function findParent(DocumentNodeInfo $node, DimensionSpacePoint $dimensionSpacePoint): ?DocumentNodeInfo
    {
        try {
            return $this->documentUriPathFinder->getByIdAndDimensionSpacePointHash(
                $node->getParentNodeAggregateId(),
                $dimensionSpacePoint->hash,
            );
        } catch (NodeNotFoundException $_) {
            return null;
        }
    }
}
