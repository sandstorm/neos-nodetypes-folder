<?php

declare(strict_types=1);

namespace Sandstorm\NodeTypes\Folder\FrontendRouting\Projection;

use Doctrine\DBAL\Connection;
use Neos\ContentRepository\Core\DimensionSpace\DimensionSpacePoint;
use Neos\Neos\FrontendRouting\Exception\NodeNotFoundException;
use Neos\Neos\FrontendRouting\Projection\DocumentNodeInfo;
use Neos\Neos\FrontendRouting\Projection\DocumentUriPathFinder;

/**
 * Folder-specific URI-path logic. Kept in a separate class so the forked
 * DocumentUriPathProjection stays close to Neos.Neos core.
 *
 * Re-sync strategy: copy upstream's projection over ours, then re-apply the
 * marked `PATCH(Folder)` hunks — each is a single delegation into this class.
 */
final class FolderUriPathLogic
{
    /**
     * The Folder NodeType's default `targetMode` (see NodeTypes.Document.Folder.yaml).
     */
    public const SHORTCUT_MODE_NO_TARGET = 'noTarget';

    public function __construct(
        private readonly DocumentUriPathFinder $documentUriPathFinder,
        private readonly Connection $dbal,
        private readonly string $tableNamePrefix,
    ) {
    }

    /**
     * Build the uriPath for a new descendant of $parent with given segment by
     * walking the parent chain in $dsp and skipping transparent folders.
     *
     * Walk is load-bearing, not defensive: a transparent folder's own row stores
     * its own segment in `uriPath`, but descendants must exclude it; the walk
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
     * Like buildChildUriPath but for the parent path only — used by move
     * handling to recompute a new parent prefix in the moved dimension.
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
     * Reads the `hideurisegment` column off the row via DocumentNodeInfo::toArray().
     * No NodeTypeManager lookup at projection time — events are historical, the
     * column is a per-row snapshot of "was this transparent when projected?".
     */
    public function isTransparentFolder(DocumentNodeInfo $node): bool
    {
        return (bool)($node->toArray()['hideurisegment'] ?? false);
    }

    /**
     * A transparent `noTarget` folder's own uriPath answers with 404 (see
     * {@see \Sandstorm\NodeTypes\Folder\Aspect\NodeControllerAspect}), so it
     * is never a URL anyone can reach — two such rows sharing a uriPath are
     * harmless (e.g. `news/2025/09` and `news/2026/09` under hidden years).
     */
    public function isUnroutableFolder(DocumentNodeInfo $node): bool
    {
        return $this->isTransparentFolder($node)
            && $node->isShortcut()
            && $node->getShortcutMode() === self::SHORTCUT_MODE_NO_TARGET;
    }

    /**
     * Same rule as {@see self::isUnroutableFolder()} for a node that has no
     * projection row yet (or whose row is about to change).
     */
    public static function isUnroutableFolderFor(bool $hideSegmentInUriPath, ?string $targetMode): bool
    {
        return $hideSegmentInUriPath && $targetMode === self::SHORTCUT_MODE_NO_TARGET;
    }

    /**
     * Pure: derive the `hideurisegment` column value at row creation from the
     * event's property values.
     */
    public function hideUriSegmentForInsert(array $propertyValues): int
    {
        return (int)($propertyValues['hideSegmentInUriPath'] ?? false);
    }

    /**
     * Apply a hideSegmentInUriPath toggle to a folder row and all its descendants
     * in the given dimension. Updates the folder's `hideurisegment` column and
     * rewrites every descendant's `uriPath` — inserting or stripping the folder
     * segment depending on the direction of the toggle.
     */
    public function applyHideToggle(
        DocumentNodeInfo $folder,
        bool $newHide,
        DimensionSpacePoint $dimensionSpacePoint,
    ): void {
        if ($this->isTransparentFolder($folder) === $newHide) {
            return;
        }

        $folderUriPath = $folder->getUriPath();
        $parentNode = $this->findParent($folder, $dimensionSpacePoint);
        $parentUriPath = $parentNode?->getUriPath() ?? '';

        // 1) flip the folder's own column
        $this->dbal->update(
            $this->tableNamePrefix . '_uri',
            ['hideurisegment' => (int)$newHide],
            [
                'nodeAggregateId' => $folder->getNodeAggregateId()->value,
                'dimensionSpacePointHash' => $dimensionSpacePoint->hash,
            ],
        );

        // 2) rewrite descendants
        $sql = $newHide
            // opaque → transparent: strip folder segment
            ? 'SET uriPath = CONCAT(IF(:parentUriPath = \'\', \'\', CONCAT(:parentUriPath, \'/\')), SUBSTRING(uriPath, LENGTH(:folderUriPath) + 2))
               WHERE dimensionSpacePointHash = :dimensionSpacePointHash
                 AND nodeAggregateId != :folderId
                 AND nodeAggregateIdPath LIKE :childPathPrefix'
            // transparent → opaque: insert folder segment
            : 'SET uriPath = CONCAT(:folderUriPath, \'/\', SUBSTRING(uriPath, IF(:parentUriPath = \'\', 1, LENGTH(:parentUriPath) + 2)))
               WHERE dimensionSpacePointHash = :dimensionSpacePointHash
                 AND nodeAggregateId != :folderId
                 AND nodeAggregateIdPath LIKE :childPathPrefix';

        $this->dbal->executeStatement(
            'UPDATE ' . $this->tableNamePrefix . '_uri ' . $sql,
            [
                'folderUriPath' => $folderUriPath,
                'parentUriPath' => $parentUriPath,
                'dimensionSpacePointHash' => $dimensionSpacePoint->hash,
                'folderId' => $folder->getNodeAggregateId()->value,
                'childPathPrefix' => $folder->getNodeAggregateIdPath() . '/%',
            ],
        );
    }

    /**
     * Pure mirror of the SQL inside {@see self::applyHideToggle()} — given a
     * descendant's current uriPath, compute what it would become after toggling
     * the folder's hide flag. Used by the write-side collision validator to
     * predict post-toggle descendant paths without mutating the DB.
     *
     * Keep in lockstep with the SQL above.
     */
    public function computeHideToggledDescendantPath(
        string $oldPath,
        string $folderUriPath,
        string $parentUriPath,
        bool $newHide,
    ): string {
        if ($newHide) {
            // opaque → transparent: strip folder segment
            $suffix = substr($oldPath, strlen($folderUriPath) + 1);
            return $parentUriPath === '' ? $suffix : $parentUriPath . '/' . $suffix;
        }
        // transparent → opaque: insert folder segment
        $suffix = $parentUriPath === '' ? $oldPath : substr($oldPath, strlen($parentUriPath) + 1);
        return $folderUriPath . '/' . $suffix;
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
