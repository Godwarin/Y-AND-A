# Android companion 0.3.0

Это новый основной Android-путь по требованию владельца: установка собственного APK, обычные системные разрешения, локальная трансляция. USB/Wireless debugging, ADB, root, Shizuku, accessibility/device-admin и OEM-драйверы не используются. Android APK пока **UNVERIFIED_ON_DEVICE**: есть сборка/подпись/программные проверки, нет физического запуска телефона или эмулятора.

## Пользовательский сценарий

1. Установить `release/Y-AND-A-0.3.0-android.apk` обычным Android installer на Android 10+. При запросе Android разрешить установку из выбранного файлового менеджера.
2. ПК и телефон подключить к одной LAN. ПК может использовать Ethernet; guest isolation/VPN/Firewall могут блокировать соединение. Firewall приложение не настраивает — доступ к нужной частной сети владелец разрешает вручную.
3. Windows → Android → «Показать QR-код». Крупный диалог не перекрывает header/42. QR одноразовый, действует 180 секунд.
4. APK → «Сканировать QR-код» → «Начать трансляцию». Разрешить системный запрос MediaProjection. Отладка не нужна, но этот запрос обязателен каждый сеанс.
5. Для звука выдать RECORD_AUDIO. Это захват воспроизведения разрешённых приложений, не микрофон. Если разрешение не выдано, видео должно продолжить работу. Системная политика/исходное приложение могут возвращать тишину или защищённый чёрный экран; обхода нет.
6. Остановить с ПК, в APK, из уведомления Stop или системного индикатора. При новом сеансе создать новый QR и новое screen consent.

## Компоненты и ограничения Android

- `MainActivity`: сканирование внутри приложения, ручной ввод и системное согласие. Данные QR остаются в памяти. Внешние Intent не выбирают получателя. Новый сеанс требует нового согласия на захват.
- `ScanActivity`: offline ZXing core 3.5.4 через Android Camera preview; камера закрывается при onPause. Нет Google Play Services, сетевой загрузки моделей и отправки кадров.
- `StreamService`: non-exported foreground service type mediaProjection, START_NOT_STICKY. startForeground выполняется после consent и до getMediaProjection; callback регистрируется до единственного VirtualDisplay.
- `MediaCodec`: surface H264, 30 FPS по умолчанию/60 по настройке, 1920 px по длинной стороне по умолчанию, максимум 2560; размеры кратны 16. Codec-specific SPS/PPS передаются отдельно от кадров.
- Начальные размеры capture берутся через WindowMetrics в Activity и передаются foreground Service; Service не полагается на UI-context WindowManager.
- Resize на Android 14+ использует onCapturedContentResize; encoder/surface заменяются, существующий VirtualDisplay делает resize/setSurface. На Android 10–13 используется DisplayListener.
- `AudioRecord` + AudioPlaybackCaptureConfiguration: 48000 Hz, stereo, PCM16 little endian; USAGE_MEDIA/GAME/UNKNOWN, собственный UID исключён. Никакой AudioSource.MIC. Audio opt-out, другой user/work profile, DRM и FLAG_SECURE не обходятся.
- Закрытие socket прерывает заблокированную запись. Heartbeat/monitor ограничивают потерю сети. onStop/stopService освобождают encoder, surfaces, AudioRecord, VirtualDisplay и projection. OEM lifecycle/codec quirks физически ещё не проверены.
- Target SDK36. Официальная local-network документация указывает обязательный ACCESS_LOCAL_NETWORK для приложений, обновлённых до target37; для target36 остаётся совместимый режим. Location и Wi-Fi scanning permissions не запрашиваются.

## TLS и QR

Windows receiver создаёт ephemeral RSA certificate/key в RAM и открывает один случайный TCP port. По stdout в приватный Rust pipe передаёт только readiness metadata; эта строка не попадает в diagnostics. Token CSPRNG 32 bytes создаёт Rust и подаёт через stdin, не argv.

QR URI:

