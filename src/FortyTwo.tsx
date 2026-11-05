import { useEffect, useRef, useState } from "react";
declare global {
  interface Window {
    FortyTwo: {
      mount: (
        el: HTMLElement,
        options: Record<string, unknown>,
      ) => { pause(): void; resume(): void; destroy(): void };
    };
  }
}
export function FortyTwo({ visible = true }: { visible?: boolean }) {
  const ref = useRef<HTMLDivElement>(null);
  const [reduced, setReduced] = useState(
    () => matchMedia("(prefers-reduced-motion: reduce)").matches,
  );
  useEffect(() => {
    const media = matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => setReduced(media.matches);
    media.addEventListener("change", update);
    return () => media.removeEventListener("change", update);
  }, []);
  useEffect(() => {
    if (reduced || !ref.current) return;
    const animation = window.FortyTwo.mount(ref.current, {
      color: "#E1192D",
      fps: 14,
      fontSize: 3.8,
    });
    const visibility = () =>
      document.hidden || !visible ? animation.pause() : animation.resume();
    document.addEventListener("visibilitychange", visibility);
    visibility();
    return () => {
      document.removeEventListener("visibilitychange", visibility);
      animation.destroy();
    };
  }, [reduced, visible]);
  return (
    <div className="signature" title="Оригинальная 3D ASCII-анимация 42">
      <div className="forty-two" ref={ref}>
        {reduced && (
          <img src="/animation/42-preview.png" alt="ASCII-цифры 42" />
        )}
      </div>
      <span>СВЯЗЬ В ДВИЖЕНИИ</span>
    </div>
  );
}
