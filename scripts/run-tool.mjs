import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
const root = path.resolve(import.meta.dirname, "..");
const versionFile = path.join(root, "toolchain/node-version.txt");
const version = existsSync(versionFile)
  ? readFileSync(versionFile, "utf8").trim()
  : "";
const localNode = path.join(
  root,
  "toolchain",
  `node-${version}-win-x64`,
  "node.exe",
);
const node = existsSync(localNode) ? localNode : process.execPath;
const commands = {
  vite: "vite/bin/vite.js",
  tsc: "typescript/bin/tsc",
  vitest: "vitest/vitest.mjs",
  tauri: "@tauri-apps/cli/tauri.js",
  eslint: "eslint/bin/eslint.js",
  prettier: "prettier/bin/prettier.cjs",
  playwright: "@playwright/test/cli.js",
};
const [tool, ...args] = process.argv.slice(2);
if (!(tool in commands)) throw new Error(`Unknown project tool: ${tool}`);
const result = spawnSync(
  node,
  [path.join(root, "node_modules", commands[tool]), ...args],
  {
    cwd: root,
    stdio: "inherit",
    windowsHide: true,
    env: {
      ...process.env,
      PATH: `${path.dirname(node)}${path.delimiter}${process.env.PATH ?? ""}`,
    },
  },
);
if (result.error) throw result.error;
process.exit(result.status ?? 1);
