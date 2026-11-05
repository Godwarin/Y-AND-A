# Проверка безопасности Y AND A — 2026-11-03

**Вердикт: NO-GO для широкого публичного выпуска текущей 0.3.0-hotfix1 / APK 0.3.0.**

Закрытое тестирование в доверенной домашней сети возможно с пониманием перечисленных ограничений. Проверка выявила воспроизводимые недостатки сетевой защиты Windows-приёмников и недостаточную защиту ключа подписи на машине сборки. Она не выявила подтверждённого удалённого выполнения кода, обхода Android MediaProjection consent или передачи экрана в облако. Это ограниченный аудит исходников и артефактов, а не гарантия отсутствия уязвимостей и не независимый пентест.

## Что именно проверено

| Артефакт | SHA-256 |
|---|---|
| Windows `Y AND A.exe` в hotfix1 | `5ac49e7b6b91bf1318048f95759c79e9b3b66d76c6d94eb19cac703f8edd4d7e` |
| Android APK 0.3.0 | `ba546d744221a9d4fd12137f410dbdf8277c9c92aa4a34760dd5dbd0ed428bfc` |
| Android Windows receiver hotfix1 | `daef37ca0b5df504c34b3b39a6d24374a7d13d857ed4d98440a1d89ec03b35f2` |
| AirPlay Windows receiver | `445d866fad65d5cb8b2c6daf7d9e2249f4d86fb115c8d40832c7da8cc2606b31` |
| Portable ZIP hotfix1 | `fc7eee131c49cfaa75ed60bbc71a3c158524603220a83c8fcfe20a66a76d3eca` |
| Source ZIP hotfix1 | `121b932110f5b36ca508d39235adbd7331945ccfd92f82eb6c85952472c8ab3e` |

Граница проверки: Android Java/manifest/QR/foreground service/TLS, Rust supervisor/IPC, React/CSP/capabilities, C++ Android transport/decoder, сетевые маршруты и парсер встроенного AirPlay, разрешения и подписи готовых файлов, состав двух ZIP, точные npm/Cargo/ZXing версии. Самостоятельного приложения для iPhone нет: проверялась Windows-сторона AirPlay. Системные компоненты Android, iOS и WebView2 не сертифицировались.

Сборки не изменялись и не переупаковывались в ходе аудита. Добавлены скрипты проверки и документация. Отчёт находится вне уже выпущенных ZIP; их старые функциональные PASS не означают SECURITY PASS.

## Подтверждённые замечания

### YA-01 — высокий: AirPlay не авторизует владельца отправителя

`vendor/airplay-windows/src/airplay/routes.cpp`, `dispatch`, `handle_stop`, `handle_pair_setup`; `src/net/tcp_server.cpp` в том же vendor.

При включённом AirPlay слушатель привязан к `[::]:7000` с IPv4/IPv6. Нет PIN, списка доверенных отправителей и подтверждения нового телефона на ПК. Криптографический pair-verify проверяет владение предъявленным ключом клиента, но не разрешение владельца ПК этому клиенту. Маршруты управления доступны без завершения pair-verify: в отдельном процессе **`POST /stop` без каких-либо credentials вернул `RTSP/1.0 200 OK`**.

Это позволяет доступному по сети клиенту отправлять управляющие запросы и пытаться инициировать свои сеансы. Реальное прерывание чужой активной трансляции не выполнялось; доступность обработчика подтверждена, последствия для живого сеанса выведены из кода. Это не доказательство чтения экрана Windows или перехвата существующего зашифрованного iPhone-сеанса.

Утверждение «только ваша сеть» не является сетевым ACL: глобальные IPv6, VPN и разрешающий Firewall могут сделать слушатель доступным за пределами предполагаемой домашней LAN. Приложение не ограничивает AirPlay только частными адресами/интерфейсом. Маршрутизация и Firewall влияют на достижимость.

До публикации: реальная авторизация нового отправителя и привязка управляющих/медийных соединений к разрешённому сеансу; ограничение интерфейсов/сети. Фиктивное поле PIN проблему не устраняет. При сохранении режима без PIN его нельзя представлять как защищённое соединение только двух выбранных устройств.

