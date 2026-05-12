# Folder package bugfixes — different dimensions & shortcut/folder URL collisions

Date: 2026-05-12
Package: `Sandstorm.NodeTypes.Folder` (Neos 9)

## Context

The package replaces the core `Neos.Neos:DocumentUriPathProjection` with a folder-aware fork so that nodes of type `Sandstorm.NodeTypes.Folder:Document.Folder` are transparent in URLs (their `uriPathSegment` is omitted when descendants' `uriPath` is built).

A draft PR — <https://github.com/sandstorm/neos-nodetypes-folder/pull/3> — fixes four issues but is not yet integrated. It was checked out into `Packages/Plugins/Sandstorm.NodeTypes.FolderWITHPR/` for reference. Issues PR #3 addresses:

1. EN dimension reused the DE `uriPathSegment` after copy.
2. Folder segment was visible in the EN dimension after copy (folder transparency not applied).
3. The Inspector toggle `hideSegmentInUriPath` had no effect after node creation.
4. Router cache was not flushed when the toggle changed.

In addition, production exhibits an **infinite 303 redirect** caused by a uriPath collision that the package itself enables — see "Bug E" below.

## Bug E — shortcut inside transparent folder collides with sibling-of-folder

Observed tree in one dimension (staging, `cr_default_p_neos_documenturipath_uri`):

```
root (d4786c6a)
└─ site "energielotse" (1284f33f)
   ├─ Document.Technologies "Wärme- und Energielösungen" (bd69f893)
   │     uriPathSegment = waerme-und-energieloesungen
   └─ Folder "Weitere Themen" (6ee8fb65)        ← hideSegmentInUriPath = true
      └─ Shortcut (2473fc26)
            uriPathSegment = waerme-und-energieloesungen
            shortcutTarget = node://bd69f893…
```

Both rows end up with `uriPath = "waerme-und-energieloesungen"` in the same `dimensionSpacePointHash`. Router picks one row (likely the shortcut); shortcut redirects to `node://bd69f893`, URI builder resolves it back to `/waerme-und-energieloesungen`, → router matches the shortcut again → infinite 303.

Root cause: Neos enforces `uriPathSegment` uniqueness among **siblings**. The Folder package collapses two different sibling-sets (children-of-folder and siblings-of-folder) into the same effective URL parent. The invariant `(dimensionSpacePointHash, uriPath)` is silently violated whenever a child-of-folder shares a slug with a sibling-of-folder (or any nephew etc.).

A `subscription:replay` rebuilds from the same events → reproduces the same broken rows.

## Decisions

- **B1-style projection-side auto-suffixing: rejected.** Projection-derived data ≠ command data → editor would show one slug while the URL has another. We fix at the editor (write side).
- **B2-style routing tiebreaker: rejected.**
- **CLI `folder:findUriCollisions` command: out of scope.**
- **Push-back to upstream `sandstorm/neos-nodetypes-folder`:** we maintain the package; no need to keep changes upstream-shaped.
- **Migration data backfill:** no. The migration adds the column only. Existing data is corrected by `subscription:replay` post-deploy.
- **Restore the neos/neos-development-collection#5778 underflow guard** in `whenSubtreeWasUntagged`. PR #3 dropped it; we keep it.
- **No `NodeTypeManager` reads added in the projection.** The default of the new `hideurisegment` column is read from the event's property values (`hideSegmentInUriPath`), not by asking the `NodeTypeManager`. Existing core `NodeTypeManager` reads (`getDocumentTypeClassification`) stay — out of scope.
- **Keep the projection fork close to upstream core ("Step C, C-lean variant"):** drop the defensive parent-chain walk in `generateUriPath`; trust the row's already-correctly-built `uriPath`. Helper shrinks to ~70 LOC.

## Implementation plan

### 1. New file: `FolderUriPathLogic` (~70 LOC)

`Classes/FrontendRouting/Projection/FolderUriPathLogic.php`

All folder-transparency decisions and DB rewrites live here so the forked projection file stays as close to Neos core as possible.

Public API:

- `isTransparentFolder(DocumentNodeInfo $node): bool` — reads the `hideurisegment` column off the row (via `toArray()` so no Neos core class needs patching).
- `hideUriSegmentForInsert(array $propertyValues): int` — pure function over the event's `hideSegmentInUriPath`, defaulting to `0`. **No `NodeTypeManager` lookup.**
- `buildChildUriPath(DocumentNodeInfo $parent, string $segment, ?NodeName $nodeName): string` — `parent.uriPath + '/' + segment` (or `''` for site), no parent-chain walk (C-lean).
- `applyHideToggle(DocumentNodeInfo $folder, bool $newHide, DimensionSpacePoint $dsp): void` — updates the folder row's `hideurisegment` and rewrites every descendant's `uriPath` in one UPDATE (insert or strip the folder segment depending on direction).

Dependencies (constructor): `Connection $dbal`, `string $tableNamePrefix`. No `NodeTypeManager`, no `DocumentUriPathFinder`.

### 2. Fork: `DocumentUriPathProjection.php`

`Classes/FrontendRouting/Projection/DocumentUriPathProjection.php` (already exists; replace).

Goal: keep the file byte-close to upstream core. Every folder-specific change is a single line marked `// PATCH(Folder): …` that delegates to `FolderUriPathLogic`. Target: 5 hunks, ≤ 6 lines each.

Hunks:

1. `determineRequiredSqlStatements()` — use `FolderAwareDocumentUriPathSchemaBuilder` instead of core builder.
2. `whenNodeAggregateWithNodeWasCreated()` — pass `hideUriSegment` into `insertNode()` via `$folderLogic->hideUriSegmentForInsert()`. `uriPath` is built exactly as in core (children of a transparent folder inherit the folder's already-stripped `uriPath`, so `parent.uriPath + '/' + segment` Just Works).
3. `copyVariants()` — replace the inline uriPath rebuild with `$folderLogic->buildChildUriPath(...)`. Fixes #1 + #2 (en-dimension uses target-dim parent uriPath, folder is transparent in target dim).
4. `whenNodePropertiesWereSet()`:
   - Add `hideSegmentInUriPath` to the early-return gate.
   - If `hideSegmentInUriPath` is present in the event → call `$folderLogic->applyHideToggle(...)`. Fixes #3.
   - When `uriPathSegment` changes on a transparent folder, update only the folder's own row (not the cascading core UPDATE, which would corrupt descendants whose paths do not contain the folder segment).
5. `whenSubtreeWasUntagged()` — restore the neos/neos-development-collection#5778 underflow guard that PR #3 dropped.

The existing folder-specific helper methods (`generateUriPath`, `generateParentUriPath`, the inline `isOfType('Folder')` checks) are deleted; their callers either delegate to `FolderUriPathLogic` or revert to the core inline build.

### 3. New file: `FolderAwareDocumentUriPathSchemaBuilder` (already in PR #3)

`Classes/FrontendRouting/Projection/FolderAwareDocumentUriPathSchemaBuilder.php`

Wraps the core `DocumentUriPathSchemaBuilder` and adds:

```sql
hideurisegment INT UNSIGNED NOT NULL DEFAULT 0
```

### 4. Migration

`Migrations/Mysql/Version20260413000000.php`

`up()`:

```sql
ALTER TABLE `cr_default_p_neos_documenturipath_uri`
  ADD COLUMN `hideurisegment` INT UNSIGNED NOT NULL DEFAULT 0
```

No backfill. `subscription:replay` after deploy will populate it correctly from event history.

`down()`: drop the column.

Idempotent on both directions (`hasColumn` checks).

### 5. CatchUpHook: `FolderRouterCacheHook` + factory (already in PR #3)

`Classes/FrontendRouting/CatchUpHook/FolderRouterCacheHook.php`
`Classes/FrontendRouting/CatchUpHook/FolderRouterCacheHookFactory.php`

Listens for `NodePropertiesWereSet` events on the live workspace; if `hideSegmentInUriPath` was changed, collects route cache tags for the node and all descendants, and flushes them via `RouterCachingService`. Fixes #4.

Wired in `Configuration/Settings.yaml`:

```yaml
Neos:
  ContentRepositoryRegistry:
    presets:
      "default":
        projections:
          "Neos.Neos:DocumentUriPathProjection":
            factoryObjectName: Sandstorm\NodeTypes\Folder\FrontendRouting\Projection\DocumentUriPathProjectionFactory
            catchUpHooks:
              "Sandstorm.NodeTypes.Folder:FlushRouteCache":
                factoryObjectName: Sandstorm\NodeTypes\Folder\FrontendRouting\CatchUpHook\FolderRouterCacheHookFactory
```

### 6. Inspector async collision validator (Bug E fix)

Goal: when an editor edits `uriPathSegment` on **node creation OR rename** of any node whose effective URL parent contains a transparent folder, the Inspector blocks save if the resulting `uriPath` would collide with an existing row in `*_documenturipath_uri`.

Components:

- **Controller** `Classes/Controller/UriCollisionController.php`
  - Action `checkAction(string $nodeAggregateId, string $candidateSegment, string $contentRepositoryId, string $workspaceName)`.
  - Resolves the node's effective parent chain (skipping transparent folders), computes the candidate `uriPath` for every covered DimensionSpacePoint, queries `cr_<crId>_p_neos_documenturipath_uri` for `(dimensionSpacePointHash, uriPath)` matches against any node **other than the one being edited**.
  - Returns `200 {ok: true}` or `409 {ok: false, conflicts: [{dimension, otherNodeAggregateId, otherLabel}]}`.
- **Routes** in `Configuration/Routes.yaml` — POST `/sandstorm/folder/check-uri-collision`.
- **Inspector wiring** in `Configuration/NodeTypes.Mixin.HideUriSegment.yaml` (or a new mixin) — add an `editorListeners`/async validator entry on the `uriPathSegment` property that POSTs to the route. Exact mechanism depends on Neos 9 inspector API; if no first-class async validator is available, implement as a small client-side JS package shipped via `Resources/Public/`.
- **Trigger on both create and rename** — bind to the property, not to a lifecycle event, so any inspector edit fires it.

Open implementation question (resolve during build): Neos 9 inspector async validators — is there a built-in YAML mechanism, or does it need a small JS extension via `Neos.Neos.Ui` plugin API? Both are acceptable; pick whichever is simpler at implementation time.

This validator is the **only** collision defense. We deliberately do not:

- silently rewrite the slug in the projection (data would diverge from the command),
- auto-fix existing collisions via a CLI (out of scope per decision).

### 7. Deploy procedure

```
./flow doctrine:migrate
./flow cr:setup
./flow subscription:replay
```

`subscription:replay` is required:

- to populate the new `hideurisegment` column for existing rows,
- to recompute `uriPath` for any row whose old value was built by the pre-PR logic.

## File inventory

| Path | Status | Origin |
|---|---|---|
| `Classes/FrontendRouting/Projection/DocumentUriPathProjection.php` | replace | forked from `Neos.Neos`, ≤ 5 marked hunks |
| `Classes/FrontendRouting/Projection/DocumentUriPathProjectionFactory.php` | keep | existing |
| `Classes/FrontendRouting/Projection/FolderAwareDocumentUriPathSchemaBuilder.php` | new | from PR #3 |
| `Classes/FrontendRouting/Projection/FolderUriPathLogic.php` | new | extracted helper (~70 LOC) |
| `Classes/FrontendRouting/CatchUpHook/FolderRouterCacheHook.php` | new | from PR #3 |
| `Classes/FrontendRouting/CatchUpHook/FolderRouterCacheHookFactory.php` | new | from PR #3 |
| `Classes/Controller/UriCollisionController.php` | new | Bug E |
| `Migrations/Mysql/Version20260413000000.php` | new | from PR #3 (column only, no backfill) |
| `Configuration/Settings.yaml` | extend | catch-up hook wiring |
| `Configuration/Routes.yaml` | new or extend | collision-check route |
| `Configuration/NodeTypes.Mixin.HideUriSegment.yaml` | extend | bind async validator |
| `Resources/Public/...` (optional) | new | JS plugin if needed |

## Out of scope

- Hotfix for the existing duplicate row in production (manual fix, or the editor validator will surface it on the next edit).
- `./flow folder:findUriCollisions` CLI command.
- Backwards-porting the fix to the upstream `sandstorm/neos-nodetypes-folder` repo.
- Replacing the existing `NodeTypeManager` reads inside `getDocumentTypeClassification()` (core inheritance, separate concern).
