#!/usr/bin/env bun

import { $ } from "bun"
import path from "path"
import fs from "fs"
import { fileURLToPath } from "url"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(__dirname, "..")
const outdir = path.join(root, "dist-bundle")

// Clean output dir
await $`rm -rf ${outdir}`
fs.mkdirSync(outdir, { recursive: true })

console.log("Generating prompts...")
await $`bun run generate:prompts`.cwd(root)

console.log("Bundling plugin...")
const result = await Bun.build({
    entrypoints: [path.join(root, "index.ts")],
    outdir,
    target: "bun",
    format: "esm",
    minify: false,
    external: [],
})

if (!result.success) {
    for (const log of result.logs) {
        console.error(log)
    }
    process.exit(1)
}

// Copy wasm file next to the bundle (tiktoken CJS loader checks __dirname first)
const wasmSrc = path.join(root, "node_modules", "tiktoken", "lite", "tiktoken_bg.wasm")
const wasmDst = path.join(outdir, "tiktoken_bg.wasm")
fs.copyFileSync(wasmSrc, wasmDst)

// Fix: Bun inlines __dirname as the build machine's absolute path.
// Replace the hardcoded tiktoken __dirname with a runtime resolution
// so the wasm file is found relative to the bundle's actual location.
const bundlePath = path.join(outdir, "index.js")
let bundleContent = fs.readFileSync(bundlePath, "utf8")
const hardcodedDir = path.join(root, "node_modules", "tiktoken", "lite")
if (bundleContent.includes(JSON.stringify(hardcodedDir))) {
    bundleContent = bundleContent.replace(
        `var __dirname = ${JSON.stringify(hardcodedDir)}`,
        `var __dirname = new URL(".", import.meta.url).pathname`,
    )
    fs.writeFileSync(bundlePath, bundleContent)
    console.log("Patched tiktoken __dirname to resolve at runtime")
} else {
    console.warn("Warning: could not find hardcoded tiktoken __dirname to patch")
}

console.log("\nBundle output:")
for (const file of fs.readdirSync(outdir)) {
    const size = fs.statSync(path.join(outdir, file)).size
    const kb = (size / 1024).toFixed(0)
    console.log(`  ${file.padEnd(30)} ${kb} KB`)
}

console.log(`\nDone. To use:\n  "plugin": ["file://${outdir}/index.js"]`)