### YA-02 — высокий: AirPlay допускает неограниченный расход ресурсов до авторизации

`vendor/airplay-windows/src/airplay/rtsp_parser.cpp:33,57,129`; `src/net/tcp_server.cpp:166,180`; `src/airplay/server.cpp:handle_client`.

64 KiB ограничение заголовков есть. Для `Content-Length` нет верхнего лимита тела: `fill` растит строку до объявленной длины, затем тело копируется в `Request.body`. Нет строгого полного разбора числового поля и запрета конфликтующих/повторных Content-Length. Для каждого принятого соединения создаётся поток без общего ограничения числа клиентов; абсолютного срока получения управляющего запроса нет. TCP keepalive и SO_SNDTIMEO не заменяют эти ограничения. Исключения выделения памяти/создания потока не локализованы на уровне обработчика.

Ограниченный тест готовой сборки: тело **1 MiB** без авторизации было обработано с ответом `501 Not Implemented`, без `413`; одновременно приняты **12** idle-соединений. Это подтверждает поведение небольшими входами; отсутствие общего предела установлено по исходникам. OOM, массовый flood и доведение ПК до отказа намеренно не выполнялись. Риск — исчерпание памяти/потоков и остановка медиапроцесса доступным по сети клиентом. Падение всего UI не доказано.

До публикации: маршрутные лимиты тела, строгий Content-Length с checked arithmetic, общий лимит клиентов/памяти, абсолютные deadlines, ограничение частоты запросов, обработка исключений внутри worker. Дополнительно установить max_pixels/размеры и ограничение decoder threads в AirPlay H264/HEVC decoder, включая software fallback: текущий Android decoder это делает, AirPlay video decoder — нет. Cover-art decoder уже ограничен 4096×4096, mirror payload — 2 000 000 bytes; это не заменяет ограничений RTSP тела и декодированной видеопамяти.

### YA-03 — средний: Android-приёмник можно занять до проверки одноразового ключа

`native/android-receiver/main.cpp:58,97,107,113`.

Один поток последовательно выполняет accept → SSL_accept → чтение 72 bytes аутентификации. SO_RCVTIMEO=5 s действует на отдельные операции; `readExact` не проверяет абсолютный deadline. Проверка TTL QR выполняется после чтения всего сообщения. Клиент, отправляющий понемногу, удерживает единственный обработчик дольше ожидаемого. В тесте одна синтетическая TLS-сессия без token удерживала его **10.01 s**, а handshake следующего клиента завершился таймаутом.

Это отказ в подключении, а не обход TLS/pinning/token и не доступ к изображению. Обычный полностью молчащий клиент закрывается примерно через 5 s, после чего нормальное подключение работает.

До публикации: абсолютные deadlines TLS handshake/auth, ограничение ожидания общей датой истечения QR, возможность продолжать принимать другие ограниченные handshake-сессии; абсолютные сроки чтения пакета после auth. Нельзя продлевать deadline очередным байтом. Проверить также Rust state: готовность слушателя сейчас может вернуть `connecting` в `waiting` после auth, обходя задуманный 30-секундный video timeout.

### YA-04 — высокий для выпуска: ключ APK и пароль доступны другим локальным пользователям

`.local/android-signing/` и резервная копия `build/android-signing/`; `scripts/build-android.ps1`.

В обеих папках keystore и plaintext-файл пароля наследуют Allow для `S-1-5-11` (Authenticated Users: Modify) и `S-1-5-32-545` (Users: ReadAndExecute). Ключ и пароль проверялись только по ACL/наличию; их содержимое не печаталось и не отправлялось наружу. Другой обычный пользователь с доступом к этим путям может получить оба файла и подписывать APK тем же сертификатом. Подписанное таким образом обновление ещё нужно доставить и установить на телефон; автоматический захват телефона этим замечанием не доказан.

**В распространяемых APK/portable/source ZIP эти файлы не обнаружены.** Проблема находится на машине сборки. Наличие у постороннего пользователя доступа к этой машине или фактическое копирование ключа не устанавливалось.

