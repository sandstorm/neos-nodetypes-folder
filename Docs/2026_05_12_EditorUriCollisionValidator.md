# Plan: URI collision prevention (Bug E)

Date: 2026-05-12
Status: **plan only — not yet implemented**
Package: `Sandstorm.NodeTypes.Folder` (Neos 9)
Companion to: `2026_05_12_FolderBugfixesDifferentDimensionsAndShortcuts.md`

This plan covers **two independent defenses**, both required:

- **Defense A — write-side (CQRS command rejection).** Reject the command in the content repository pipeline before any event is written. This is the authoritative defense: it holds regardless of which client (UI, API, import, CLI) issues the command, and it keeps the event store free of collision-producing events. Without it, every replay re-creates the duplicate row.
- **Defense B — editor-side async validator.** Block the inspector from dispatching a doomed command in the first place, with an inline error message. Pure UX; never the source of truth.

A and B share **the same collision check** (same code path), they just call it from different sides.

## Why this exists

The Folder package makes folder nodes transparent in URIs. That collapses two normally-disjoint sibling sets — *children-of-folder* and *siblings-of-folder* — into the same effective URL parent. Neos's built-in `uriPathSegment` uniqueness check only compares actual siblings in the node tree, so it does not catch a collision between, say:

```
site
├─ page "Wärme- und Energielösungen"               (uriPathSegment = "waerme-und-energieloesungen")
└─ folder "Weitere Themen"   (transparent)
   └─ shortcut "Wärme- und Energielösungen"        (uriPathSegment = "waerme-und-energieloesungen")
```

Both rows end up with `uriPath = "waerme-und-energieloesungen"` in the same dimension. The router picks one (typically the shortcut), the shortcut redirects to the page node, the page node resolves back to the same `uriPath`, and the user observes an **infinite 303 redirect** in the frontend. See the companion doc for the staging incident.

We deliberately fix this on the **write side** (editor → command), not in the projection — see the companion doc's "Decisions" section. The projection must not silently rewrite a slug because that would diverge the read model from the command stream.

## Goal

Block the editor from saving a `uriPathSegment` that would collide with another node's effective `uriPath` in any covered dimension. Fire on **both** node creation and rename of the segment — same code path, same UX.

## Out of scope

- Auto-fix or auto-suffix of slugs in the projection (rejected — projection ≠ command).
- `./flow folder:findUriCollisions` CLI (rejected — surface via the editor instead, and let the next manual edit clear up legacy collisions).
- Router-side tiebreaking (rejected — keeps stale collisions invisible to editors and tooling).
- Hotfix for the one duplicate row already in the staging DB. Next manual edit of either side will surface the validator; in the meantime a one-off SQL update or `SetNodeProperties` command can be applied by hand.

---

## Defense A — CQRS write-side rejection

**Status: plan only — not yet implemented.**

### Goal

When a command would result in two nodes having the same `(dimensionSpacePointHash, effective uriPath)` in any covered dimension, refuse the command in the content repository pipeline. No event is written; the event store stays clean; replay does not re-materialize the collision.

### Commands to intercept

At minimum:

- `CreateNodeAggregateWithNode` — when a new document node would land with a colliding effective uriPath.
- `SetNodeProperties` — when an existing node's `uriPathSegment` is changed (the rename path).
- `SetNodeProperties` — when an existing node's `hideSegmentInUriPath` toggles, which can collapse two previously-distinct URL spaces and create collisions among already-saved descendants.
- (Likely also relevant: `MoveNodeAggregate`, `CreateNodeVariant` / dimension copy commands — moving or copying a node into a transparent-folder subtree can also produce a collision.)

For each, the constraint check needs the node's prospective `uriPathSegment`, the prospective `hideSegmentInUriPath`, and the prospective parent — then derive the effective uriPath in each covered DSP.

### Where to hook in (Neos 9)

Use Neos 9's `CommandHookInterface` — registered per content-repository preset, invoked before the command handler dispatches events. Throwing a domain exception from the hook aborts the command cleanly before any event is appended.

Registration in `Configuration/Settings.yaml` under the preset (alongside the existing `catchUpHooks` block):

```yaml
Neos:
  ContentRepositoryRegistry:
    presets:
      "default":
        commandHooks:
          "Sandstorm.NodeTypes.Folder:PreventUriCollision":
            factoryObjectName: Sandstorm\NodeTypes\Folder\UriCollision\UriCollisionCommandHookFactory
```

The hook implementation inspects the command type, derives the prospective effective uriPath via `UriCollisionCheck`, and throws `UriPathCollisionDetected` if collisions are found. Commands it does not recognise pass through untouched.

### Constraint check (shared with Defense B)

Implement once in a single service, called from both the command hook and the HTTP endpoint:

