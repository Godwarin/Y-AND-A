import React, { useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import { getCurrentWindow } from "@tauri-apps/api/window";
import {
  ArrowRight,
  AudioLines,
  Check,
  ChevronDown,
  CircleHelp,
  Copy,
  Expand,
  Headphones,
  Info,
  LoaderCircle,
  Minimize,
  Minus,
  Monitor,
  MonitorSmartphone,
  Pin,
  Radio,
  Settings2,
  ShieldCheck,
  Smartphone,
  Square,
  Unplug,
  Volume2,
  VolumeX,
  Wifi,
  X,
} from "lucide-react";
import { FortyTwo } from "./FortyTwo";
import { AndroidConnection } from "./AndroidConnection";
import { api, call, desktop } from "./api";
import {
  duration,
  initial,
  loadPreferences,
  phaseLabels,
  sourceNames,
  type Preferences,
  type Snapshot,
  type Source,
} from "./model";
import "./styles.css";

const sources: {
  id: Source;
  title: string;
  subtitle: string;
  icon: typeof Smartphone;
}[] = [
  {
    id: "android",
    title: "Android",
    subtitle: "Приложение · QR",
    icon: Smartphone,
  },
  { id: "airplay", title: "iPhone", subtitle: "AirPlay", icon: Radio },
];
const guides: Record<Source, string[]> = {
  android: [
    "Установите Android-приложение Y AND A из APK рядом с этой программой.",
    "Нажмите «Показать QR-код» и отсканируйте его в приложении на телефоне.",
    "На телефоне нажмите «Начать трансляцию» и разрешите показ экрана.",
  ],
  airplay: [
    "Подключите iPhone и ПК к одной локальной сети.",
    "Запустите приёмник кнопкой «Включить AirPlay».",
    "На iPhone: Пункт управления → Повтор экрана → Y AND A. Затем разрешите подключение на ПК.",
  ],
};

function App() {
  const [source, setSource] = useState<Source>("android");
  const [snapshot, setSnapshot] = useState<Snapshot>(initial);
  const [prefs, setPrefs] = useState<Preferences>(() => {
    try {
      return loadPreferences(localStorage.getItem("yanda.preferences.v1"));
    } catch {
      return loadPreferences(null);
    }
  });
  const [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  const [approvalBusy, setApprovalBusy] = useState(false);
  async function answerAirplay(allow: boolean) {
    const pending = snapshot.airplayApproval;
    if (!pending || approvalBusy) return;
    setApprovalBusy(true);
    try {
      await call("approve_airplay", { requestId: pending.requestId, allow });
      setSnapshot((s) => ({ ...s, airplayApproval: null }));
    } catch (e) {
      report(e);
    } finally {
      setApprovalBusy(false);
    }
  }
  const [expanded, setExpanded] = useState(false);
  const presentationQueue = useRef(Promise.resolve());
  const [showSettings, setShowSettings] = useState(false),
    [showHelp, setShowHelp] = useState(false),
    [showLogs, setShowLogs] = useState(false),
    [top, setTop] = useState(false),
    [full, setFull] = useState(false);
  const [volumeStatus, setVolumeStatus] = useState(""),
    [copied, setCopied] = useState(false);
  const [hiddenMessage, setHiddenMessage] = useState("");
  const viewer = useRef<HTMLDivElement>(null);
  const active = [
    "connecting",
    "waiting",
    "streaming",
    "reconnecting",
  ].includes(snapshot.phase);
  const streaming = snapshot.phase === "streaming";
  const compact = streaming && prefs.autoCompact && !expanded;
  useEffect(() => {
    if (!streaming) setExpanded(false);
  }, [streaming]);
  useEffect(() => {
    if (!desktop) return;
    const size = snapshot.resolution?.match(/(\d+)\s*×\s*(\d+)/);
    if (streaming && !size) return;
    const request = {
      active: streaming,
      compact,
      width: Number(size?.[1] ?? 1),
      height: Number(size?.[2] ?? 1),
    };
    // Serialize transitions: a fast start/stop cannot restore an outdated size.
    presentationQueue.current = presentationQueue.current
      .catch(() => {})
      .then(async () => {
        const fullscreen = await call<boolean>("presentation_set", { request });
        setFull(fullscreen);
      })
      .catch((e: unknown) => setError(String(e)));
  }, [streaming, compact, snapshot.resolution, full]);
  const update = <K extends keyof Preferences>(key: K, value: Preferences[K]) =>
    setPrefs((p) => ({ ...p, [key]: value }));
  const report = (e: unknown) =>
    setError(e instanceof Error ? e.message : String(e));
  useEffect(() => {
    try {
      localStorage.setItem("yanda.preferences.v1", JSON.stringify(prefs));
    } catch {
      /* Storage may be disabled. */
    }
  }, [prefs]);
  useEffect(() => {
    if (!desktop) return;
    let gone = false,
      pending = false;
    const poll = async () => {
      if (pending) return;
      pending = true;
      try {
        const s = await api.status();
        if (!gone) setSnapshot(s);
      } catch (e) {
        if (!gone) setError(String(e));
      } finally {
        pending = false;
      }
    };
    void poll();
    const timer = setInterval(() => void poll(), 750);
    return () => {
      gone = true;
      clearInterval(timer);
    };
  }, []);
  useEffect(() => {
    if (!desktop || !viewer.current) return;
    const el = viewer.current;
    let queued = 0;
    const sync = () => {
      cancelAnimationFrame(queued);
      queued = requestAnimationFrame(() => {
        const r = el.getBoundingClientRect();
        void call("viewer_bounds", {
          bounds: {
            x: Math.round(r.x),
            y: Math.round(r.y),
            width: Math.round(r.width),
            height: Math.round(r.height),
            scale: devicePixelRatio,
            fill: prefs.fill,
            topLimit: Math.ceil(
              document.querySelector(".titlebar")?.getBoundingClientRect()
                .bottom ?? 0,
            ),
          },
        }).catch(report);
      });
    };
    const observer = new ResizeObserver(sync);
    observer.observe(el);
    window.addEventListener("resize", sync);
    window.addEventListener("scroll", sync, true);
    sync();
    return () => {
      observer.disconnect();
      window.removeEventListener("resize", sync);
      window.removeEventListener("scroll", sync, true);
      cancelAnimationFrame(queued);
    };
  }, [prefs.fill, full, showLogs]);
  useEffect(() => {
    if (!desktop) return;
    const timer = setTimeout(() => {
      void call<boolean>("set_volume", {
        volume: prefs.volume / 100,
        muted: prefs.muted || !prefs.audio,
      })
        .then(() => setVolumeStatus(""))
        .catch(() =>
          setVolumeStatus(
            "Не удалось изменить громкость. Проверьте устройство вывода Windows.",
          ),
        );
    }, 100);
    return () => clearTimeout(timer);
  }, [prefs.volume, prefs.muted, prefs.audio, active]);
  useEffect(() => {
    const key = (e: KeyboardEvent) => {
      if (e.key === "Escape" && full) void fullscreen(false);
    };
    document.addEventListener("keydown", key);
    return () => document.removeEventListener("keydown", key);
  }, [full]);
  useEffect(() => {
    const changed = () => setFull(!!document.fullscreenElement);
    document.addEventListener("fullscreenchange", changed);
    return () => document.removeEventListener("fullscreenchange", changed);
  }, []);

  async function connect() {
    setError("");
    setBusy(true);
    try {
      setSnapshot(await api.connect(source, prefs));
    } catch (e) {
      report(e);
    } finally {
      setBusy(false);
    }
  }
  async function stop() {
    setBusy(true);
    setError("");
    try {
      setSnapshot(await api.stop());
    } catch (e) {
      report(e);
    } finally {
      setBusy(false);
    }
  }
  async function fullscreen(value: boolean) {
    try {
      if (desktop) {
        await getCurrentWindow().setFullscreen(value);
        setFull(value);
      } else {
        if (value) await document.documentElement.requestFullscreen();
        else if (document.fullscreenElement) await document.exitFullscreen();
      }
    } catch (e) {
      report(e);
    }
  }
  async function toggleTop() {
    try {
      if (!desktop)
        throw new Error("Режим поверх окон доступен в десктопном приложении");
      await getCurrentWindow().setAlwaysOnTop(!top);
      setTop(!top);
    } catch (e) {
      report(e);
    }
  }
  async function copyDiagnostics() {
    const text = [
      "Y AND A 0.4.0-rc.1",
      desktop ? "Tauri Windows" : "Веб-просмотр",
      `Источник: ${sourceNames[source]}`,
      `Состояние: ${snapshot.phase}`,
      `Видео: ${snapshot.resolution ?? "нет"}`,
      `Звук: ${snapshot.audio}`,
      ...snapshot.logs,
    ].join("\n");
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      setError(
        "Не удалось скопировать диагностику. Выделите записи журнала вручную.",
      );
    }
  }
  const canConnect = !busy && !active;
  const displayError =
    error ||
    (snapshot.phase === "error" &&
    snapshot.source === source &&
    snapshot.message !== hiddenMessage
      ? snapshot.message
      : "");

  return (
    <div
      className={`app ${full ? "is-fullscreen" : ""} ${compact && !full ? "is-compact" : ""}`}
    >
      <header
        className="titlebar"

        onMouseDown={(e) => {
          if (
            desktop &&
            e.button === 0 &&
            !(e.target as HTMLElement).closest("button")
          )
            void getCurrentWindow().startDragging().catch(report);
        }}
      >
        <div className="brand">
          <span className="brand-symbol">
            Y<span>∧</span>
          </span>
          <span>
            Y AND A<span className="brand-dot">.</span>
          </span>
          <span className="brand-divider" />
          <span className="brand-caption">ЭКРАН И ЗВУК</span>
        </div>
        <div className="titlebar-right">
          <div className={`connection-status ${streaming ? "live" : ""}`}>
            <i />
            {streaming ? "В эфире" : "Локальное соединение"}
          </div>
          <FortyTwo visible={snapshot.windowVisible} />
          <div className="window-controls">
            <button
              aria-label="Свернуть"
              onClick={() =>
                desktop && void getCurrentWindow().minimize().catch(report)
              }
            >
              <Minus size={15} />
            </button>
            <button
              aria-label="Развернуть окно"
              onClick={() =>
                desktop &&
                void getCurrentWindow().toggleMaximize().catch(report)
              }
            >
              <Square size={12} />
            </button>
            <button
              className="close-window"
              aria-label="Закрыть приложение"
              onClick={() =>
                desktop && void getCurrentWindow().close().catch(report)
              }
            >
              <X size={17} />
            </button>
          </div>
        </div>
      </header>
      <div className="workspace">
        <nav className="rail" aria-label="Разделы">
          <div className="rail-top">
            <button
              className={!showSettings && !showHelp ? "selected" : ""}
              aria-label="Трансляция"
              title="Трансляция"
              onClick={() => {
                setShowSettings(false);
                setShowHelp(false);
              }}
            >
              <MonitorSmartphone size={22} />
            </button>
            <span className="rail-line" />
            <button
              className={showSettings ? "selected" : ""}
              aria-label="Настройки"
              title="Настройки"
              onClick={() => {
                setShowSettings(!showSettings);
                setShowHelp(false);
              }}
            >
              <Settings2 size={21} />
            </button>
          </div>
          <div className="rail-bottom">
            <button
              className={showHelp ? "selected" : ""}
              aria-label="Помощь"
              title="Помощь"
              onClick={() => {
                setShowHelp(!showHelp);
                setShowSettings(false);
              }}
            >
              <CircleHelp size={21} />
            </button>
            <span className="rail-version">0.4 RC</span>
          </div>
        </nav>
        <main>
          <section className="page-heading">
            <div>
              <div className="eyebrow">
                <span /> ВАШ ТЕЛЕФОН. ВАШ КОМПЬЮТЕР.
              </div>
              <h1>Трансляция экрана</h1>
              <p>Больше пространства для того, что у вас на экране.</p>
            </div>
            <div className="privacy-note">
              <ShieldCheck size={19} />
              <div>
                Только между вами
                <span>Без облака и записи на диск</span>
              </div>
            </div>
          </section>
          {!desktop && (
            <div className="preview-banner">
              <Info size={15} />
              <span>
                Веб-просмотр интерфейса. Для настоящей трансляции запустите
                десктопное приложение.
              </span>
            </div>
          )}
          <div className="studio">
            <section className="viewer-card" aria-label="Область трансляции">
              <div className="viewer-heading">
                <div className="viewer-title">
                  <Monitor size={16} />
                  <span>Экран устройства</span>
                  <span className={`status-pill ${streaming ? "live" : ""}`}>
                    <i />
                    {phaseLabels[snapshot.phase]}
                  </span>
                </div>
                <div className="viewer-heading-right">
                  <span>{snapshot.resolution ?? "Авто"}</span>
                  <span className="tiny-divider" />
                  <span>
                    {streaming ? duration(snapshot.elapsed) : "— : —"}
                  </span>
                </div>
              </div>
              <div className="viewer" ref={viewer} data-testid="viewer">
                {!streaming && (
                  <div className="empty-state">
                    <div className="screen-art" aria-hidden="true">
                      <div className="art-orbit orbit-one" />
                      <div className="art-orbit orbit-two" />
                      <div className="art-monitor">
                        <span />
                        <div className="art-monitor-line" />
                        <MonitorSmartphone size={44} strokeWidth={1} />
                      </div>
                      <div className="art-phone">
                        <div className="phone-speaker" />
                        <div className="phone-symbol">
                          <span />
                          <span />
                          <span />
                        </div>
                        <div className="phone-home" />
                      </div>
                      <div className="art-connection">
                        <span />
                        <span />
                        <span />
                      </div>
                    </div>
                    <div className="empty-caption">
                      <span className="empty-overline">
                        {active
                          ? "СОЕДИНЕНИЕ С УСТРОЙСТВОМ"
                          : "ГОТОВЫ, КОГДА ГОТОВЫ ВЫ"}
                      </span>
                      <h2>
                        {busy || snapshot.phase === "connecting"
                          ? "Устанавливаем связь…"
                          : snapshot.phase === "waiting"
                            ? source === "airplay"
                              ? "Ждём ваш iPhone"
                              : "Ждём ваш Android"
                            : snapshot.phase === "error"
                              ? "Вернёмся на связь"
                              : "Ваш экран — здесь"}
                      </h2>
                      <p>
                        {active
                          ? snapshot.message
                          : "Подключите телефон, чтобы видеть и слышать больше.\nИзображение появится прямо в этом окне."}
                      </p>
                      {active ? (
                        <div className="waiting-line">
                          <LoaderCircle size={14} className="spin" />
                          {snapshot.phase === "waiting"
                            ? source === "airplay"
                              ? "Выберите Y AND A в «Повторе экрана»"
                              : "Сканируйте QR в приложении на телефоне"
                            : "Запускаем видео и проверяем звук"}
                        </div>
                      ) : (
                        <div className="empty-compat">
                          <span>
                            <Wifi size={13} />
                            Android · без отладки
                          </span>
                          <i />
                          <span>
                            <Radio size={13} />
                            iPhone AirPlay
                          </span>
                        </div>
                      )}
                    </div>
                  </div>
                )}
              </div>
              <div className="viewer-controls">
                <div className="audio-controls">
                  <button
                    aria-label={
                      prefs.muted ? "Включить звук" : "Выключить звук"
                    }
                    title={prefs.muted ? "Включить звук" : "Выключить звук"}
                    className={prefs.muted ? "is-muted" : ""}
                    onClick={() => update("muted", !prefs.muted)}
                  >
                    {prefs.muted || prefs.volume === 0 ? (
                      <VolumeX size={19} />
                    ) : (
                      <Volume2 size={19} />
                    )}
                  </button>
                  <input
                    type="range"
                    aria-label="Громкость"
                    min="0"
                    max="100"
                    value={prefs.volume}
                    style={
                      { "--range": `${prefs.volume}%` } as React.CSSProperties
                    }
                    onChange={(e) => update("volume", +e.target.value)}
                  />
                  <span className="volume-value">
                    {prefs.muted ? "0" : prefs.volume}%
                  </span>
                  <span className="control-divider" />
                  <span
                    className="output-label"
                    title="Используется выбранное в Windows устройство. Для смены вывода откройте микшер Windows."
                  >
                    <Headphones size={14} />
                    Вывод Windows
                  </span>
                </div>
                <div className="view-actions">
                  <div className="fit-control" aria-label="Масштаб">
                    <button
                      className={!prefs.fill ? "active" : ""}
                      onClick={() => update("fill", false)}
                      title="Весь экран без обрезания"
                    >
                      Fit
                    </button>
                    <button
                      className={prefs.fill ? "active" : ""}
                      onClick={() => update("fill", true)}
                      title="Заполнить область с обрезанием краёв"
                    >
                      Fill
                    </button>
                  </div>
                  <span className="control-divider" />
                  <button
                    className={top ? "active-icon" : ""}
                    aria-label="Поверх окон"
                    aria-pressed={top}
                    title="Поверх других окон"
                    onClick={() => void toggleTop()}
                  >
                    <Pin size={17} />
                  </button>
                  <button
                    aria-label={
                      full ? "Выйти из полного экрана" : "Полный экран"
                    }
                    title="Полный экран"
                    onClick={() => void fullscreen(!full)}
                  >
                    {full ? <Minimize size={18} /> : <Expand size={18} />}
                  </button>
                </div>
              </div>
              {streaming && (
                <div className="session-bar">
                  <button
                    onClick={() => {
                      if (!prefs.autoCompact) update("autoCompact", true);
                      setExpanded(compact);
                    }}
                    title={
                      compact
                        ? "Развернуть интерфейс"
                        : "Окно по размеру телефона"
                    }
                  >
                    <MonitorSmartphone size={15} />
                    <span>{compact ? "Развернуть" : "Компактно"}</span>
                  </button>
                  <button
                    className="session-stop"
                    disabled={busy}
                    onClick={() => void stop()}
                  >
                    <Unplug size={15} />
                    {busy ? "Останавливаем…" : "Остановить"}
                  </button>
                </div>
              )}
              <div className="viewer-footnote">
                <span>
                  <i
                    className={snapshot.audio === "active" ? "audio-on" : ""}
                  />
                  {streaming || active
                    ? snapshot.audioMessage
                    : "Видео и системный звук · без записи на диск"}
                </span>
                <span>
                  {prefs.fill
                    ? "Fill · края изображения могут обрезаться"
                    : "Fit · пропорции сохранены"}
                </span>
              </div>
            </section>
            <aside className="connection-panel">
              <div className="panel-heading">
                <div className="eyebrow muted">ПОДКЛЮЧЕНИЕ</div>
                <h2>Выберите источник</h2>
              </div>
              <div
                className="source-tabs"
                role="tablist"
                aria-label="Источник трансляции"
              >
                {sources.map((s) => (
                  <button
                    key={s.id}
                    role="tab"
                    aria-selected={source === s.id}
                    className={source === s.id ? "active" : ""}
                    disabled={active || busy}
                    onClick={() => {
                      setSource(s.id);
                      setError("");
                    }}
                  >
                    <s.icon size={20} />
                    <strong>{s.title}</strong>
                    <span>{s.subtitle}</span>
                  </button>
                ))}
              </div>
              <div className="source-body">
                <div className="section-label">
                  {source === "airplay" ? "ПРИЁМНИК" : "ANDROID-ПРИЛОЖЕНИЕ"}
                </div>
                {source === "android" && (
                  <AndroidConnection
                    onStop={() => void stop()}
                    busy={busy}
                    phase={
                      snapshot.source === "android" ? snapshot.phase : "idle"
                    }
                  />
                )}
                {source === "airplay" && (
                  <div className="receiver-card">
                    <div className="receiver-logo">
                      <Radio size={22} />
                    </div>
                    <div>
                      <strong>Y AND A</strong>
                      <span>
                        {active
                          ? "Приёмник включён"
                          : "Локальная сеть · AirPlay"}
                      </span>
                    </div>
                    <span className="receiver-dot" />
                  </div>
                )}
                <div className="instructions" hidden={source === "android"}>
                  <h3>
                    {source === "airplay"
                      ? "На одном Wi-Fi — на большом экране"
                      : "Первое подключение — это просто"}
                  </h3>
                  <ol>
                    {guides[source].map((step, i) => (
                      <li key={step}>
                        <span>{String(i + 1).padStart(2, "0")}</span>
                        <p>{step}</p>
                      </li>
                    ))}
                  </ol>
                </div>
                <div className="source-limit">
                  <Info size={14} />
                  <p>
                    {source === "airplay"
                      ? "Новый iPhone требует подтверждения на ПК. Используйте доверенную локальную сеть. DRM-контент может не передаваться."
                      : "Разрешение Android на экран требуется для каждого сеанса. Защищённые приложения могут запрещать передачу изображения и звука."}
                  </p>
                </div>
              </div>
              <div className="connect-action">
                {active ? (
                  <button
                    className="stop-button"
                    disabled={busy}
                    onClick={() => void stop()}
                  >
                    <Unplug size={17} />
                    {busy ? "Останавливаем…" : "Остановить трансляцию"}
                  </button>
                ) : (
                  <button
                    className="primary-button"
                    disabled={!canConnect}
                    onClick={() => void connect()}
                  >
                    {busy ? (
                      <LoaderCircle className="spin" size={17} />
                    ) : source === "airplay" ? (
                      <Radio size={17} />
                    ) : (
                      <MonitorSmartphone size={17} />
                    )}
                    <span>
                      {busy
                        ? "Подключаем…"
                        : source === "airplay"
                          ? "Включить AirPlay"
                          : snapshot.phase === "error"
                            ? "Создать новый QR-код"
                            : "Показать QR-код"}
                    </span>
                    <ArrowRight size={17} />
                  </button>
                )}
                <p>
                  <ShieldCheck size={12} />
                  Прямое соединение. Только ваша сеть.
                </p>
              </div>
            </aside>
          </div>
          {displayError && (
            <div role="alert" className="error-banner">
              <Info size={17} />
              <span>{displayError}</span>
              <button
                aria-label="Скрыть сообщение"
                onClick={() => {
                  setError("");
                  setHiddenMessage(snapshot.message);
                }}
              >
                <X size={16} />
              </button>
            </div>
          )}
          {volumeStatus && active && (
            <div className="audio-note">{volumeStatus}</div>
          )}
          {showSettings && (
            <section className="drawer settings-drawer">
              <div className="drawer-heading">
                <div>
                  <span className="eyebrow muted">ПАРАМЕТРЫ СЕАНСА</span>
                  <h2>Ваш баланс качества</h2>
                </div>
                <button
                  aria-label="Закрыть настройки"
                  onClick={() => setShowSettings(false)}
                >
                  <X size={19} />
                </button>
              </div>
              <label className="compact-preference">
                <input
                  type="checkbox"
                  checked={prefs.autoCompact}
                  onChange={(e) => update("autoCompact", e.target.checked)}
                />
                <span>Сжимать окно под экран телефона при трансляции</span>
              </label>
              <div className="settings-grid">
                <label>
                  Разрешение
                  <select
                    value={prefs.quality}
                    disabled={active}
                    onChange={(e) => update("quality", e.target.value)}
                  >
                    <option value="auto">Авто · до 1920 px</option>
                    <option value="1080">До 1080 px</option>
                    <option value="1600">До 1600 px</option>
                    <option value="original">До 2560 px</option>
                  </select>
                </label>
                <label>
                  Частота кадров
                  <select
                    value={prefs.fps}
                    disabled={active || source === "airplay"}
                    onChange={(e) => update("fps", +e.target.value)}
                  >
                    <option value={0}>Авто</option>
                    <option value={30}>До 30 FPS</option>
                    <option value={60}>До 60 FPS</option>
                  </select>
                </label>

                <label className="toggle-label">
                  <span>
                    Передавать системный звук
                    <small>Один аудиопоток на компьютере</small>
                  </span>
                  <input
                    type="checkbox"
                    checked={prefs.audio}
                    disabled={active}
                    onChange={(e) => update("audio", e.target.checked)}
                  />
                </label>
              </div>
              <p className="settings-caption">
                Изменения качества применяются при следующем подключении. iPhone
                выбирает фактическое разрешение сам; приёмник объявляет квадрат
                1920 или 2560 px. Вывод звука выбирается в микшере Windows.
              </p>
            </section>
          )}
          {showHelp && (
            <section className="drawer help-drawer">
              <div className="drawer-heading">
                <div>
                  <span className="eyebrow muted">ПОМОЩЬ</span>
                  <h2>Остаёмся на связи</h2>
                </div>
                <button
                  aria-label="Закрыть помощь"
                  onClick={() => setShowHelp(false)}
                >
                  <X size={19} />
                </button>
              </div>
              <div className="help-columns">
                <div>
                  <h3>Android не обнаружен</h3>
                  <p>
                    Установите APK Y AND A на телефон, подключите оба устройства
                    к одной локальной сети и создайте новый QR-код. Отладка и
                    USB-драйверы не нужны.
                  </p>
                </div>
                <div>
                  <h3>Нет звука</h3>
                  <p>
                    Разрешите запись аудио в Android-приложении и включите
                    передачу звука. Некоторые приложения запрещают его захват.
                    Микрофон не используется; защищённый контент не обходится.
                  </p>
                </div>
                <div>
                  <h3>iPhone не видит Y AND A</h3>
                  <p>
                    Одна LAN, без гостевой изоляции и VPN. Разрешите приёмнику
                    локальную сеть в Windows вручную. Приложение не меняет
                    Firewall. Автоматический USB AirPlay не гарантируется.
                  </p>
                </div>
              </div>
            </section>
          )}
          <footer className="page-footer">
            <div>
              <span className="footer-dot" />
              {active ? sourceNames[source] : "Всё начинается с подключения"}
              <span className="footer-separator">/</span>
              <span>{desktop ? "Windows · локально" : "Веб-просмотр"}</span>
            </div>
            <button
              onClick={() => setShowLogs(!showLogs)}
              className={showLogs ? "expanded" : ""}
            >
              <AudioLines size={14} />
              Диагностика
              <ChevronDown size={13} />
            </button>
          </footer>
          {showLogs && (
            <section className="diagnostics">
              <div>
                <h3>Журнал соединения</h3>
                <button onClick={() => void copyDiagnostics()}>
                  {copied ? <Check size={14} /> : <Copy size={14} />}{" "}
                  {copied ? "Скопировано" : "Копировать"}
                </button>
              </div>
              <p>
                Android {snapshot.companionReady ? "готов" : "не проверен"} ·
                AirPlay{" "}
                {snapshot.airplayReady ? "готов" : "не собран / не проверен"} ·
                Встроенное видео {snapshot.embedded ? "подключено" : "ожидание"}
              </p>
              <pre>
                {snapshot.logs.length
                  ? snapshot.logs.join("\n")
                  : "Сеансов ещё не было. Персональные данные и коды сопряжения в журнал не записываются."}
              </pre>
            </section>
          )}
        </main>
      </div>
      {snapshot.airplayApproval && (
        <div className="pairing-overlay">
          <section
            className="pairing-dialog approval-dialog"
            role="dialog"
            aria-modal="true"
            aria-labelledby="airplay-approval-title"
          >
            <span className="eyebrow">НОВОЕ ПОДКЛЮЧЕНИЕ</span>
            <h2 id="airplay-approval-title">Разрешить этому iPhone?</h2>
            <p>
              Сверьте адрес ниже с iPhone: Настройки → Wi-Fi → ⓘ рядом с вашей
              сетью → IP-адрес. Разрешайте только своё устройство. Запрос
              действует 20 секунд.
            </p>
            <dl>
              <dt>Адрес телефона</dt>
              <dd>{snapshot.airplayApproval.address}</dd>
              <dt>Проверенный ключ устройства</dt>
              <dd className="device-key">
                {snapshot.airplayApproval.fingerprint}
              </dd>
            </dl>
            <p>
              Разрешение действует до выключения приёмника. Новый ключ телефона
              потребует нового подтверждения.
            </p>
            <div className="approval-actions">
              <button
                autoFocus
                disabled={approvalBusy}
                onClick={() => void answerAirplay(false)}
              >
                Отклонить
              </button>
              <button
                className="primary"
                disabled={approvalBusy}
                onClick={() => void answerAirplay(true)}
              >
                Разрешить iPhone
              </button>
            </div>
          </section>
        </div>
      )}
    </div>
  );
}
createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
