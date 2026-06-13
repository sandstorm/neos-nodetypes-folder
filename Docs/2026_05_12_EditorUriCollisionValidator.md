# URI collision prevention (Bug E)

Date: 2026-05-12 (plan), updated 2026-05-13 (as-built).
Status: **Defense A + Defense B both implemented and covered by Behat tests.**
Package: `Sandstorm.NodeTypes.Folder` (Neos 9).
Companion to: `2026_05_12_FolderBugfixesDifferentDimensionsAndShortcuts.md`.

Two independent defenses, both required:

- **Defense A — write-side (CQRS command rejection).** Reject the command in the content repository pipeline before any event is written. Authoritative: holds regardless of which client (UI, API, import, CLI) issues the command, and the event store stays free of collision-producing events so replay never re-creates the broken rows. Implemented as `UriCollisionCommandHook`.
- **Defense B — editor-side async validator.** Surfaces the same answer in the inspector ~300 ms after the user stops typing so they see an inline error before clicking Apply, rather than a backend exception after. Pure UX; Defense A is the gate. Implemented as `UriCollisionController` + a TypeScript editor override in `Resources/Private/UriCollisionPlugin/`.

A and B share **the same `UriCollisionCheck` service** — they call it from different sides.

## Why this exists

The Folder package makes folder nodes transparent in URIs. That collapses two normally-disjoint sibling sets — *children-of-folder* and *siblings-of-folder* — into the same effective URL parent. Neos's built-in `uriPathSegment` uniqueness check only compares actual siblings in the node tree, so it does not catch a collision between, e.g.:

```
site
├─ page "Wärme- und Energielösungen"               (uriPathSegment = "waerme-und-energieloesungen")
└─ folder "Weitere Themen"   (transparent)
   └─ shortcut "Wärme- und Energielösungen"        (uriPathSegment = "waerme-und-energieloesungen")
```

Both rows end up with `uriPath = "waerme-und-energieloesungen"` in the same dimension. The router picks one (typically the shortcut), the shortcut redirects to the page node, the page node resolves back to the same `uriPath` — the user observes an **infinite 303 redirect** in the frontend.

We deliberately fix this on the **write side** (editor → command), not in the projection. The projection must not silently rewrite a slug because that would diverge the read model from the command stream.

## Out of scope

- Auto-fix or auto-suffix of slugs in the projection (rejected — projection ≠ command).
- `./flow folder:findUriCollisions` CLI (rejected — surface via the editor instead).
- Router-side tiebreaking (rejected — keeps stale collisions invisible to editors).
- Hotfix for legacy duplicate rows already in the DB. The next manual edit of either side will surface the validator; until then a one-off SQL update or `SetNodeProperties` command can be applied by hand.

---

## Defense A — CQRS write-side rejection (as built)

### Wiring

Registered in `Configuration/Settings.yaml` under the `default` content-repository preset:

```yaml
Neos:
  ContentRepositoryRegistry:
    presets:
      "default":
        commandHooks:
          "Sandstorm.NodeTypes.Folder:PreventUriCollision":
            factoryObjectName: Sandstorm\NodeTypes\Folder\UriCollision\UriCollisionCommandHookFactory
```

`UriCollisionCommandHook::onBeforeHandle()` intercepts four command types:

| Command | What's checked | `UriCollisionCheck` method |
|---|---|---|
| `CreateNodeAggregateWithNode` | New node's prospective URL | `check()` |
| `SetNodeProperties` (uriPathSegment) | Renamed node's prospective URL | `check()` |
| `SetNodeProperties` (hideSegmentInUriPath) | Descendant URLs after the toggle | `checkHideToggle()` |
| `MoveNodeAggregate` | Moved node's prospective URL under new parent | `checkMove()` |
| `CreateNodeVariant` | Variant's URL in the target dimension | `checkVariant()` |

On detection, the hook throws `UriPathCollisionDetected` (extends `\DomainException`). The command never reaches the event store.

### Collision algorithm

Per covered DSP from `OriginDimensionSpacePoint::toDimensionSpacePoint() + variationGraph->getSpecializationSet(…, true)`:

1. Walk the parent chain from the projection (`DocumentUriPathFinder::getByIdAndDimensionSpacePointHash`), skipping ancestors whose `hideurisegment` column is `1`. This is the same walk `FolderUriPathLogic::buildChildUriPath()` does for projection writes.
2. Compute the prospective `uriPath = parent_prefix + '/' + candidateSegment` (or just the segment if `parent_prefix` is empty).
3. `SELECT nodeAggregateId, nodetypename FROM <table> WHERE dimensionSpacePointHash = :dsp AND uriPath = :candidate AND nodeAggregateId != :selfId`. Each row is a `Collision`.

For hide-toggles (`checkHideToggle`), step 1/2 is replaced by enumerating every descendant's post-toggle uriPath via the pure helper `FolderUriPathLogic::computeHideToggledDescendantPath()` and looking each one up.

### Behat coverage

`Tests/Behavior/Features/UriCollision/`:

