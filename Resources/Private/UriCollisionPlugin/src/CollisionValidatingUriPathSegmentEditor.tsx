import React, { useEffect, useRef, useState } from "react";
import { useSelector } from "react-redux";
import { selectors } from "@neos-project/neos-ui-redux-store";
import { TextInput, IconButton } from "@neos-project/react-ui-components";
import backend, { fetchWithErrorHandling } from "@neos-project/neos-ui-backend-connector";
import { neos } from "@neos-project/neos-ui-decorators";
import unescape from "lodash.unescape";

/**
 * Drop-in replacement for the built-in `uriPathSegment` editor that adds an
 * async collision check against our `neos/folder/check-uri-collision`
 * endpoint. Below the input we render an inline error when the prospective
 * segment would collide; otherwise the editor behaves identically to the
 * built-in one.
 *
 * Defense A (the command hook) is still the authoritative line of defense —
 * this editor exists to surface the same answer ~300ms after the user stops
 * typing instead of after they hit Apply.
 */

interface Conflict {
    dimensionSpacePointHash: string;
    uriPath: string;
    otherNodeAggregateId: string;
    otherNodeTypeName: string;
}

interface EditorProps {
    id?: string;
    value: string;
    commit: (value: string) => void;
    options?: {
        autoFocus?: boolean;
        disabled?: boolean;
        readonly?: boolean;
        maxlength?: number;
        placeholder?: string;
        title?: string;
    };
    onKeyPress?: () => void;
    onEnterKey?: () => void;
    i18nRegistry: {
        translate: (
            id: string,
            fallback?: string,
            args?: Record<string, unknown>,
            packageKey?: string,
            sourceName?: string,
        ) => string;
    };
}

const DEBOUNCE_MS = 300;

const translateCollision = (
    i18n: EditorProps["i18nRegistry"],
    conflicts: Conflict[],
): string => {
    if (conflicts.length === 1) {
        return i18n.translate(
            "Sandstorm.NodeTypes.Folder:Main:uriCollision.collision.single",
            `This URL would collide with another node (${conflicts[0].uriPath}).`,
            { uriPath: conflicts[0].uriPath },
        );
    }
    return i18n.translate(
        "Sandstorm.NodeTypes.Folder:Main:uriCollision.collision.many",
        `This URL would collide with ${conflicts.length} other nodes.`,
        { count: conflicts.length },
    );
};

