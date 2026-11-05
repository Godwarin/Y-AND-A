import { invoke, isTauri } from "@tauri-apps/api/core";
import type { Snapshot, Source, Preferences } from "./model";
export const desktop = isTauri();
const missing =
  "Откройте десктопную версию Y AND A: npm run desktop. Веб-просмотр показывает интерфейс без доступа к устройствам.";
export async function call<T>(
  command: string,
  args?: Record<string, unknown>,
): Promise<T> {
  if (!desktop) throw new Error(missing);
  return invoke<T>(command, args);
}
export const api = {
  status: () => call<Snapshot>("status"),
  connect: (source: Source, p: Preferences) =>
    call<Snapshot>("connect", {
      request: {
        source,
        quality: p.quality,
        fps: p.fps,
        audio: p.audio,
      },
    }),
  stop: () => call<Snapshot>("disconnect"),
};
