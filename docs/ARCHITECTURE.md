# Архитектура Y AND A

React/TypeScript/Tauri2/Rust управляет native C++ FFmpeg/SDL HWND в viewer. Engine находится в Job-группе; падение engine не завершает UI. Original42: неизменённая геометрия,14FPS,visibility pause/reduced-motion. Presentation state отделён от media mutex; compact начинается после decoded video и восстанавливает прежнюю геометрию после stop.

Android10+: MediaProjection + AudioPlaybackCapture → H264/PCM → TLS1.3 pinned QR certificate + one-use256bit token/TTL180s → native receiver. ADB отсутствует. Destination фиксируется до consent; pending8/per-IP1/deadline4s,packet10s/write3s. DRM/capture policies не обходятся, media/QR/private keys не выводятся в files/diagnostics.

AirPlay: Ed25519 proof/key+peer → explicit PC approval/private stdin ID20s → fail-closed routes. TCP16,accept32/s,request40/s; bounded lengths/deadlines,max_pixels16M/thread2,media peer check. Trust RAM-only до stop. Trusted LAN: первое mDNS имя не удостоверяет приёмник, PIN/SRP не реализован.

APK имеет стабильный publisher cert. Keys защищены owner-only ACL/CurrentUser DPAPI, encrypted backup подтверждён владельцем. ECDSA-P256 manifest связывает hashes/размеры3загрузок и требует доверенного fingerprint. Windows Authenticode отсутствует.

Свежие scoped regression13+13PASS относятся к frozen receivers в offline LPAC guest. Trusted parent проверяет TCP PID/Job/executable и создаёт target-read-only proof; это не IPC продукта и не повышение его прав. Scope — [итог безопасности](SECURITY_VALIDATION_BETA_0.42.md).

Label BETA-0.42 отделён от code version0.4.0-rc.1 через config/release.json и release-layout.ps1. Релиз — release/BETA-0.42, история — archive/releases.100tested application files при обновлении docs не пересобираются. Source export publish/github исключает private dirs/keys/backups/SDK/runtime. Source ZIP добавляет pinned dependency sources, необходимые для GPL/сборки.

GitHub хранит код и будущие Release assets, в трансляцию не включён. В main закрытого Godwarin/Y-AND-A загружен исходный snapshot 0fb8cbe50f3298b9ac3d5f55bd59876fc58db73a: 308 файлов, remote blob hashes совпали. Source ZIP соответствует этому commit; последующий docs commit фиксирует загрузку. Tag и выпуск с assets ещё не созданы. Local package scripts не меняют remote commits/visibility, загрузка выполнялась GitHub connector. Product code и проверенные EXE/APK в этом этапе не менялись.

## Удаление запускателя резервной копии из GitHub, 5 ноября 2026

По просьбе владельца файл «СОХРАНИТЬ КЛЮЧИ.cmd» удалён из текущего main и исключён из ROOT_FILES экспортера, чтобы не возвращаться при следующей подготовке. Личные ключи и резервные копии не затрагиваются. Продуктовый код, EXE и APK не меняются; независимый агент не запускался. Проверка этого этапа: remote tree — файл отсутствует, остальные файлы сохранены. Старые commits не переписываются. Локальные подготовленные архивы соответствуют прежнему snapshot: перед загрузкой Release обновить source ZIP без запускателя и переподписать manifest; текущие assets не загружать как обновлённые.

## Независимый статический аудит, 5 ноября 2026

Уточнены границы доверия в локальном отчёте `docs/security-independent-2026-11-05/REPORT.md`. Android pin удостоверяет сертификат из текущего предложения. Выбор этого предложения проходит отдельную границу между внешним Intent и сканером. В AirPlay FairPlay handshake предшествует допуску SETUP. Согласие на SETUP сохраняет необходимость проверять все полученные от отправителя поля. Общие TCP-слоты и HLS registry также имеют отдельные границы по ресурсам и времени жизни.

## Исправления после независимого аудита, 5 ноября 2026

Входы получателя на Android ограничены встроенным сканером и ручным вводом. AirPlay ограничивает соединения до согласия, проверяет режим FairPlay на двух уровнях и освобождает сокеты при повторном SETUP. HLS-операции в штатном режиме отключены. Подписываемый APK связан с вложенной и проверенной копиями. [Подробности](SECURITY_REMEDIATION_2026-11-05.md).

## Кандидат 0.42a для проверки на телефонах

Комплект 0.42a использует протокол Android YANDA03 и прежнюю подпись APK для обновления. Исходники Rust/Tauri имеют SemVer 0.4.0-rc.2. Windows EXE, AirPlay и Android helpers пересобраны. Режим `package.ps1 -ForDeviceTesting` собирает отдельный ZIP без прежних отчётов в `Windows/docs/evidence`.

Изолированная регрессия приёмников использует отдельные ISO только для чтения и офлайн-гостя с тестовой учётной записью LPAC. Контроллер сверяет SHA-256 приёмников, проверяет ограничения на пробных процессах и передаёт на хост только фиксированные статусы по виртуальному COM-порту. После попытки хост возвращает исходный снимок. Проверка различения отправителей AirPlay с одинаковым видимым IP остаётся открытой.

Диагностические сравнения LPAC, AppContainer и обычного ограниченного токена используют только приостановленные пробные процессы. Полный набор ограничений требуется для запуска приёмников. [Состояние стенда](ISOLATED_STAND_PLAN.md).

Обычное подключение физического телефона проверяет работу интерфейса и медиапотока на рабочей Windows. Устойчивость приёмников к некорректным запросам проверяется на синтетических данных в гостевой Windows. Результаты этих проверок учитываются отдельно.

Отчёт владельца по 0.42a привязан к версии комплекта. Отдельная запись стенда содержит SHA-256 приёмников и доказательства изоляции. [Пользовательская проверка](evidence/0.42a-owner-validation.json), [стенд](evidence/0.42a-isolated-validation.json).

Снимок для закрытого GitHub формируется по явному списку исходников и документации. Верификатор сверяет хэши исходников и копий, вычисляет общий SHA-256 дерева и проверяет локальные ссылки и обязательные лицензии.

Архив исходников 0.42a объединяет проверенный снимок с версионированным набором зависимостей. При упаковке проверяются SHA-256 каждого файла и закреплённые хэши ImGui и нативных архивов. Проверка архива читает его без распаковки.

В диагностике гостевого стенда проверяется запуск LPAC через доверенный процесс тестового пользователя, вошедшего в консоль. Контроллер назначает этому процессу Job Object до запуска. Доверенный процесс создаёт дочерний AppContainer приостановленным. Перед продолжением он сверяет идентификатор пакета, ограничения токена, членство в Job Object и фактический доступ к двум тестовым файлам. Сетевые тесты допускаются после проб записи, loopback, лимитов и завершения потомков.
