export type Source = "android" | "airplay";
export interface Snapshot {
  phase:
    "idle" | "connecting" | "waiting" | "streaming" | "error" | "reconnecting";
  source: Source;
  message: string;
  audio: "waiting" | "active" | "unavailable" | "disabled";
  audioMessage: string;
  resolution: string | null;
  elapsed: number;
  logs: string[];
  companionReady: boolean;
  apkReady: boolean;
  airplayReady: boolean;
  embedded: boolean;
  windowVisible: boolean;
  airplayApproval?: {
    requestId: string;
    fingerprint: string;
    address: string;
  } | null;
}
export interface Preferences {
  quality: string;
  fps: number;
  audio: boolean;
  volume: number;
  muted: boolean;
  fill: boolean;
  autoCompact: boolean;
}
export const defaults: Preferences = {
  quality: "auto",
  fps: 0,
  audio: true,
  volume: 80,
  muted: false,
  fill: false,
  autoCompact: true,
};
export const initial: Snapshot = {
  phase: "idle",
  source: "android",
  message: "Готово к подключению",
  audio: "waiting",
  audioMessage: "Звук появится вместе с трансляцией",
  resolution: null,
  elapsed: 0,
  logs: [],
  companionReady: false,
  apkReady: false,
  airplayReady: false,
  embedded: false,
  windowVisible: true,
};
export const phaseLabels: Record<Snapshot["phase"], string> = {
  idle: "Ожидание подключения",
  connecting: "Подключение",
  waiting: "Приёмник запущен",
  streaming: "Трансляция",
  error: "Нужна проверка",
  reconnecting: "Переподключение",
};
export const sourceNames: Record<Source, string> = {
  android: "Android · Приложение",
  airplay: "iPhone · AirPlay",
};
export function loadPreferences(raw: string | null): Preferences {
  try {
    const p = JSON.parse(raw ?? "{}") as Partial<Preferences>;
    return {
      quality: ["auto", "1080", "1600", "original"].includes(p.quality ?? "")
        ? p.quality!
        : defaults.quality,
      fps: [0, 30, 60].includes(p.fps ?? -1) ? p.fps! : 0,
      audio: typeof p.audio === "boolean" ? p.audio : true,
      volume:
        typeof p.volume === "number" && Number.isFinite(p.volume)
          ? Math.min(100, Math.max(0, p.volume))
          : 80,
      muted: p.muted === true,
      fill: p.fill === true,
      autoCompact: p.autoCompact !== false,
    };
  } catch {
    return { ...defaults };
  }
}
export function duration(seconds: number): string {
  return [
    Math.floor(seconds / 3600),
    Math.floor(seconds / 60) % 60,
    seconds % 60,
  ]
    .map((n) => String(n).padStart(2, "0"))
    .join(":");
}
