# Архитектура Y AND A

React/TypeScript/Tauri2/Rust управляет native C++ FFmpeg/SDL HWND в viewer. Engine находится в Job-группе; падение engine не завершает UI. Original42: неизменённая геометрия,14FPS,visibility pause/reduced-motion. Presentation state отделён от media mutex; compact начинается после decoded video и восстанавливает прежнюю геометрию после stop.

Android10+: MediaProjection + AudioPlaybackCapture → H264/PCM → TLS1.3 pinned QR certificate + one-use256bit token/TTL180s → native receiver. ADB отсутствует. Destination фиксируется до consent; pending8/per-IP1/deadline4s,packet10s/write3s. DRM/capture policies не обходятся, media/QR/private keys не выводятся в files/diagnostics.

AirPlay: Ed25519 proof/key+peer → explicit PC approval/private stdin ID20s → fail-closed routes. TCP16,accept32/s,request40/s; bounded lengths/deadlines,max_pixels16M/thread2,media peer check. Trust RAM-only до stop. Trusted LAN: первое mDNS имя не удостоверяет приёмник, PIN/SRP не реализован.

APK имеет стабильный publisher cert. Keys защищены owner-only ACL/CurrentUser DPAPI, encrypted backup подтверждён владельцем. ECDSA-P256 manifest связывает hashes/размеры3загрузок и требует доверенного fingerprint. Windows Authenticode отсутствует.

Свежие scoped regression13+13PASS относятся к frozen receivers в offline LPAC guest. Trusted parent проверяет TCP PID/Job/executable и создаёт target-read-only proof; это не IPC продукта и не повышение его прав. Scope — [итог безопасности](SECURITY_VALIDATION_BETA_0.42.md).

Label BETA-0.42 отделён от code version0.4.0-rc.1 через config/release.json и release-layout.ps1. Релиз — release/BETA-0.42, история — archive/releases.100tested application files при обновлении docs не пересобираются. Source export publish/github исключает private dirs/keys/backups/SDK/runtime. Source ZIP добавляет pinned dependency sources, необходимые для GPL/сборки.

GitHub хранит код и Release assets, в трансляцию не включён. Local package scripts не меняют remote commits/visibility. Новые templates/instructions описывают будущий Code/Release workflow; final metadata receipts сохраняются вне snapshot. Product code в текущем этапе не менялся.