```
final class UriCollisionCheck
{
    /**
     * @return CollisionList (possibly empty) — listing every (dimension, otherNodeAggregateId)
     *         that the prospective uriPath would collide with.
     */
    public function check(
        ContentRepositoryId $crId,
        WorkspaceName $workspace,
        NodeAggregateId $selfId,            // for new nodes: the prospective id (already known at command time)
        NodeAggregateId $parentId,          // prospective parent
        string $candidateUriPathSegment,
        bool $candidateHideSegmentInUriPath, // whether the node *itself* is transparent
        OriginDimensionSpacePoint $originDsp,
    ): CollisionList;
}
```

Algorithm, per covered DSP:

1. Resolve the parent chain in this DSP from the projection (`getByIdAndDimensionSpacePointHash` for `parentId` and its ancestors). Build the parent prefix by joining segments and skipping any ancestor whose `hideurisegment` column is `1` — same rule the projection itself applies.
2. Determine the candidate's own contribution. If `candidateHideSegmentInUriPath` is true, the node will be transparent → its descendants ignore it (but the node's own row still stores its segment, mirroring the projection's two-rule model — see the companion bugfix doc). For the *collision check on the node itself* this distinction matters: a transparent folder's own row holds `parent_prefix/segment`; a non-transparent or non-folder node's own row holds the same. So the prospective uriPath of the node itself is always `parent_prefix + '/' + candidateUriPathSegment` (or just the segment if `parent_prefix` is empty).
3. Query the projection: `SELECT nodeAggregateId, nodetypename FROM <table> WHERE dimensionSpacePointHash = :dsp AND uriPath = :candidate AND nodeAggregateId != :selfId`. Each row is a collision.
4. **If the toggling node is a folder and `candidateHideSegmentInUriPath` differs from its current value**, the check must also enumerate every descendant's *prospective* new uriPath (post-toggle) and look for collisions among already-saved siblings of the toggling node. This is the "toggle collapses two URL spaces" case. Implementation: derive the new descendant paths the same way `applyHideToggle` does, and look each one up in the projection.

Return all collisions, not just the first — useful for both UX and CLI/API callers.

### Exception contract

Define a typed exception in this package:

```
final class UriPathCollisionDetected extends \DomainException implements ConstraintViolation
{
    public function __construct(public readonly CollisionList $collisions) { ... }
}
```

The command hook throws it. The HTTP controller in Defense B catches it (or the equivalent of it from its own call site) and renders the same `409` body. The CLI / API path gets a clean error.

### Tests

Two integration tests (functional, against a real DB):

- Create a Document.Technologies page "/foo", then attempt to create a Shortcut "/foo" inside a transparent folder that is a sibling of the page → expect `UriPathCollisionDetected`.
- Toggle a folder from opaque to transparent when one of its descendants' resulting transparent uriPath would collide with the folder's own sibling → expect `UriPathCollisionDetected`.

### What this does NOT cover

