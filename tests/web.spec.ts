import { test, expect, type Page } from "@playwright/test";
test("главный экран, оригинальная анимация, отсутствие ложной трансляции", async ({
  page,
}) => {
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.goto("/");
  await expect(
    page.getByRole("heading", { name: "Трансляция экрана" }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Показать QR-код" }),
  ).toBeEnabled();
  await expect(
    page.getByText("Веб-просмотр интерфейса.", { exact: false }),
  ).toBeVisible();
  const pre = page.locator(".forty-two pre");
  await expect(pre).toBeVisible();
  const frame = await pre.textContent();
  await expect.poll(() => pre.textContent()).not.toBe(frame);
  await expect(page.getByText("Ваш экран — здесь")).toBeVisible();
  await page.screenshot({
    path: "docs/evidence/ui-desktop.png",
    fullPage: true,
  });
  expect(errors).toEqual([]);
});
test("AirPlay, настройки, сохранение громкости, reduced motion", async ({
  page,
}) => {
  await page.goto("/");
  await page.getByRole("tab", { name: "iPhone AirPlay" }).click();
  await expect(
    page.getByRole("button", { name: "Включить AirPlay" }),
  ).toBeEnabled();
  await expect(
    page.getByText("Пункт управления", { exact: false }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Включить AirPlay" }).click();
  await expect(page.getByRole("alert")).toContainText("десктопную версию");
  await page.getByRole("button", { name: "Настройки", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "Ваш баланс качества" }),
  ).toBeVisible();
  await page.getByRole("slider", { name: "Громкость" }).fill("37");
  await page.reload();
  await expect(page.getByRole("slider", { name: "Громкость" })).toHaveValue(
    "37",
  );
  await page.emulateMedia({ reducedMotion: "reduce" });
  await expect(page.locator(".forty-two img")).toBeVisible();
  await expect(page.locator(".forty-two pre")).toHaveCount(0);
  await page.setViewportSize({ width: 900, height: 800 });
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
  await page.getByRole("tab", { name: "iPhone AirPlay" }).click();
  await expect(
    page.getByRole("button", { name: "Включить AirPlay" }),
  ).toBeInViewport();
  await expect(
    page.getByRole("button", { name: "Полный экран", exact: true }),
  ).toBeInViewport();
  await page.screenshot({
    path: "docs/evidence/ui-compact-airplay.png",
    fullPage: true,
  });
});

test("минимальное окно сохраняет controls и анимацию", async ({ page }) => {
  await page.setViewportSize({ width: 900, height: 650 });
  await page.goto("/");
  await expect(
    page.getByRole("button", { name: "Показать QR-код" }),
  ).toBeInViewport();
  await expect(
    page.getByRole("button", { name: "Полный экран", exact: true }),
  ).toBeInViewport();
  await expect(page.locator(".forty-two pre")).toBeInViewport();
  const rect = await page.getByTestId("viewer").boundingBox();
  expect(rect!.height).toBeGreaterThan(150);
  await page.screenshot({
    path: "docs/evidence/ui-minimum-window.png",
    fullPage: true,
  });
});

test("Android companion без отладки и без ложного QR в web preview", async ({
  page,
}) => {
  await page.goto("/");
  await expect(
    page.getByText("Без кабеля и отладки", { exact: true }),
  ).toBeVisible();
  await expect(page.getByRole("tab")).toHaveCount(2);
  await page
    .getByRole("button", { name: "Показать QR-код", exact: true })
    .click();
  await expect(page.getByRole("alert")).toContainText("десктопную версию");
  await expect(
    page.getByAltText("QR для Android-приложения Y AND A"),
  ).toHaveCount(0);
  await expect(
    page.getByText("Ваш экран — здесь", { exact: true }),
  ).toBeVisible();
  await page.screenshot({
    path: "docs/evidence/ui-android-companion.png",
    animations: "disabled",
  });
});

test("компактная CSS fixture: controls и 42 при ширине телефона, без потока", async ({
  page,
}) => {
  await page.setViewportSize({ width: 360, height: 820 });
  await page.goto("/");
  await page.locator(".app").evaluate((el) => el.classList.add("is-compact"));
  await expect(page.locator(".forty-two pre")).toBeInViewport();
  await expect(
    page.getByRole("button", { name: "Полный экран", exact: true }),
  ).toBeInViewport();
  await expect(
    page.getByRole("slider", { name: "Громкость" }),
  ).toBeInViewport();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
  expect(
    await page
      .locator(".viewer")
      .evaluate((el) => el.getBoundingClientRect().height),
  ).toBeGreaterThan(500);
  await page.screenshot({ path: "docs/evidence/ui-phone-layout-fixture.png" });
});

// IPC fixtures belong only to tests. They exercise UI lifecycle, never prove media.
async function installIpcFixture(page: Page) {
  await page.addInitScript(() => {
    const f = {
      snapshot: {
        phase: "idle",
        source: "android",
        message: "TEST FIXTURE",
        audio: "waiting",
        audioMessage: "TEST FIXTURE",
        resolution: null as string | null,
        elapsed: 0,
        logs: [],
        companionReady: true,
        apkReady: true,
        airplayReady: true,
        embedded: false,
        windowVisible: true,
        airplayApproval: null as {
          requestId: string;
          fingerprint: string;
          address: string;
        } | null,
      },
      calls: [] as { command: string; args: Record<string, unknown> }[],
      ready: false,
    };
    Object.assign(window, {
      isTauri: true,
      yandaTestFixture: f,
      __TAURI_INTERNALS__: {
        metadata: {
          currentWindow: { label: "main" },
          currentWebview: { label: "main" },
        },
        invoke: async (command: string, args: Record<string, unknown> = {}) => {
          f.calls.push({ command, args });
          if (command === "devices") return [];
          if (command === "status") return { ...f.snapshot };
          if (command === "approve_airplay") {
            f.snapshot.airplayApproval = null;
            return null;
          }
          if (command === "presentation_set") return false;
          if (command === "connect") {
            f.snapshot.phase = "waiting";
            return { ...f.snapshot };
          }
          if (command === "disconnect") {
            f.snapshot.phase = "idle";
            f.snapshot.resolution = null;
            return { ...f.snapshot };
          }
          if (command === "companion_offer")
            return {
              destinations: [
                {
                  address: "192.168.1.20",
                  payload:
                    "yanda://connect?v=3&host=192.168.1.20&port=12345&fp=" +
                    "aa".repeat(32) +
                    "&token=" +
                    "ab".repeat(32),
                },
              ],
              expiresIn: 180,
            };
          return null;
        },
      },
    });
  });
}
type FixtureWindow = Window & {
  yandaTestFixture: {
    snapshot: {
      phase: string;
      resolution: string | null;
      airplayApproval?: {
        requestId: string;
        fingerprint: string;
        address: string;
      } | null;
    };
    ready: boolean;
    calls: { command: string; args: Record<string, unknown> }[];
  };
};

test("IPC fixture: iPhone ждёт явного разрешения, отказ и подтверждение адресованы запросу", async ({
  page,
}) => {
  await installIpcFixture(page);
  await page.goto("/");
  const pending = async (id: string) =>
    page.evaluate((requestId) => {
      (window as FixtureWindow).yandaTestFixture.snapshot.airplayApproval = {
        requestId,
        fingerprint: "42".repeat(32),
        address: "192.168.1.42",
      };
    }, id);
  await pending("de".repeat(16));
  await expect(page.getByRole("dialog")).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Отклонить", exact: true }),
  ).toBeFocused();
  expect(
    await page.evaluate(() =>
      (window as FixtureWindow).yandaTestFixture.calls.some(
        (c) => c.command === "approve_airplay",
      ),
    ),
  ).toBe(false);
  await page.getByRole("button", { name: "Отклонить", exact: true }).click();
  await expect
    .poll(() =>
      page.evaluate(
        () =>
          (window as FixtureWindow).yandaTestFixture.calls
            .filter((c) => c.command === "approve_airplay")
            .at(-1)?.args,
      ),
    )
    .toEqual({ requestId: "de".repeat(16), allow: false });
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await pending("ad".repeat(16));
  await expect(page.getByRole("dialog")).toBeVisible();
  await page.screenshot({
    path: "docs/evidence/ui-airplay-approval-fixture.png",
  });
  await page
    .getByRole("button", { name: "Разрешить iPhone", exact: true })
    .click();
  await expect
    .poll(() =>
      page.evaluate(
        () =>
          (window as FixtureWindow).yandaTestFixture.calls
            .filter((c) => c.command === "approve_airplay")
            .at(-1)?.args,
      ),
    )
    .toEqual({ requestId: "ad".repeat(16), allow: true });
  expect(
    await page.evaluate(() =>
      Object.values(localStorage).some((x) =>
        String(x).includes("fingerprint"),
      ),
    ),
  ).toBe(false);
});

test("IPC fixture: реальное ожидание не сжимает UI, stream/rotation/stop вызывают геометрию", async ({
  page,
}) => {
  await installIpcFixture(page);
  await page.goto("/");
  await page.getByRole("tab", { name: "iPhone AirPlay" }).click();
  await page
    .getByRole("button", { name: "Включить AirPlay", exact: true })
    .click();
  await expect(page.locator(".is-compact")).toHaveCount(0);
  await page.evaluate(() => {
    const f = (window as FixtureWindow).yandaTestFixture;
    f.snapshot.phase = "streaming";
    f.snapshot.resolution = "1178 × 2560";
  });
  await expect(page.locator(".is-compact")).toBeVisible();
  await page.setViewportSize({ width: 360, height: 820 });
  await expect(
    page.getByRole("button", { name: "Остановить", exact: true }),
  ).toBeInViewport();
  await expect(
    page.getByRole("button", { name: "Развернуть", exact: true }),
  ).toBeInViewport();
  await expect(page.locator(".forty-two pre")).toBeInViewport();
  await page.evaluate(() => {
    (window as FixtureWindow).yandaTestFixture.snapshot.resolution =
      "2560 × 1178";
  });
  await expect
    .poll(() =>
      page.evaluate(
        () =>
          (window as FixtureWindow).yandaTestFixture.calls
            .filter((c) => c.command === "presentation_set")
            .at(-1)?.args.request,
      ),
    )
    .toMatchObject({ width: 2560, height: 1178, active: true, compact: true });
  await page.getByRole("button", { name: "Развернуть", exact: true }).click();
  await expect(page.locator(".is-compact")).toHaveCount(0);
  await page.setViewportSize({ width: 900, height: 650 });
  await page.getByRole("button", { name: "Компактно", exact: true }).click();
  await expect(page.locator(".is-compact")).toBeVisible();
  await page.getByRole("button", { name: "Остановить", exact: true }).click();
  await expect(page.locator(".is-compact")).toHaveCount(0);
  await expect
    .poll(() =>
      page.evaluate(
        () =>
          (window as FixtureWindow).yandaTestFixture.calls
            .filter((c) => c.command === "presentation_set")
            .at(-1)?.args.request,
      ),
    )
    .toMatchObject({ active: false, compact: false });
});

test("IPC fixture: companion QR, ожидание не объявляется потоком, секрет не сохраняется", async ({
  page,
}) => {
  await installIpcFixture(page);
  await page.goto("/");
  await page
    .getByRole("button", { name: "Показать QR-код", exact: true })
    .click();
  const qr = page.getByAltText("QR для Android-приложения Y AND A");
  await expect(qr).toBeInViewport({ ratio: 1 });
  expect(await qr.evaluate((el: HTMLImageElement) => el.naturalWidth)).toBe(
    320,
  );
  await expect(page.locator(".is-compact")).toHaveCount(0);
  await expect(
    page.getByText("Ждём ваш Android", { exact: true }),
  ).toBeVisible();
  expect(
    await page.evaluate(() =>
      Object.values(localStorage).some((v) => String(v).includes("token=")),
    ),
  ).toBe(false);
  await page
    .locator(".empty-overline")
    .evaluate((el) => (el.textContent = "TEST FIXTURE · ТЕЛЕФОН НЕ ПОДКЛЮЧЁН"));
  await page.setViewportSize({ width: 900, height: 650 });
  await expect(qr).toBeInViewport({ ratio: 1 });
  await expect(page.locator(".forty-two pre")).toBeInViewport();
  await page.screenshot({
    path: "docs/evidence/ui-android-qr-fixture.png",
    animations: "disabled",
  });
  await page
    .getByRole("button", { name: "Отменить подключение", exact: true })
    .click();
  await expect(qr).toHaveCount(0);
});