До публикации: ограничить ACL всех копий ключа/пароля аккаунтом сборки и администраторами, вынести долговременный секрет из `build`, отделить пароль от файла ключа и создать зашифрованную резервную копию вне распространяемого проекта. Не удалять и не менять ключ самовольно: это нарушит совместимость обновлений установленного APK. Если доступ третьего лица уже был возможен, отдельно оценить необходимость смены ключа до первого массового выпуска. Одно ужесточение ACL не отзывает ранее скопированные ключи.

### YA-05 — средний для распространения: Windows-бинарники не имеют подписи издателя

`Get-AuthenticodeSignature`: главный EXE и оба собственных receiver EXE — `NotSigned`. SHA256SUMS проверяет целостность относительно манифеста, но злоумышленник может заменить и ZIP, и неподписанный манифест. Это риск подмены дистрибутива, не доказательство вредоносности файлов.

До широкого выпуска: проверяемый канал загрузки от владельца, подпись релиза/манифеста с опубликованным доверенным ключом; желательно Authenticode для Windows-бинарников с timestamp. Self-signed сертификат без установленного доверия не даёт публичной идентификации издателя. Разрешение этой задачи потребует настоящего ключа/сертификата владельца; в аудите он не создавался и не приобретался.

### YA-06 — средний приоритет: нативные версии отстают от security fixes

В составе сборки OpenSSL **3.6.2**, FFmpeg **8.1**, SDL2 **2.32.10**, libplist **2.7.0**. Подтверждены PE version resources OpenSSL/SDL и pinned vcpkg status. На 2026-11-03 официальный OpenSSL перечисляет исправления вплоть до **3.6.5**; FFmpeg — security fixes **8.1.2**.

Нельзя считать каждую запись CVE достижимой в Y AND A. Примеры проверки применимости: OpenSSL CVE-2026-84782 относится к DTLS, которого Android transport не использует; CVE-2026-34180 прямо не затрагивает Windows x64; CVE-2026-35189 касается обработки сертификатов peer, а Android receiver не запрашивает client certificates. У FFmpeg CVE-2026-8461 связан с MagicYUV, который этот receiver не выбирает; официальный fix CVE-2026-30999 меняет `tools/zmqsend.c`, этот tool не поставляется. Подтверждённой эксплуатации этих CVE через приложение нет.

До выпуска: закрепить поддерживаемые версии с актуальными исправлениями, пересобрать оба receiver и зависимости, повторить native/pixel/protocol tests. Проверка всех нативных транзитивных библиотек по всем CVE не завершена: поисковый результат без advisories для SDL/libplist не доказывает отсутствие уязвимостей. Обновление должно охватывать также bzip2, brotli, zlib, libpng, freetype и CRT; при необходимости вести SBOM и документировать исключения по достижимости. Простое обновление DLL без ABI-проверки не применять.