```text
yanda://connect?v=3&host=PRIVATE_IPV4&alt=OTHER_PRIVATE_IPS&port=PORT&fp=SHA256_CERT_DER&token=64_HEX_TOKEN
```

Android принимает только private/link-local IPv4, до восьми адресов, port 1–65535, version3, fingerprint/token по 64 lowercase hex. Duplicate keys, публичные адреса и посторонние схемы отклоняются. При недоступности primary пробует private alternatives; сертификат проверяется до отправки токена. Pin сравнивается constant-time. Никаких доверяющих всем сертификатам production fallback нет. Самоподписанный сертификат допустим только по точному fingerprint из QR.

OpenSSL receiver требует TLS1.3. После правильного токена соединение одноразовое, QR offer уничтожается в Rust, listener после disconnect закрывается. При cancel/timeout/exit child завершает Job object. Token, QR URI, private keys и media не пишутся в файлы/журналы/localStorage. Приватный `.local/android-signing/` относится к подписи APK, не к transport; не включать в архивы.

## Wire format v3

Все network integers big endian. После TLS:

| Направление | Данные |
|---|---|
| Android → PC auth | 8 bytes `YANDA03\n`, затем 64 ASCII hex token |
| PC → Android ack | 8 bytes `YANDAOK\n`, uint8 audioEnabled, uint32 maxSize, uint32 fps |
| Media header | uint8 type, uint32 payloadLength, uint64 monotonic PTS microseconds |

| Type | Payload |
|---|---|
| 1 | H264 Annex-B access unit или SPS/PPS codec configuration, ≤8 MiB |
| 2 | PCM16 LE stereo 48000, длина кратна 4, ≤192000 bytes |
| 3 | End, длина 0 |
| 4 | Audio unavailable/not sent, длина 0 |
| 5 | Heartbeat, длина 0; PC отвечает одним byte 1 |

FFmpeg decoder ограничен max_pixels 16M, размером 4096 по каждой стороне. Последний RGBA frame держится в одном буфере и отображается SDL texture; очередь видеокадров не растёт. SDL queued audio сбрасывается при накоплении >~250 ms. PTS передаются, но строгий A/V scheduling пока не реализован: физические latency/sync и sustained mobile throughput не заявляются измеренными.

`YANDA_VIDEO WxH` выдаётся только после декодирования и создания texture, поэтому UI не считает handshake/QR успешным видеопотоком. Native HWND встраивается тем же bridge, что AirPlay. Аудиовывод/volume/mute относятся к receiver PID. Audio marker доказывает открытый output, не слышимость конкретного приложения телефона.

## Сборка, подпись и тесты

Скрипты: bootstrap-android.ps1 (SDK terms acceptance), build-android.ps1 (JDK21/aapt2/javac/D8/zipalign/apksigner), build-android-receiver.ps1 (existing pinned media SDK), test-android.ps1 (JVM parser/signature/manifest), test-android-protocol.py (real TLS/FFmpeg/SDL synthetic tests), smoke-desktop.mjs (native end-to-end).

APK подписан собственным RSA3072 key, V3 scheme для minSdk29. Signer SHA256 `2657a1dc1b3754231d3b6add16e51354f08bc8f0b26cd8137bac6d34fd0871c3`. Keystore/password в `.local/android-signing/` исключены из исходников, ZIP, APK, logs. Сохранять этот каталог для совместимых обновлений; не удалять как generated build cache.

Primary docs: [MediaProjection](https://developer.android.com/media/grow/media-projection), [AudioPlaybackCapture](https://developer.android.com/media/platform/av-capture), [Local network permissions](https://developer.android.com/privacy-and-security/local-network-permission), [OpenSSL in-memory certificates](https://docs.openssl.org/3.6/man3/SSL_CTX_use_certificate/). Context7 и Firecrawl использованы; SDK license owner explicitly accepted 2026-11-03. Точный итог — TEST_RESULTS.md и evidence JSON. Первый аппаратный чек-лист — DEVICE_VALIDATION.md.
