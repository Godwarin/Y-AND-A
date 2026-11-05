import { chromium, expect } from "@playwright/test";
import { spawn } from "node:child_process";
import { writeFile, mkdir, readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import path from "node:path";
import { createServer } from "node:net";
const root = path.resolve(import.meta.dirname, "..");
const exe = path.resolve(
  root,
  process.argv.slice(2).find((a) => !a.startsWith("--")) ??
    "src-tauri/target/debug/y-and-a.exe",
);
const withAirplay = process.argv.includes("--airplay");
const port = 19342;
const child = spawn(exe, [], {
  cwd: path.dirname(exe),
  env: {
    ...process.env,
    WEBVIEW2_USER_DATA_FOLDER: path.join(root, "build/native-smoke-webview"),
    WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS: `--remote-debugging-port=${port} --remote-debugging-address=127.0.0.1`,
  },
  stdio: ["ignore", "pipe", "pipe"],
});
let browser;
let lastEnginePid, sender, previousToken;
const report = {
  kind: "native Tauri/WebView2 smoke; no physical device",
  binary: path.relative(root, exe),
  sha256: createHash("sha256")
    .update(await readFile(exe))
    .digest("hex"),
  androidReceiverSha256: createHash("sha256")
    .update(
      await readFile(
        path.join(path.dirname(exe), "runtime/android-yanda/yanda-android.exe"),
      ).catch(() =>
        readFile(path.join(root, "runtime/android-yanda/yanda-android.exe")),
      ),
    )
    .digest("hex"),
  airplayReceiverSha256:createHash("sha256").update(await readFile(path.join(path.dirname(exe),"runtime/airplay-yanda/airplay-windows.exe")).catch(()=>readFile(path.join(root,"runtime/airplay-yanda/airplay-windows.exe")))).digest("hex"),
  checks: [],
  errors: [],
};
const delay = (ms) => new Promise((r) => setTimeout(r, ms));
async function check(label, fn) {
  await fn();
  report.checks.push(label);
  console.log(`PASS ${label}`);
}
const alive = (pid) => {
  if (!pid) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
};
async function portFree() {
  const server = createServer();
  return new Promise((resolve) => {
    server.once("error", () => resolve(false));
    server.listen(7000, "127.0.0.1", () => server.close(() => resolve(true)));
  });
}
async function runProtocolSuite(page) {
  let approving = false;
  let approvalFailure="";
  const approvals = setInterval(async () => {
    if (approving) return;
    approving = true;
    try {
      const button = page.getByRole("button", {
        name: "Разрешить iPhone",
        exact: true,
      });
      if (await button.isVisible()) {
        const pending=(await page.evaluate(()=>window.__TAURI_INTERNALS__.invoke("status"))).airplayApproval;
        // Public synthetic Ed25519 seed 42 repeated 32 times. Never allow a real sender.
        if(pending?.address!=="127.0.0.1" || pending.fingerprint!=="3097e2dee2cb4a34b53840cdb705aed71067c36f68db0e0f559c3f3fa043315f"){
          approvalFailure="Unexpected external approval request during isolated synthetic test";
          await page.getByRole("button",{name:"Отклонить",exact:true}).click();return;
        }
        if(!report.approvalUiCaptured){await page.screenshot({path:path.join(root,"docs/evidence/native-airplay-approval-fixture.png")});report.approvalUiCaptured=true;}
        await button.click();
      }
    } catch {
    } finally {
      approving = false;
    }
  }, 100);
  try {
    const result = await new Promise((resolve, reject) => {
      const py = spawn(
        path.join(root, ".venv/Scripts/python.exe"),
        [path.join(root, "vendor/airplay-windows/tools/test_pair_verify.py")],
        { cwd: root, windowsHide: true },
      );
      let output = "";
      py.stdout.on("data", (data) => (output += data));
      py.stderr.on("data", (data) => (output += data));
      const timer = setTimeout(() => {
        py.kill();
        reject(new Error("Protocol suite timed out"));
      }, 60000);
      py.on("error", reject);
      py.on("exit", (code) => {
        clearTimeout(timer);
        resolve({ code, output });
      });
    });
    await writeFile(
      path.join(root, "docs/evidence/airplay-protocol.log"),
      result.output,
    );
    if (result.code !== 0)
      throw new Error(
        `AirPlay protocol suite failed, see airplay-protocol.log`,
      );
    if(approvalFailure)throw new Error(approvalFailure);
  } finally {
    clearInterval(approvals);
  }
}
try {
  let endpoint;
  for (let i = 0; i < 80; i++) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}/json/version`);
      endpoint = (await res.json()).webSocketDebuggerUrl;
      if (endpoint) break;
    } catch {}
    if (child.exitCode !== null)
      throw new Error(`Native exited ${child.exitCode}`);
    await delay(250);
  }
  if (!endpoint) throw new Error("WebView2 debugger not started");
  browser = await chromium.connectOverCDP(endpoint);
  const context = browser.contexts()[0];
  let page;
  for (let i = 0; i < 50; i++) {
    page = context.pages().find((p) => !p.url().startsWith("about:"));
    if (page) break;
    await delay(200);
  }
  if (!page) throw new Error("No WebView2 page");
  page.on("pageerror", (e) => report.errors.push(e.message));
  await page
    .getByRole("heading", { name: "Трансляция экрана" })
    .waitFor({ timeout: 20000 });
  const invoke = (command, args = {}) =>
    page.evaluate(
      ({ command, args }) => window.__TAURI_INTERNALS__.invoke(command, args),
      { command, args },
    );
  await check("Desktop IPC and bundled Android receiver/APK", async () => {
    const s = await invoke("status");
    if (!s.companionReady || !s.apkReady)
      throw new Error("Android runtime/APK missing");
    if (await page.locator(".preview-banner").count())
      throw new Error("Preview in desktop");
  });
  await check("Legacy debug source and ADB IPC are rejected", async () => {
    for (const command of ["devices", "wifi_qr_begin", "wifi_via_usb"]) {
      let rejected = false;
      try {
        await invoke(command);
      } catch {
        rejected = true;
      }
      if (!rejected) throw new Error("Legacy IPC still exposed");
    }
    let rejected = false;
    try {
      await invoke("connect", {
        request: { source: "usb", quality: "auto", fps: 0, audio: true },
      });
    } catch {
      rejected = true;
    }
    if (!rejected) throw new Error("Legacy USB source accepted");
  });
  const normalSessionSize = await page.evaluate(() => ({
    width: innerWidth,
    height: innerHeight,
  }));
  await check(
    "Android TLS receiver creates real one-use QR, no false stream",
    async () => {
      await page
        .getByRole("button", { name: "Показать QR-код", exact: true })
        .click();
      await expect
        .poll(async () => (await invoke("status")).phase, { timeout: 20000 })
        .toBe("waiting");
      const s = await invoke("status");
      lastEnginePid = s.enginePid;
      if (!s.embedded || s.resolution)
        throw new Error("False stream or missing HWND");
      await expect(
        page.getByAltText("QR для Android-приложения Y AND A"),
      ).toBeVisible();
      const offer = await invoke("companion_offer");
      const uri = offer.destinations[0]?.payload;
      if (!uri?.startsWith("yanda://connect?v=3&") || offer.expiresIn < 150)
        throw new Error("Invalid offer");
      if (
        s.logs.some(
          (l) => l.includes("token=") || l.includes("YANDA_COMPANION_READY"),
        )
      )
        throw new Error("Secret in diagnostic log");
      sender = spawn(
        path.join(root, ".venv/Scripts/python.exe"),
        [path.join(root, "scripts/send-android-fixture.py")],
        { cwd: root, windowsHide: true, stdio: ["pipe", "pipe", "pipe"] },
      );
      previousToken = new URL(uri).searchParams.get("token");
      sender.stdin.on("error", () => {});
      sender.stdin.write(uri + "\n");
    },
  );
  await check(
    "Real TLS H264 pipeline enters streaming and auto-compacts (synthetic sender)",
    async () => {
      await expect
        .poll(async () => (await invoke("status")).phase, { timeout: 20000 })
        .toBe("streaming");
      await expect
        .poll(async () => (await invoke("status")).resolution)
        .toBe("320 × 640");
      await expect(page.locator(".is-compact")).toBeVisible();
      await expect
        .poll(() => page.evaluate(() => innerWidth))
        .toBeLessThan(600);
      await expect(
        page.getByRole("button", { name: "Остановить", exact: true }),
      ).toBeInViewport();
      await expect(page.locator(".forty-two pre")).toBeInViewport();
      let rejected = false;
      try {
        await invoke("companion_offer");
      } catch {
        rejected = true;
      }
      if (!rejected) throw new Error("Consumed QR exposed");
    },
  );
  await check(
    "Native video pixels are visibly presented after auto-compaction",
    async () => {
      const rect = await page.getByTestId("viewer").boundingBox();
      const scale = await page.evaluate(() => devicePixelRatio);
      const result = await new Promise((resolve, reject) => {
        const p = spawn(
          "powershell.exe",
          [
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            path.join(root, "scripts/assert-native-video.ps1"),
            "-AppId",
            String(child.pid),
            "-X",
            String(Math.round(rect.x * scale)),
            "-Y",
            String(Math.round(rect.y * scale)),
            "-Width",
            String(Math.round(rect.width * scale)),
            "-Height",
            String(Math.round(rect.height * scale)),
          ],
          { cwd: root, windowsHide: true },
        );
        let out = "";
        p.stdout.on("data", (d) => (out += d));
        p.stderr.on("data", (d) => (out += d));
        p.on("error", reject);
        p.on("exit", (code) => resolve({ code, out }));
      });
      if (result.code !== 0) throw new Error(result.out);
      report.nativePixelCheck = result.out.trim();
    },
  );
  await check(
    "Real stream orientation resizes native viewer and compact window",
    async () => {
      sender.stdin.write("rotate\n");
      await expect
        .poll(async () => (await invoke("status")).resolution, {
          timeout: 15000,
        })
        .toBe("640 × 320");
      await expect
        .poll(() => page.evaluate(() => innerWidth > innerHeight))
        .toBe(true);
    },
  );
  await check(
    "Sender disconnect restores UI/window and releases owned receiver",
    async () => {
      sender.stdin.end("stop\n");
      await expect
        .poll(async () => (await invoke("status")).phase, { timeout: 15000 })
        .toBe("idle");
      await expect(page.locator(".is-compact")).toHaveCount(0);
      await expect
        .poll(() =>
          page.evaluate(() => ({ width: innerWidth, height: innerHeight })),
        )
        .toEqual(normalSessionSize);
      await expect.poll(() => alive(lastEnginePid)).toBe(false);
    },
  );
  await check(
    "New Android session has a fresh token; explicit stop cleans it",
    async () => {
      await page
        .getByRole("button", { name: "Показать QR-код", exact: true })
        .click();
      await expect
        .poll(async () => (await invoke("status")).phase, { timeout: 20000 })
        .toBe("waiting");
      lastEnginePid = (await invoke("status")).enginePid;
      const next = await invoke("companion_offer");
      if (
        new URL(next.destinations[0].payload).searchParams.get("token") ===
        previousToken
      )
        throw new Error("QR token reused");
      await invoke("disconnect");
      await expect(
        page.getByAltText("QR для Android-приложения Y AND A"),
      ).toHaveCount(0);

      await expect.poll(() => alive(lastEnginePid)).toBe(false);
    },
  );
  const beforeGeometry = await page.evaluate(() => ({
    width: innerWidth,
    height: innerHeight,
  }));
  await check(
    "Native portrait phone size (geometry fixture, no stream)",
    async () => {
      await invoke("presentation_set", {
        request: { active: true, compact: true, width: 1178, height: 2560 },
      });
      await expect
        .poll(() => page.evaluate(() => innerWidth))
        .toBeLessThan(600);
      const size = await page.evaluate(() => ({
        width: innerWidth,
        height: innerHeight,
      }));
      if (size.height <= size.width || size.width < 320)
        throw new Error("Wrong portrait dimensions");
      if ((await invoke("status")).phase !== "idle")
        throw new Error("Geometry manufactured stream state");
    },
  );
  await check("Native orientation change and interface expansion", async () => {
    await invoke("presentation_set", {
      request: { active: true, compact: true, width: 2560, height: 1178 },
    });
    await expect
      .poll(() => page.evaluate(() => innerWidth > innerHeight))
      .toBe(true);
    await invoke("presentation_set", {
      request: { active: true, compact: false, width: 2560, height: 1178 },
    });
    await expect
      .poll(() =>
        page.evaluate(() => ({ width: innerWidth, height: innerHeight })),
      )
      .toEqual(beforeGeometry);
  });
  await check(
    "Native window restores size and position on session end",
    async () => {
      const position = await invoke("plugin:window|outer_position", {
        label: "main",
      });
      await invoke("presentation_set", {
        request: { active: true, compact: true, width: 1178, height: 2560 },
      });
      await invoke("presentation_set", {
        request: { active: false, compact: false, width: 1, height: 1 },
      });
      await expect
        .poll(() =>
          page.evaluate(() => ({ width: innerWidth, height: innerHeight })),
        )
        .toEqual(beforeGeometry);
      const restored = await invoke("plugin:window|outer_position", {
        label: "main",
      });
      if (JSON.stringify(restored) !== JSON.stringify(position))
        throw new Error("Window position not restored");
    },
  );
  await check(
    "Compact restores maximized and its normal restore rectangle",
    async () => {
      const normal = await page.evaluate(() => ({
        width: innerWidth,
        height: innerHeight,
      }));
      await invoke("plugin:window|toggle_maximize", { label: "main" });
      await expect
        .poll(() => invoke("plugin:window|is_maximized", { label: "main" }))
        .toBe(true);
      await invoke("presentation_set", {
        request: { active: true, compact: true, width: 1178, height: 2560 },
      });
      await invoke("presentation_set", {
        request: { active: false, compact: false, width: 1, height: 1 },
      });
      await expect
        .poll(() => invoke("plugin:window|is_maximized", { label: "main" }))
        .toBe(true);
      await invoke("plugin:window|toggle_maximize", { label: "main" });
      await expect
        .poll(() =>
          page.evaluate(() => ({ width: innerWidth, height: innerHeight })),
        )
        .toEqual(normal);
    },
  );
  await check("Compact preserves a pre-existing fullscreen mode", async () => {
    await invoke("plugin:window|set_fullscreen", {
      label: "main",
      value: true,
    });
    await expect
      .poll(() => invoke("plugin:window|is_fullscreen", { label: "main" }))
      .toBe(true);
    await invoke("presentation_set", {
      request: { active: true, compact: true, width: 1178, height: 2560 },
    });
    await expect
      .poll(() => invoke("plugin:window|is_fullscreen", { label: "main" }))
      .toBe(false);
    await invoke("presentation_set", {
      request: { active: false, compact: false, width: 1, height: 1 },
    });
    await expect
      .poll(() => invoke("plugin:window|is_fullscreen", { label: "main" }))
      .toBe(true);
    await invoke("plugin:window|set_fullscreen", {
      label: "main",
      value: false,
    });
  });
  await check("Always on top control", async () => {
    await page
      .getByRole("button", { name: "Поверх окон", exact: true })
      .click();
    await expect(
      page.getByRole("button", { name: "Поверх окон", exact: true }),
    ).toHaveAttribute("aria-pressed", "true");
    if (!(await invoke("plugin:window|is_always_on_top", { label: "main" })))
      throw new Error("Win32 topmost property false");
    await page
      .getByRole("button", { name: "Поверх окон", exact: true })
      .click();
    await expect(
      page.getByRole("button", { name: "Поверх окон", exact: true }),
    ).toHaveAttribute("aria-pressed", "false");
  });
  await check("Native fullscreen and return", async () => {
    await page
      .getByRole("button", { name: "Полный экран", exact: true })
      .click();
    await page.locator(".is-fullscreen").waitFor();
    if (!(await invoke("plugin:window|is_fullscreen", { label: "main" })))
      throw new Error("Native fullscreen property false");
    await page.getByRole("button", { name: "Выйти из полного экрана" }).click();
    await page.locator(".app:not(.is-fullscreen)").waitFor();
  });
  await page.screenshot({
    path: path.join(root, "docs/evidence/native-desktop.png"),
  });
  if (withAirplay) {
    const request = {
      source: "airplay",
      serial: null,
      endpoint: null,
      quality: "auto",
      fps: 0,
      audio: true,
      audioCodec: "opus",
    };
    await check("AirPlay port conflict rejects a second receiver", async () => {
      if (!(await portFree()))
        throw new Error("Port 7000 was occupied before the test");
      const blocker = createServer();
      await new Promise((r) => blocker.listen(7000, "127.0.0.1", r));
      try {
        let rejected = false;
        try {
          await invoke("connect", { request });
        } catch {
          rejected = true;
        }
        if (!rejected) throw new Error("Port conflict accepted");
      } finally {
        await new Promise((r) => blocker.close(r));
      }
    });
    await page.getByRole("tab", { name: "iPhone AirPlay" }).click();
    const waitReceiver = async () => {
      await expect
        .poll(
          async () => {
            const s = await invoke("status");
            if (s.phase === "error") throw new Error(s.message);
            return s.phase;
          },
          { timeout: 35000 },
        )
        .toBe("waiting");
      const s = await invoke("status");
      if (!s.embedded || s.resolution)
        throw new Error("AirPlay missing native host or claiming fake video");
      lastEnginePid = s.enginePid;
      report.airplayDiscovery = s.logs.filter((l) => l.includes("mDNS"));
    };
    await check(
      "Real AirPlay receiver, native HWND and Windows mDNS registration",
      async () => {
        await page.getByRole("button", { name: "Включить AirPlay" }).click();
        await waitReceiver();
      },
    );
    await check(
      "Upstream AirPlay crypto and media handshake suite (synthetic sender)",
      () => runProtocolSuite(page),
    );
    await page.screenshot({
      path: path.join(root, "docs/evidence/native-airplay.png"),
    });
    await check("AirPlay disconnect releases TCP 7000", async () => {
      await page.getByRole("button", { name: "Остановить трансляцию" }).click();
      await expect
        .poll(async () => (await invoke("status")).phase)
        .toBe("idle");
      await expect.poll(portFree, { timeout: 10000 }).toBe(true);
    });
    await check("Receiver crash keeps the main app alive", async () => {
      await page.getByRole("button", { name: "Включить AirPlay" }).click();
      await waitReceiver();
      process.kill(lastEnginePid);
      await expect
        .poll(async () => (await invoke("status")).phase, { timeout: 10000 })
        .toBe("error");
      await expect(
        page.getByRole("heading", { name: "Трансляция экрана" }),
      ).toBeVisible();
    });
    await check("AirPlay can restart after a crash", async () => {
      await page.getByRole("button", { name: "Включить AirPlay" }).click();
      await waitReceiver();
    });
  }
  await check("Native minimize pauses original animation", async () => {
    await page.getByRole("button", { name: "Свернуть", exact: true }).click();
    await delay(1600);
    if ((await invoke("status")).windowVisible !== false)
      throw new Error("Minimized visibility missing");
    const frame = await page.locator(".forty-two pre").textContent();
    await delay(1200);
    if ((await page.locator(".forty-two pre").textContent()) !== frame)
      throw new Error("Animation still paints while minimized");
  });
  await page
    .getByRole("button", { name: "Закрыть приложение" })
    .click({ force: true });
  for (let i = 0; i < 40 && child.exitCode === null; i++) await delay(200);
  if (child.exitCode === null) throw new Error("Native exit timed out");
  report.checks.push("Graceful native exit");
  await check("Owned child processes exit with the app", async () => {
    await expect
      .poll(() => alive(lastEnginePid), { timeout: 10000 })
      .toBe(false);
    if (withAirplay && !(await portFree()))
      throw new Error("Receiver port leaked after app close");
  });
} catch (e) {
  if (sender && sender.exitCode === null) sender.kill();
  report.failure = e.stack ?? String(e);
  process.exitCode = 1;
  console.error(e);
} finally {
  if (browser) await browser.close().catch(() => {});
  if (child.exitCode === null) child.kill();
  await mkdir(path.join(root, "docs/evidence"), { recursive: true });
  await writeFile(
    path.join(root, "docs/evidence/native-smoke.json"),
    JSON.stringify(report, null, 2),
  );
}