| File | Scenarios | What it locks down |
|---|---|---|
| `Collision_Create.feature` | 3 | Bug E reproduction; unique segment succeeds; opaque-folder bypass |
| `Collision_Rename.feature` | 3 | Rename to colliding segment rejected; unique rename works; no-op rename accepted |
| `Collision_Move.feature` | 2 | Move into colliding parent rejected; move with conflict removed first works |
| `Collision_Variant.feature` | 2 | Variant into already-occupied target dim rejected; clean variant works |
| `Collision_HideToggle.feature` | 2 | Toggle that would create descendant collision rejected; toggle without conflict works |

---

## Defense B — Editor-side async validator (as built)

### 1. Backend endpoint

`Classes/Controller/UriCollisionController.php`. Single action behind `POST /neos/folder/check-uri-collision`.

Request body:

```json
{
  "workspaceName": "user-jdoe",
  "nodeAggregateId": "bd69f893-…",
  "parentNodeAggregateId": "…",
  "dimensions": { "language": ["en"] },
  "propertyValues": {
    "uriPathSegment": "foo",
    "hideSegmentInUriPath": true
  }
}
```

Notable choices that differ from the original plan:

- **`contentRepositoryId` is NOT in the body.** It's resolved server-side via `SiteDetectionResult::fromRequest($this->request->getHttpRequest())->contentRepositoryId` — the same path `Neos.Neos.Ui`'s `BackendServiceController` uses. `SiteDetectionMiddleware` runs `'before routing'` so the value is always populated by the time the action runs.
- **`dimensions` is accepted in the legacy `{lang: ["en"]}` shape** that `selectors.CR.ContentDimensions.active` returns from the store. The controller normalizes to DSP (`{lang: "en"}`) via `normalizeDimensions()` — it also passes through already-flat payloads, so callers can send either shape.
- The endpoint dispatches to `UriCollisionCheck::check()` when `uriPathSegment` is in the payload, and to `checkHideToggle()` when `hideSegmentInUriPath` is in the payload. Both can be set in a single request.

Response:

- `200 {"ok": true}` if no collisions.
- `409 {"ok": false, "conflicts": [{dimensionSpacePointHash, uriPath, otherNodeAggregateId, otherNodeTypeName}, ...]}` otherwise.