- Pre-existing collisions in the projection. They stay until manually edited. The check fires only on *new* commands.
- Dimension-config changes (adding a new dimension that suddenly causes collisions in the new dimension's projected rows). Out of scope; surfaces as ordinary collisions on the next edit.

---

## Defense B — Editor-side async validator

## Components

### 1. Backend endpoint

`Classes/Controller/UriCollisionController.php` — a Flow `ActionController` with a single action:

```
POST /sandstorm/folder/check-uri-collision
Body (JSON):
  {
    "contentRepositoryId": "default",
    "workspaceName": "user-jdoe",
    "nodeAggregateId": "bd69f893-…",
    "candidateUriPathSegment": "waerme-und-energieloesungen"
  }
```

Behavior:

1. Resolve the node via `ContentRepositoryRegistry::get(...)->getContentGraph($workspaceName)`. From it, get the node's covered dimension space points.
2. For each covered DSP:
   - Build the candidate `uriPath` the way the projection would: walk up the parent chain, skipping nodes whose `hideSegmentInUriPath` is true (or — equivalently for the projection's view — whose `hideurisegment` column is 1). Append `candidateUriPathSegment` at the end.
   - Query `cr_<crId>_p_neos_documenturipath_uri` for rows with `(dimensionSpacePointHash = :dsp AND uriPath = :candidate AND nodeAggregateId != :selfId)`.
3. Return:
   - `200 {ok: true}` if no collisions.
   - `409 {ok: false, conflicts: [{dimension: "<label>", otherNodeAggregateId: "…", otherLabel: "…"}, ...]}` otherwise.

Notes:

- Query the projection table directly — same source of truth the router uses, so the validator surfaces exactly the problem that would manifest at runtime.
- For *new* nodes that don't have a `nodeAggregateId` yet (creation flow), the inspector typically already knows the new ID. If it doesn't, accept the parent node ID + intended position and compute the would-be `uriPath` ignoring the not-yet-existing row.
- Compute the parent's `uriPath` from the projection too (`getByIdAndDimensionSpacePointHash`) rather than walking the content graph — guarantees consistency with the read model.

### 2. Route

Add to `Configuration/Routes.yaml`:

```yaml
-
  name: 'Sandstorm.NodeTypes.Folder :: check uri collision'
  uriPattern: 'sandstorm/folder/check-uri-collision'
  defaults:
    '@package':    Sandstorm.NodeTypes.Folder
    '@controller': UriCollision
    '@action':     check
    '@format':     json
  httpMethods: ['POST']
```

Plus the standard Neos `Settings.yaml` `Neos.Flow.mvc.routes.Sandstorm.NodeTypes.Folder: true` entry (or whatever pattern matches the package's existing route registration — confirm at implementation time).

### 3. Inspector wiring

Open question — pick one at implementation time:

- **Option A: built-in async validator (preferred if it exists in this Neos 9 version).** Some Neos 9 builds expose an inspector validator that accepts a server endpoint via YAML:

  ```yaml
  # Configuration/NodeTypes.Mixin.UriPathSegment.yaml (or wherever the property lives)
  'Neos.Neos:Document':
    properties:
      uriPathSegment:
        ui:
          inspector:
            editorOptions:
              # speculative name; verify against the running Neos version
              asyncValidator:
                endpoint: '/sandstorm/folder/check-uri-collision'
                errorMessage: 'This URL is already in use by another node ({otherLabel}).'
  ```

  If a built-in mechanism exists, this is preferred — zero JS shipped from this package.

- **Option B: small JS plugin via `Neos.Neos.Ui` plugin API.** If no built-in async validator exists, ship a tiny TypeScript/JS plugin under `Resources/Private/UriCollisionPlugin/` that:
  - subscribes to inspector value changes for `uriPathSegment`,
  - debounces ~300ms,
  - calls the endpoint,
  - sets a validation error on the inspector field on `409`,
  - clears it on `200`.

  Build output goes to `Resources/Public/JavaScript/UriCollisionPlugin.js`, registered via the standard `Neos.Neos.Ui` plugin manifest.

The endpoint and contract are identical in both options — the JS bit just becomes optional plumbing.

### 4. UX

On collision:

> *"This URL would collide with «Wärme- und Energielösungen» in dimension DE. Please choose a different URL path segment."*

Show one entry per conflict (there may be more than one when multiple dimensions are affected). Block the inspector's save action until the segment is changed.

## Trigger surface

Bind to the `uriPathSegment` property, **not** to a lifecycle hook. The inspector fires the validator on:

- initial creation of the node (before the `CreateNodeAggregateWithNode` command is dispatched), and
- rename (before `SetNodeProperties`).

Both flows use the same endpoint. No separate "rename" path is needed.

## Open implementation questions to resolve at build time

1. Does the running Neos 9 expose a YAML-driven async validator hook? If not → Option B.
2. What exactly does the inspector send as `nodeAggregateId` for a *new* (unsaved) node? If a placeholder, the endpoint must tolerate a missing/null `selfId`.
3. Are dimensions exposed to the editor by label or by hash? Translate hashes to labels in the response for a useful error message.
4. Is there a workspace-aware lookup in the projection, or do we always query the live `*_uri` table? (Probably live — the projection is single-workspace per content repository in Neos 9. Verify.)
5. CSRF / auth: the controller must require the Neos backend auth. Use the same `Policy.yaml` pattern as other backend endpoints in this codebase.

## Not done by this validator

- **Catching commands that don't originate in the inspector.** Defense A is the safety net for any other client (REST API, content import, CLI, raw command bus calls). Defense B alone is *not* sufficient.
- Cleaning up legacy duplicate rows. Will surface on the next manual edit of either side. If that's not acceptable in a given environment, the operator can dispatch a `SetNodeProperties` command for one of the colliding nodes by hand.
- Detecting collisions caused by changes *elsewhere* (e.g. someone toggles a folder to transparent, which collapses two previously-distinct URL spaces and creates collisions among already-saved nodes). Those will surface when an editor next touches one of the affected nodes. Defense A's toggle-handling clause (see above) covers the *new* toggle command itself; old collisions left by past toggles still need a manual edit.

## File inventory (when implemented)

Defense A (write side):

| Path | Status |
|---|---|
| `Classes/UriCollision/UriCollisionCheck.php` | new — shared service |
| `Classes/UriCollision/CollisionList.php` | new — value object |
| `Classes/UriCollision/UriPathCollisionDetected.php` | new — typed exception |
| `Classes/UriCollision/UriCollisionCommandHook.php` | new — implements `CommandHookInterface` |
| `Classes/UriCollision/UriCollisionCommandHookFactory.php` | new |
| `Configuration/Settings.yaml` | extend — register under the preset's `commandHooks` block |

Defense B (editor side):

| Path | Status |
|---|---|
| `Classes/Controller/UriCollisionController.php` | new — thin wrapper around `UriCollisionCheck` |
| `Configuration/Routes.yaml` | new or extend |
| `Configuration/Policy.yaml` | extend (grant editors access to the endpoint) |
| `Configuration/NodeTypes.*.yaml` | extend (bind validator to `uriPathSegment`) — only if Option A |
| `Resources/Private/UriCollisionPlugin/` + `Resources/Public/...` | new — only if Option B |
