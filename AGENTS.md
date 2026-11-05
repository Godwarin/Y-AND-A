# Y AND A — правила разработки

- Работать только в этой папке. Пользовательское ТЗ: `CODEX_PROMPT.md`.
- Windows 11 x64, Tauri 2 + React/TypeScript + Rust. Живой native media HWND в центральном viewer; никаких кадров-скриншотов вместо потока.
- Только официальные закреплённые upstream, проверка SHA-256, лицензии в THIRD_PARTY_NOTICES.md. AirPlay GPL-3.0: исходники и изменения сохранять.
- Оригинал `public/animation/forty-two.js` копируется из архива без изменения геометрии. Mount/destroy, 14 FPS, пауза при скрытии, reduced-motion PNG.
- Все подписи на русском, #080808, единственный яркий акцент #E1192D.
- Не менять глобальный Firewall, реестр, драйверы и настройки других приложений. Только процессы приложения и собственные каталоги данных.
- Не логировать PIN, ключи, содержимое медиапотоков и персональные данные. Не включать автосинхронизацию clipboard.
- Не утверждать наличие видео/звука без доказательства. Физические тесты отдельно от программных fixture.
- После каждого этапа синхронизировать docs/CURATOR_HANDOFF.md, ARCHITECTURE.md, CHANGELOG.md, TEST_RESULTS.md. Указывать команды, ограничения, доказательства и следующий шаг.
- Проверки: npm run check, npm test, npm run build; cargo test/clippy; Playwright; native smoke и lifecycle тесты. Падение engine не должно завершать UI.
- Использовать локальный Node 24 через scripts/run-tool.mjs; frontend lint — npm run lint, браузерные тесты — npm run e2e. Chrome MCP отсутствует, проверенный fallback — установленный Edge.
- C++ receiver собирать scripts/build-airplay.ps1; не запускать vcpkg параллельно самому себе. Пробелы в путях FFmpeg обходятся только собственными TEMP build directories/junction с проверкой target.
- Сохранять YANDA_EMBEDDED isolation, запрет firewall helper, media-dump запреты, mDNS callback readiness и Windows SO_EXCLUSIVEADDRUSE. PIN не поддерживается — не показывать фиктивную опцию.
- Финальный native smoke: node scripts/smoke-desktop.mjs 'release/BETA-0.42/Windows/Y AND A.exe' --airplay. Он временно включает WebView2 debug port только для своего процесса и проверяет cleanup.
- После упаковки выполнять scripts/verify-package.ps1. Physical-phone статус остаётся UNVERIFIED_ON_DEVICE до указания реальной модели/ОС и доказательств; synthetic protocol/GPU проверки его не заменяют.

- История 0.2 (отменено новым требованием, не применять): пользователь разрешал упрощение Android: USB → tcpip допускается только по явной кнопке для авторизованного физического USB устройства. Отслеживать владение режимом и пытаться вернуть только собственное изменение в USB при stop/error/exit. Чужой ADB server и заранее включённый TCP mode не менять.
- Только исторический ADB-QR 0.2 требовал Wireless debugging; текущий companion QR 0.3 отладки не требует. Секрет только RAM, CSPRNG, срок 180 с; не логировать payload, не сохранять реальные QR screenshots/fixtures. Synthetic QR test values явно помечать.
- Компактное окно начинается только при реальном streaming, сохраняет исходную геометрию, 42 и controls. Состояние presentation отделено от медленного ADB mutex.
- iPhone 17 / iOS 27 / видео+звук: OWNER_REPORTED_PASS на 0.1.0, 2026-11-03. Это пользовательское физическое подтверждение, не тест агента. Android и новые функции 0.2.0 требуют аппаратной проверки.


## Новое обязательное направление 0.3.0
Пользователь исключил USB/Wireless debugging для Android. Основной Android путь — собственное приложение MediaProjection + AudioPlaybackCapture, QR pairing, локальная TLS-передача; ADB не запускается в этом сценарии. Старые инструкции 0.2.0 выше исторические, не предлагать их как основной путь. Владелец явно разрешил принять Android SDK license и собрать APK (ответ 2026-11-03). Системное согласие MediaProjection запрашивается каждый сеанс; не обходить DRM/FLAG_SECURE/audio capture policies. Подписывающий keystore и секреты QR не включать в source/portable ZIP или журналы. Базовый iPhone AirPlay сохранить.

- После black-viewer регрессии 2026-11-03 native streaming marker/resize НЕ доказывают видимые пиксели. Сохранять native pixel check на synthetic source (scripts/assert-native-video.ps1), separate WebView2 smoke profile и привязку helper SHA. Не записывать живой экран телефона для этой проверки. Hotfix artifact label может отличаться от неизменённой base app/APK version; использовать -ArtifactVersion при упаковке.

- OWNER_REPORTED_PASS video+audio: OPPO Reno5 Lite / Android13 на PC0.3.0-hotfix1 с APK0.3.0, 2026-11-03. До исправления nativeSDL viewer был пуст при streaming=true; исходный renderer действительно проваливает pixel regression. Сохранять эту проверку и не переименовывать synthetic кадры в physical-phone доказательства.

## BETA-0.42,2026-11-04

- Пользователь обозначил проверенную0.4.0-rc.1 как BETA-0.42. Не пересобирать её EXE/APK ради смены label. Пути задаются config/release.json + scripts/release-layout.ps1; релиз release/BETA-0.42/Windows, история archive/releases. Все100 application/runtime files сохранены побайтно (artifact-relocation.json).
- Новый owner PASS: OPPO Reno5 Lite/Android13, затем iPhone17/iOS27 — подключение, картинка и звук. Поворот/stop/denial в последнем ответе отдельно не подтверждены. Evidence beta-0.42-owner-validation.json; не спрашивать модель повторно.
- GitHub Godwarin/Y-AND-A PRIVATE, доступ на запись проверен. Не менять visibility; по порядку владельца сначала security validation, затем clean source upload. В Git не включать .local/keys/backups,build,archive,runtime binaries,SDK/caches или release assets.
- Владелец явно разрешил установку VirtualBox7.2.22 core и условия гостевой Windows. MSI использовал существующий <VirtualBox-installation>; VBOX_USER_HOME для своих VM только .local/security-vm/vbox-config. Чужие VM/config не открывать. Host Firewall/VBS/антивирус не отключать, host reboot без владельца не запускать.
- security-audit требует OS-isolated execution: offline guest/isolated loopback, explicit empty-env allowlist, read-only target/tools, scratch-only writes и OS resource limits. Сначала доказать эти controls на dummy; при неудаче не выполнять product tests и не выдавать NEEDS_VALIDATION за PASS.

## Подготовка GitHub, 2026-11-05
Владелец выбрал сначала проверку и подготовку чистых исходников для закрытого GitHub. Проверка source snapshot имеет отдельный результат от изолированных испытаний EXE/APK. Динамический статус остаётся NEEDS_VALIDATION. В текущей фазе VM не запускать и видимость репозитория не менять.