Returned via a direct `GuzzleHttp\Psr7\Response` (Flow's `JsonView` resets `setStatusCode()` so we bypass it).

### 2. Route + auth

`Configuration/Routes.yaml`:

```yaml
-
  name: 'Sandstorm.NodeTypes.Folder UriCollisionController->check'
  uriPattern: 'neos/folder/check-uri-collision'
  defaults:
    '@package': Sandstorm.NodeTypes.Folder
    '@controller': UriCollision
    '@action': check
    '@format': json
  httpMethods: ['POST']
```

`Configuration/Settings.yaml` wires the route position (`before Neos.Neos`) and the backend auth provider.

`Configuration/Policy.yaml` grants the `Neos.Neos:Editor` role access to the controller; production is locked down.

`Configuration/Testing/Behat/Policy.yaml` overrides the policy in `FLOW_CONTEXT=Testing/Behat` to grant `Neos.Flow:Everybody` — the Behat suite doesn't go through the Neos login flow, and this avoids a backend-auth dance in every test. Production policy is untouched.

### 3. Inspector wiring

The research at implementation time confirmed **no YAML-driven async-validator hook exists in Neos 9** (`neos-ui-validators` is `SynchronousRegistry<T>` only, no Promise support). Option A from the plan is therefore not possible; we shipped Option B.

`Resources/Private/UriCollisionPlugin/` is a small TypeScript+esbuild bundle following the same layout `DistributionPackages/Sandstorm.NeosSeoAi` uses. Files:

| Path | Purpose |
|---|---|
| `package.json`, `build.js`, `global.d.ts`, `src/index.ts` | esbuild + extensibility plumbing |
| `src/manifest.ts` | Registers the editor override on `Neos.Neos/Inspector/Editors/UriPathSegmentEditor` |
| `src/CollisionValidatingUriPathSegmentEditor.tsx` | The actual editor — renders the original (TextInput + sync button) + debounced async validation + inline error |

Build output goes to `Resources/Public/UriCollisionPlugin/Plugin.js`; registered in `Configuration/Settings.yaml` under `Neos.Neos.Ui.resources.javascript`.

Key store-shape decisions baked into the editor (resolved by reading `neos-ui-redux-store/src/CR/Nodes/`):

- `selectors.CR.Nodes.focusedSelector` returns the focused Node object; `.identifier` is the `nodeAggregateId`.
- `selectors.CR.Nodes.focusedParentSelector` returns the parent Node (the `parent` field on the focused node is a *context path*, not an aggregate ID — must be looked up). Use `.identifier`.
- `selectors.CR.Workspaces.personalWorkspaceNameSelector` for the workspace.
- `selectors.CR.ContentDimensions.active` for dimensions — legacy `{lang: ["en"]}` shape, normalized server-side.
- `contentRepositoryId` is *not* exposed in the store; resolved server-side (see endpoint section).

CSRF token + 401 re-auth handling: `fetchWithErrorHandling.withCsrfToken(csrfToken => ({…}))` from `@neos-project/neos-ui-backend-connector` — same path the built-in endpoints take in `neos-ui-backend-connector/src/Endpoints/index.ts:57+`. Not a manual `document.querySelector("[data-csrf-token]")` lookup, which would skip the upstream re-login queueing on 401.

Translation: `i18nRegistry.translate("Sandstorm.NodeTypes.Folder:Main:uriCollision.collision.single", fallback, {uriPath})` — XLF files at `Resources/Private/Translations/en/Main.xlf` and `de/Main.xlf`, wired via `userInterface.translation.autoInclude`.

### 4. UX

On collision, an inline error appears below the input ~300 ms after the user stops typing:

> *"This URL would collide with another node (/sibling)."*

While a check is in flight, a subtle "Checking URL availability…" hint appears below.

**Limitations of this v1 UX** (worth iterating later):

- **No hard Apply-block.** The editor shows the inline error but doesn't disable the inspector's Apply button. If the user clicks Apply anyway, Defense A rejects the command server-side and Neos.Neos.Ui surfaces a standard backend error. Two-step UX, but no way to corrupt the projection.
- **Single dimension only.** The check fires for the editor's currently-active DSP. Conflicts in other dimensions surface only when the user switches to them (Defense A still catches multi-DSP collisions on save).
- **No conflict-target labels.** The 409 body identifies the conflicting node by `nodeAggregateId` + node-type name. Showing a human-readable label would require resolving the label per node — out of scope for v1.

### Behat coverage

`Tests/Behavior/Features/UriCollision/Collision_Endpoint.feature` (5 scenarios). Real HTTP via the Flow `Browser` + `InternalRequestEngine` (registered through a small `HttpJsonPostTrait`) — exercises Routes.yaml + Policy.yaml + controller in one go:

- Unique segment → 200.
- Colliding new-child segment → 409 + conflict body.
- Rename to colliding segment → 409.
- No-op rename → 200.
- Hide-toggle that would create descendant collision → 409.

---

## Known limitation: the multi-user publish race

Both Defenses A and B query the **live projection** to detect collisions. The `DocumentUriPathProjection` has no `workspaceName` column and every event handler returns early on non-live (`if (!$event->workspaceName->isLive()) return;`). This is the same model upstream Neos 9 uses.

Consequence: if User A and User B both create a page with `uriPathSegment = "news"` in their personal workspaces and both publish, the second publish silently writes a colliding row into the live projection. The router will then return the first match by DB order; the second page's URL becomes "dark".

This race exists in vanilla Neos 9 today and is not fixed by this package. Solving it would require either a workspace-aware projection, a publish-time replay-into-live check, or a rebase-time pre-flight validation — all of them changes to core CR semantics. Out of scope here.

In practice, the validator catches every collision created within a single workspace's edits, plus every cross-workspace collision created against an already-published page. Only the simultaneous-publish window is uncovered.

## File inventory (as built)

Defense A:

| Path | Status |
|---|---|
| `Classes/UriCollision/UriCollisionCheck.php` | shared service |
| `Classes/UriCollision/Collision.php` | value object |
| `Classes/UriCollision/CollisionList.php` | value object |
| `Classes/UriCollision/UriPathCollisionDetected.php` | typed exception |
| `Classes/UriCollision/UriCollisionCommandHook.php` | implements `CommandHookInterface` |
| `Classes/UriCollision/UriCollisionCommandHookFactory.php` | factory |
| `Configuration/Settings.yaml` | registers hook under preset `commandHooks` |

Defense B:

| Path | Status |
|---|---|
| `Classes/Controller/UriCollisionController.php` | thin wrapper around `UriCollisionCheck`; resolves CR id via `SiteDetectionResult`; normalizes dimensions |
| `Configuration/Routes.yaml` | `POST neos/folder/check-uri-collision` |
| `Configuration/Settings.yaml` | route position + backend auth provider |
| `Configuration/Policy.yaml` | grants Editor role |
| `Configuration/Testing/Behat/Policy.yaml` | grants Everybody in test context |
| `Resources/Private/UriCollisionPlugin/` | TypeScript editor override |
| `Resources/Private/Translations/{en,de}/Main.xlf` | translations for inline error strings |
| `Tests/Behavior/Features/Bootstrap/HttpJsonPostTrait.php` | Behat step definitions for `I POST JSON to URL` + response assertions |
| `Tests/Behavior/Features/UriCollision/Collision_Endpoint.feature` | endpoint coverage |

## What this does NOT cover

- Pre-existing collisions in the projection. They stay until manually edited. The check fires only on *new* commands.
- The publish race (see "Known limitation" above).
- Dimension-config changes that produce collisions in a newly-added dimension. Surfaces as ordinary collisions on the next edit.
- Catching commands that don't originate in the inspector — but **Defense A** is the safety net for REST API, content import, CLI, raw command bus calls. Defense B alone is not sufficient; both layers are required.