Источники: [OpenSSL 3.6 advisories](https://openssl-library.org/news/vulnerabilities-3.6/), [FFmpeg security](https://www.ffmpeg.org/security.html), [официальный fix zmqsend](https://github.com/FFmpeg/FFmpeg/commit/144af8f81abc1385631b4e1f4672cd415a9c6e05). Это данные upstream; оценка применимости выше — анализ кода приложения.

### YA-07 — низкий для пользователя, средний для сборки: dev-зависимость minimatch

Полный npm audit: **11 moderate affected package nodes**, происходящих от одного advisory **GHSA-g3hv-75wg-m249** в `minimatch 10.2.6` и цепочек ESLint/typescript-eslint. Это не 11 независимых дыр. Пакет помечен devOnly, в пользовательский frontend он не входит. Production npm audit: **0 известных advisories**. Уязвимость требует контроля glob pattern и optimizationLevel ≥2; это не сетевой вход Y AND A. Исправленная upstream версия — 11.0.1. Не применять автоматически предложенные npm откаты ESLint до 4.0.0: нужен совместимый update/override с проверкой lint.

OSV проверил **624 уникальные пары package/version** npm, crates.io и ZXing Maven. Найдены тот же minimatch, glib 0.18.5 (RUSTSEC-2024-0429 и его GHSA alias — одна проблема), proc-macro-error 1.0.4 (RUSTSEC-2024-0370, unmaintained). Обе Rust-зависимости отсутствуют в `cargo tree --target x86_64-pc-windows-msvc`; это не подтверждённые уязвимости поставленного Windows EXE. ZXing 3.5.4 не получил совпадений в OSV. OSV не заменяет ручную проверку нативных библиотек и неизвестных уязвимостей.

Источники: [maintainer/GitHub advisory minimatch](https://github.com/advisories/GHSA-g3hv-75wg-m249), [RustSec glib](https://rustsec.org/advisories/RUSTSEC-2024-0429.html), [RustSec proc-macro-error](https://rustsec.org/advisories/RUSTSEC-2024-0370.html), [OSV](https://osv.dev/). Полные результаты и attribution сохранены в `security-evidence/dependency-osv.json`.

## Что проверено положительно

- Подпись готового APK проходит apksigner. Сертификат SHA-256: `2657a1dc1b3754231d3b6add16e51354f08bc8f0b26cd8137bac6d34fd0871c3`. Минимальный Android API29, target36; нет debuggable/testOnly, backup выключен.
- В actual APK нет SMS, контактов, файлового хранилища, геолокации, accessibility/device-admin и разрешений отладки. Шесть разрешений: интернет, камера QR, запись аудио для AudioPlaybackCapture, уведомления и два foreground-service permissions. Микрофонный источник в коде не используется. MediaProjection consent требуется каждый сеанс, service/scanner не экспортированы, PendingIntent immutable.
- Передача Android — TLS1.3, сертификат сверяется по SHA256 из QR, token создаётся CSPRNG (256 bit), передаётся helper через stdin и живёт в памяти. Нет trust-all fallback. API снимок состояния/диагностика не содержит QR token. Android принимает частные/link-local IPv4 без DNS и не включает облачный relay. Custom `SSLSocket` проверен отдельно: одного manifest usesCleartextTraffic=false для него было бы недостаточно.
- Реальный Windows transport повторно прошёл 13/13 protocol checks: TLS1.2 отклонён, неправильный token отклонён без потребления валидного, session одноразовая, packets ограничены, остановка закрывает listener. Pinning на Android проверялся по коду; runtime negative MITM test на физическом Android не проводился.
- Дополнительные malformed packet tests отклоняют unknown type, неверное выравнивание PCM, пустой H264 и oversized PCM до ложного streaming. Полностью молчащий неавторизованный TCP клиент закрывается.
- Нет обнаруженного облачного upload/телеметрии, неявной записи экрана на диск или автоматического чтения clipboard в рассмотренном собственном коде. AirPlay embedded logging фильтрует персональное содержимое, media-dumps выключены; HLS proxy/player и USB supervisor в текущем пути не запускаются.
- Tauri capabilities привязаны к main, без remote URLs и fs/shell plugins; CSP запрещает script eval/внешние scripts/frames/objects. Строки UI выводятся React без dangerouslySetInnerHTML. Удалённые origins не получают IPC по умолчанию согласно [документации Tauri](https://github.com/tauri-apps/tauri-docs/blob/v2/src/content/docs/security/capabilities.mdx). Пользовательские IPC параметры ограничиваются backend. Job object завершает дочерние процессы; он не является sandbox с пониженными привилегиями.
- 59 PE файлов содержат ASLR/DYNAMIC_BASE и NX flags. Это не доказывает отсутствие memory-safety ошибок; CFG flag отсутствует у трёх собственных EXE. Для последующей сборки рассмотреть /guard:cf и проверку фактических runtime mitigations.
- Проверка ZIP SHA256SUMS: 592 файла PASS. В двух ZIP/APK нет опасных путей распаковки, имён keystore/password/identity, найденных PEM private-key markers; просмотрено 621 текстовых файла по ограниченному шаблону. Это ограниченный secret scan, не полная проверка произвольных бинарных секретов. Сам архив не является проверенным издателем.

## Дополнительные задачи усиления

1. Rust stdout/stderr bridge использует unbounded mpsc и `lines()` до проверки длины. Ограничить очередь и выделение на строку, coalesce повторяющиеся marker-события. Авторизованный Android sender способен генерировать много type4 markers; нагрузочный OOM тест не проводился.
2. Android MainActivity: exported deep-link может менять mutable `offer` через onNewIntent, а onActivityResult читает текущее offer после системного согласия. Заморозить destination на время permission/consent flow и не подменять его новым intent. Возможность эксплуатации конкретного lifecycle пока не воспроизведена на устройстве; это замечание ревью, не доказанный обход consent.
3. Разделить production CSP и devCsp: production пока разрешает connect к localhost:1420 от dev server. Подтверждённой XSS/утечки через это разрешение нет.
4. Публично описать передачу полного экрана, чувствительные уведомления, доверие к QR и ограничения AirPlay; оформить канал сообщения об уязвимостях. Не обещать, что ОС/другая программа не может сохранить видео, увиденное на ПК.

## Доказательства и повторение

Из корня проекта, PowerShell:

```powershell
./scripts/test-android.ps1
./scripts/verify-package.ps1 -ArtifactVersion 0.3.0-hotfix1
./.venv/Scripts/python.exe scripts/test-android-protocol.py
./.venv/Scripts/python.exe scripts/audit-network.py
./.venv/Scripts/python.exe scripts/audit-artifacts.py
./.venv/Scripts/python.exe scripts/audit-dependencies.py --query
# Node 24 из toolchain в PATH:
npm audit --json
npm audit --omit=dev --json
cargo tree --manifest-path src-tauri/Cargo.toml --locked --offline --target x86_64-pc-windows-msvc
```

Network audit использует только собственные helper процессы из точной hotfix1 папки и loopback, публичный synthetic token, максимум 12 idle AirPlay sockets и 1 MiB body. До AirPlay запросов проверяет PID listener; при занятом 7000 пропускает эту часть. Свой helper завершает по сохранённому process object. Существующие сеансы/чужие процессы/Firewall не меняет. Сохранённых кадров настоящего телефона нет. В этой среде loopback и сетевые запросы из sandbox потребовали разрешённого исполнения вне sandbox; повторные прогоны завершились. Это не обход защит продукта.

`security-evidence/network.json`: audit execution COMPLETE, 7 passed safety/negative-input checks, 3 confirmed observations, skipped=0. Это **не security PASS**. `dependency-osv.json`: все 624 запроса завершены без ошибок/пагинации. `npm-audit*.json`, `apk-manifest.txt`, `apk-permissions.txt`, `artifacts.json`, `windows-signatures.json`, `signing-key-acl.json`, `cargo-windows-*.txt` содержат остальные доказательства. В ACL отчёте сохраняются только общие SID, не имя/индивидуальный SID владельца и не секреты.

Frontend/Rust функциональные suites не повторялись: продуктовый код не менялся. Предыдущие native24/pixel regression остаются функциональными доказательствами только для соответствующих hashes. Android protocol13, APK parser15/QR4 и packaging592 в этом аудите повторены.

Владелец сообщил об успешной работе на дополнительных устройствах без моделей/ОС. Это OWNER_REPORTED_PASS общего функционального теста, не пентест. Сохраняются отдельные ранее сообщённые iPhone17/iOS27 и OPPO Reno5 Lite/Android13 результаты. Агент не управлял физическими телефонами; отказ в permissions, lock/stop/reconnect, single-app capture и негативный MITM test на Android/OEM требуют аппаратной проверки. Fuzzing с sanitizers, независимый анализ, exhaustive CVE review всех native transitives, оценка лицензий/готовности магазина и антивирусная сертификация в этот отчёт не входят.

## Условия пересмотра решения

1. Закрыть YA-01/02/03 и защитить все копии signing key (YA-04), добавить регрессионные negative tests.
2. Обновить/проверить нативные зависимости и dev toolchain с документированными исключениями по применимости; проверить цепочку распространения (YA-05/06/07).
3. Пересобрать новым номером версии, сохранить совместимость подписи APK, повторить functional/native pixel/protocol/packaging suites и физические stop/permission/MITM проверки.
4. Сделать повторный security review новых hashes. Только после этого дать отдельное заключение о готовности публичного кандидата. Нынешний отчёт не разрешает объявлять hotfix1 «проверенной безопасной публичной версией».