const Component: React.FC<EditorProps> = ({
    id,
    value,
    commit,
    options = {},
    onKeyPress,
    onEnterKey,
    i18nRegistry,
}) => {
    const focusedNode = useSelector(selectors.CR.Nodes.focusedSelector);
    const focusedParent = useSelector(selectors.CR.Nodes.focusedParentSelector);
    const workspaceName = useSelector(
        selectors.CR.Workspaces.personalWorkspaceNameSelector,
    );
    const dimensions = useSelector(selectors.CR.ContentDimensions.active);

    const [conflicts, setConflicts] = useState<Conflict[]>([]);
    const [checking, setChecking] = useState(false);
    const [isBusy, setIsBusy] = useState(false);
    const debounceHandle = useRef<ReturnType<typeof setTimeout> | null>(null);
    const inflightId = useRef(0);

    // Debounced collision check on value change.
    useEffect(() => {
        if (debounceHandle.current) clearTimeout(debounceHandle.current);

        const selfId = focusedNode?.identifier;
        const parentId = focusedParent?.identifier;
        if (!value || !selfId || !parentId) {
            setConflicts([]);
            return;
        }

        debounceHandle.current = setTimeout(() => {
            // contentRepositoryId is resolved server-side from SiteDetection;
            // dimensions are normalized server-side from the legacy shape.
            const payload = {
                workspaceName,
                nodeAggregateId: selfId,
                parentNodeAggregateId: parentId,
                dimensions,
                propertyValues: { uriPathSegment: value },
            };

            const requestId = ++inflightId.current;
            setChecking(true);

            fetchWithErrorHandling
                .withCsrfToken((csrfToken: string) => ({
                    url: "/neos/folder/check-uri-collision",
                    method: "POST",
                    credentials: "include",
                    headers: {
                        "Content-Type": "application/json",
                        "X-Flow-Csrftoken": csrfToken,
                    },
                    body: JSON.stringify(payload),
                }))
                .then(async (res: Response) => {
                    // Drop stale results — a newer keystroke already fired.
                    if (requestId !== inflightId.current) return;
                    const data = await res.json().catch(() => ({}));
                    if (res.status === 409 && Array.isArray(data.conflicts)) {
                        setConflicts(data.conflicts as Conflict[]);
                    } else {
                        setConflicts([]);
                    }
                })
                .catch(() => {
                    if (requestId !== inflightId.current) return;
                    // Network/server failure — clear conflicts so we don't show stale errors.
                    // Defense A is still the authoritative gate.
                    setConflicts([]);
                })
                .finally(() => {
                    if (requestId === inflightId.current) {
                        setChecking(false);
                    }
                });
        }, DEBOUNCE_MS);

        return () => {
            if (debounceHandle.current) clearTimeout(debounceHandle.current);
        };
    }, [
        value,
        focusedNode?.identifier,
        focusedParent?.identifier,
        workspaceName,
        dimensions,
    ]);

    // Sync-from-title button (mirrors the upstream editor).
    const generatePathSegment = async () => {
        const title = options?.title || "";
        const { generateUriPathSegment } = backend.get().endpoints;
        const contextPath = focusedNode?.contextPath || "";
        setIsBusy(true);
        try {
            const slug = await generateUriPathSegment(contextPath, title);
            commit(slug);
        } finally {
            setIsBusy(false);
        }
    };

    const finalOptions = {
        autoFocus: false,
        disabled: false,
        readonly: false,
        maxlength: undefined as number | undefined,
        ...options,
    };
    const showSyncButton = !(finalOptions.readonly || finalOptions.disabled);
    const placeholder =
        options?.placeholder &&
        i18nRegistry.translate(unescape(options.placeholder));

    return (
        <div>
            <div style={{ display: "flex" }}>
                <div style={{ flexGrow: 1 }}>
                    <TextInput
                        id={id}
                        autoFocus={finalOptions.autoFocus}
                        value={value}
                        onChange={commit}
                        placeholder={placeholder}
                        onKeyPress={onKeyPress}
                        onEnterKey={onEnterKey}
                        disabled={finalOptions.disabled || isBusy}
                        maxLength={finalOptions.maxlength}
                        readOnly={finalOptions.readonly}
                    />
                </div>
                {showSyncButton ? (
                    <div style={{ flexGrow: 0 }}>
                        <IconButton
                            id="neos-UriPathSegmentEditor-sync"
                            size="regular"
                            icon="sync"
                            iconProps={isBusy ? { spin: true } : undefined}
                            onClick={generatePathSegment}
                            disabled={isBusy}
                            style="neutral"
                            hoverStyle="clean"
                        />
                    </div>
                ) : null}
            </div>
            {conflicts.length > 0 ? (
                <div
                    style={{
                        marginTop: 6,
                        color: "var(--colors-Error, #ff5050)",
                        fontSize: 12,
                    }}
                    role="alert"
                >
                    {translateCollision(i18nRegistry, conflicts)}
                </div>
            ) : null}
            {checking && conflicts.length === 0 ? (
                <div style={{ marginTop: 6, fontSize: 12, opacity: 0.6 }}>
                    {i18nRegistry.translate(
                        "Sandstorm.NodeTypes.Folder:Main:uriCollision.checking",
                        "Checking URL availability…",
                    )}
                </div>
            ) : null}
        </div>
    );
};

// Wire `i18nRegistry` via the `@neos` decorator so translations work the same
// way as in the built-in editor.
export default neos((globalRegistry: any) => ({
    i18nRegistry: globalRegistry.get("i18n"),
}))(Component);
