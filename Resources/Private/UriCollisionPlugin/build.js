const esbuild = require("esbuild/lib/main");
const extensibilityMap = require("@neos-project/neos-ui-extensibility/extensibilityMap.json");
const isWatch = process.argv.includes("--watch");

/** @type {import("esbuild/lib/main").BuildOptions} */
const options = {
    logLevel: "info",
    bundle: true,
    target: "es2020",
    entryPoints: { Plugin: "src/index.ts" },
    loader: { ".js": "tsx" },
    outdir: "../../Public/UriCollisionPlugin",
    alias: extensibilityMap,
};

if (isWatch) {
    esbuild.context(options).then((ctx) => ctx.watch());
} else {
    esbuild.build(options);
}
