import QRCode from "qrcode";
import path from "node:path";
const root = path.resolve(import.meta.dirname, "..");
// Public synthetic credentials. No runtime/session offer is written to disk.
const uri =
  "yanda://connect?v=3&host=192.168.1.20&alt=10.0.0.2,172.16.0.2,192.168.2.2,192.168.3.2,10.1.1.2,10.2.1.2,169.254.1.2&port=12345&fp=" +
  "a".repeat(64) +
  "&token=" +
  "b".repeat(64);
await QRCode.toFile(path.join(root, "build/android-qr-fixture.png"), uri, {
  width: 320,
  margin: 4,
  errorCorrectionLevel: "M",
});
