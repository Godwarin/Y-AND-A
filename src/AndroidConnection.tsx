import { useEffect, useState } from "react";
import QRCode from "qrcode";
import { Download, LoaderCircle, ShieldCheck, X, QrCode } from "lucide-react";
import { call } from "./api";
import type { Snapshot } from "./model";
type Offer = {
  destinations: { address: string; payload: string }[];
  expiresIn: number;
};
export function AndroidConnection({
  phase,
  onStop,
  busy,
}: {
  phase: Snapshot["phase"];
  onStop: () => void;
  busy: boolean;
}) {
  const [offer, setOffer] = useState<Offer | null>(null),
    [address, setAddress] = useState(""),
    [qr, setQr] = useState("");
  const [expanded, setExpanded] = useState(false);
  const [seconds, setSeconds] = useState(0),
    [error, setError] = useState("");
  useEffect(() => {
    if (phase !== "waiting") {
      setExpanded(false);
      setOffer(null);
      setQr("");
      return;
    }
    let gone = false;
    void call<Offer>("companion_offer")
      .then((o) => {
        if (!gone) {
          setOffer(o);
          setAddress(o.destinations[0]?.address ?? "");
          setSeconds(o.expiresIn);
        }
      })
      .catch((e) => {
        if (!gone) setError(String(e));
      });
    return () => {
      gone = true;
    };
  }, [phase]);
  useEffect(() => {
    if (!offer) return;
    const t = setInterval(() => setSeconds((s) => Math.max(0, s - 1)), 1000);
    return () => clearInterval(t);
  }, [offer]);
  useEffect(() => {
    const destination = offer?.destinations.find((d) => d.address === address);
    if (!destination) return;
    let gone = false;
    void QRCode.toDataURL(destination.payload, {
      width: 320,
      margin: 4,
      errorCorrectionLevel: "M",
      color: { dark: "#080808", light: "#ffffff" },
    })
      .then((url) => {
        if (!gone) {
          setQr(url);
          setExpanded(true);
        }
      })
      .catch(() => {
        if (!gone) setError("Не удалось показать QR. Создайте новый код.");
      });
    return () => {
      gone = true;
    };
  }, [offer, address]);
  useEffect(() => {
    if (!expanded) return;
    const key = (e: KeyboardEvent) => {
      if (e.key === "Escape") setExpanded(false);
    };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, [expanded]);
  const network =
    offer && offer.destinations.length > 1 ? (
      <label className="pairing-network">
        Сеть компьютера
        <select
          aria-label="Сеть компьютера"
          value={address}
          onChange={(e) => setAddress(e.target.value)}
        >
          {offer.destinations.map((d) => (
            <option key={d.address}>{d.address}</option>
          ))}
        </select>
      </label>
    ) : null;

  return (
    <div className="android-connection">
      <div className="android-badge">
        <ShieldCheck size={15} />
        Без кабеля и отладки
      </div>
      <h3>Телефон — на большом экране</h3>
      <p>
        Установите Y AND A на Android 10+. Телефон и ПК должны быть в одной
        локальной сети.
      </p>
      <button
        className="secondary-button"
        onClick={() => {
          void call("open_android_apk").catch((e) => setError(String(e)));
        }}
      >
        <Download size={15} />
        Открыть папку с APK
      </button>
      {phase === "connecting" || phase === "reconnecting" ? (
        <p className="android-preparing">
          <LoaderCircle size={15} className="spin" />
          Готовим защищённое подключение…
        </p>
      ) : null}
      {phase === "waiting" && qr && (
        <>
          <button
            className="secondary-button"
            onClick={() => setExpanded(true)}
          >
            <QrCode size={16} />
            Открыть QR-код
          </button>
          <p>
            Код действует {seconds} с. Сканируйте его в приложении Y AND A на
            Android.
          </p>
          {expanded && (
            <div
              className="pairing-overlay"
              role="dialog"
              aria-modal="true"
              aria-labelledby="pairing-title"
            >
              <div className="pairing-dialog">
                <div className="pairing-dialog-heading">
                  <div>
                    <span className="eyebrow muted">ANDROID · БЕЗ ОТЛАДКИ</span>
                    <h2 id="pairing-title">Подключите телефон</h2>
                  </div>
                  <button
                    aria-label="Закрыть крупный QR"
                    onClick={() => setExpanded(false)}
                  >
                    <X size={20} />
                  </button>
                </div>
                {network}
                <div className="qr-card">
                  <img
                    src={qr}
                    alt="QR для Android-приложения Y AND A"
                    width={320}
                    height={320}
                  />
                  <div>Одноразовый QR · {seconds} с</div>
                </div>
                <p>
                  В Android-приложении: «Сканировать QR-код» → «Начать
                  трансляцию» → разрешить показ экрана.
                </p>
                <button
                  className="secondary-button"
                  disabled={busy}
                  onClick={onStop}
                >
                  Отменить подключение
                </button>
              </div>
            </div>
          )}
        </>
      )}
      {phase === "streaming" && (
        <p className="inline-note">
          Телефон подключён. Остановить трансляцию можно здесь или на Android.
        </p>
      )}
      {error && (
        <p className="inline-note" role="alert">
          {error}
        </p>
      )}
      <p className="wifi-detail">
        Зашифрованное соединение с вашим ПК. Камера нужна только для QR. Android
        отдельно запрашивает разрешение на экран и звук; микрофон не
        захватывается.
      </p>
    </div>
  );
}
