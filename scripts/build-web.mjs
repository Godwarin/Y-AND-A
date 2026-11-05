import { spawnSync } from "node:child_process";
import path from "node:path";
const runner = path.join(import.meta.dirname, "run-tool.mjs");
for (const args of [
  ["tsc", "-b"],
  ["vite", "build"],
]) {
  const result = spawnSync(process.execPath, [runner, ...args], {
    stdio: "inherit",
    windowsHide: true,
  });
  if (result.error) throw result.error;
  if (result.status) process.exit(result.status);
}
