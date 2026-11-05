import { describe, expect, it } from "vitest";
import { defaults, duration, loadPreferences } from "./model";
describe("сохранённые настройки", () => {
  it("восстанавливается после повреждённого JSON", () =>
    expect(loadPreferences("{")).toEqual(defaults));
  it("не принимает произвольные аргументы и типы", () => {
    const p = loadPreferences(
      '{"quality":"--bad","fps":999,"volume":500,"audio":"false","fill":true}',
    );
    expect(p.quality).toBe("auto");
    expect(p.fps).toBe(0);
    expect(p.volume).toBe(100);
    expect(p.audio).toBe(true);
    expect(p.fill).toBe(true);
  });
});
it("счётчик длительных сеансов", () => expect(duration(3661)).toBe("01:01:01"));
