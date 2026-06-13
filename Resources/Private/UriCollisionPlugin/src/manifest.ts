import manifest from "@neos-project/neos-ui-extensibility";
import CollisionValidatingUriPathSegmentEditor from "./CollisionValidatingUriPathSegmentEditor";

// Replace the built-in `uriPathSegment` editor with a wrapper that performs an
// async collision check against our backend endpoint. The original editor
// (TextInput + sync-from-title button) is rendered unchanged underneath; we
// only add the validation behavior + an inline error display.
//
// Why globally instead of conditionally: the Folder-package's transparent
// folders can appear anywhere in the document tree, so any document's
// uriPathSegment may end up in a shared URL space. A targeted override (e.g.
// only inside Folder subtrees) would still let editors miss conflicts they
// could prevent — and Defense A would still catch them on the server, so we'd
// just be denying ourselves the inline UX.
manifest("Sandstorm.NodeTypes.Folder:UriCollisionPlugin", {}, (globalRegistry) => {
    const editorsRegistry = globalRegistry.get("inspector").get("editors");

    editorsRegistry.set("Neos.Neos/Inspector/Editors/UriPathSegmentEditor", {
        component: CollisionValidatingUriPathSegmentEditor,
    });
});
