# URI collision prevention Update

The URI collision prevention was too aggressive when URI path segments were hidden. It was impossible to add /news/2026/09
when /news/2025/09 already existed. That should be possible if the folders have no routing target and their URI segment is hidden.

However, it should not be possible to have two siblings with the same name. Adding a /news/2026/09 folder should throw an
exception, if /news/2026/09 already exists - even as an unpublished change in my personal workspace.

## Exception: unroutable folders

A transparent folder's own row still stores `parent_prefix/segment`, so e.g. hidden month folders `news/2025/09` and `news/2026/09` (years hidden too) both occupy `news/09`. When both rows are **transparent and `targetMode: noTarget`** (`FolderUriPathLogic::isUnroutableFolder()`) **and have different parents**, neither URL is reachable (404, see `NodeControllerAspect`), so step 3 skips such rows for such a candidate. Siblings always collide: segments stay unique per parent. Everything reachable still collides: a page vs. a folder, or a folder that redirects (`firstChildNode`/`selectedTarget`).

- Create: the candidate flag comes from `initialPropertyValues` merged over the NodeType defaults (the hook runs before the CR merges them; the Neos UI sends neither `hideSegmentInUriPath` nor `targetMode`).
- Rename / target-mode change / endpoint: `UriCollisionCheck::isUnroutableFolderAfterChange()` — changed values win, the rest from the row. A `targetMode` change re-checks the node's own uriPath, since leaving `noTarget` makes it reachable.
- Hide toggle / move / variant: the moved row's own routability.

## Behat coverage

`Tests/Behavior/Features/UriCollision/`:

| File | Scenarios | What it locks down |
|---|---|---|
| `Collision_UnroutableFolders.feature` | 12 | Same-named hidden `noTarget` folders under different hidden parents: create / hide toggle / move / rename / endpoint accepted; post, page, redirecting folder, target-mode change and same-parent siblings (create / move / rename) still rejected |
| `Collision_Workspace.feature` | 7 | Unpublished siblings in a user workspace: duplicate folder / page, rename, move and endpoint rejected; cross-year month still accepted; endpoint judges unpublished folders' routability from the workspace |

---

## Known limitation: the multi-user publish race

Within a single workspace, the projection is blind to unpublished nodes. `UriCollisionCheck::checkSiblings()` closes the most common gap: on create, rename and move (hook and endpoint), `uriPathSegment` must be unique among the parent's document children **in the command's workspace**, queried via the workspace-aware content graph. Siblings always collide, even two unroutable folders.

Still uncovered until one side is published:
- effective-URL collisions *across* transparent folders among unpublished nodes (e.g. an unpublished page under a hidden folder vs. an unpublished sibling of that folder);
- the simultaneous-publish race described above.

Everything against already-published nodes is caught by the projection check.
