# Продолжение проверки безопасности — 2026-11-04

Статус: **частичная проверка исходников и файлов; динамическая перепроверка NEEDS_VALIDATION**. Кандидат PC/APK0.4.0-rc.1 не одобрен для массового выпуска. Ничего не опубликовано.

## Область и метод

По запросу владельца применён `<user-profile>/.agents/skills/security-audit/SKILL.md` в focused guidance mode: повторный просмотр конкретных защит после исправлений, привязка прежних результатов к готовым бинарникам и проверка комплекта. Это не полный six-phase audit и не независимый пентест. Подходящего прежнего coverage-ledger/findings run нет; исторический SECURITY_AUDIT.md не заменяет такой ledger. Корень не является Git checkout; source ref фиксируется SHA256 просмотренных файлов в evidence/security-followup.json, без выдуманного commit.

Просмотрены:

| Граница | Источник и наблюдаемая защита | Что этим не доказано |
|---|---|---|
| LAN sender → AirPlay control/media | routes.cpp: proof Ed25519 и Approval key+peer до dispatch защищённых routes; approval.h: private stdin, случайный ID,20s, RAM-only | Физический handshake нового iPhone, отсутствие иных protocol flaws |
| Сетевые байты → RTSP память/потоки | rtsp_parser.cpp: строгая длина, duplicate/TE reject, body/header bounds/deadlines; TcpServer quotas | Поведение при всех malformed inputs, decoder memory safety |
| LAN client → Android QR session | native/android-receiver/main.cpp: bounded pending pool, one/IP, TLS deadline4s, constant-time token compare, закрытие listener после auth | Новый runtime regression в изолированной ОС, OEM capture lifecycle |
| Android intent → получатель одобренного экрана | MainActivity.java: pendingOffer до permission/consent, игнорирование новых offers во время pending/running | Реальная intent race/recreation/permission ревокация на телефоне |
| Helper output → привилегированный UI | log.cpp: полный regex lifecycle allowlist; engine.rs: line4096/queue256, проверка approval ID/срока | Отсутствие любого другого источника spoof, CPU/memory fuzzing |
| Загруженный web-контент → IPC | production CSP отделён от dev localhost; service не exported, backup/cleartext отключены в Android manifest | Все Tauri/WebView2 и OS security свойства |
| Архив → пользователь | пути/дубликаты/секретные имена, hashes компонентов, public dependency source hashes, PE mitigations | Полная антивирусная проверка, распаковка всех nested dependency archives, отсутствие произвольных секретов |

Новых подтверждённых уязвимостей с доказанным пересечением границы при этом ограниченном просмотре не установлено. Severity для непроверенных гипотез не назначается. Прежние YA-01..04 описывают старые бинарники; исправления нового RC и остаточные ограничения изложены в SECURITY_RELEASE_REVIEW.md.

## Сохранённые результаты

До прерывания сохранены security13, protocol13, native24, AirPlay26, CTest6, Rust11/Clippy, frontend/Vitest3/Playwright8, APK parser24/QR4 и криптографические fixture tests. Evidence связан с hashes EXE/helpers/APK. В этом продолжении они не запускались повторно. Условия прежних host-прогонов не подтверждены как соответствующие строгому sandbox контракту навыка; нельзя переименовывать их в новый изолированный audit PASS.

Новые операции выполняются доверенным кодом проверяющего: чтение исходников/метаданных, SHA256, создание и чтение ZIP без запуска их содержимого, подпись manifest. Код приложения, проектные test/build scripts и зависимые исполняемые файлы не запускаются. Новые зависимости не устанавливаются. Для исходного комплекта загружен только официальный публичный ZXing source JAR, сверенный с Maven digest и закреплённым SHA256; это не сетевой тест продукта.

## Почему динамические тесты отложены

Навык требует: «If every control cannot be enforced, do not execute target code». Доступная workspace sandbox не подтверждает scratch-only запись, read-only target/toolchain, пустой allowlist environment, изолированную loopback namespace и все CPU/RAM/process/disk/time limits одновременно. WindowsSandbox.exe/docker.exe не найдены; WSL enumeration вернул E_ACCESSDENIED. Настройки Windows/Firewall/виртуализации не менялись, полномочия не повышались для запуска target tests в обход этого ограничения.

Это ограничение методики исполнения, а не вновь найденная уязвимость приложения и не отказ automatic approval review.

## План безопасной валидации

Разработчику подготовить отдельную одноразовую Windows VM с заранее установленными локальными Node24/Python/Rust/C++/Edge/SDK. Не подключать host shares, clipboard, настоящие ключи, аккаунты и телефоны. Отключить внешнюю сеть VM; локальные клиент/сервер только внутри её loopback. ОС должна ограничивать target account чтением target/toolchain и записью только в выделенный scratch; запускать из пустого environment с явным списком безопасных переменных и scratch-local temp/cache/home. Системно ограничить CPU, RAM, число процессов, объём файлов/диска и время, включая дочерние процессы. Обычное открытие приложения в VM без этих контролей недостаточно.

Скопировать публичный source/binary candidate, сверить signed manifest и hashes. На synthetic principals выполнить минимальные негативные cases из test-security-candidate.py, протокольные и native/pixel/lifecycle tests, без загрузок из build scripts. Для каждого case записать точную команду, fixture input, allowlist environment и реальные лимиты. Проверить ALLOW/DENY/expiry/replay, unauth routes/length/deadline/quota, Android slow peer recovery, wrong pin/token, one-use QR. Уничтожить VM после сбора только ограниченных не содержащих секретов результатов. Не переносить из неё произвольные файлы: full audit требует parent-owned race-safe artifact promotion и независимой проверки кандидатов.

Отдельно владелец проверяет реальные Android/iPhone flows по OWNER_RELEASE_STEPS.md после передачи кандидата. Такие функциональные тесты не заменяют изолированный negative security regression. Затем пересмотреть release verdict для точных hashes; пока остаются неподтверждёнными backup, новые phone flows, изолированные tests и настройки публичного канала.

## Уточнение владельца после проверки

2026-11-04: владелец сообщил об успешном создании backup и переносе в отдельное место. Сам backup агент не читал и внешний носитель не проверял. Канал Telegram закрытый, для друзей, без публичного username; анимацию42 владелец создал сам и разрешил распространять с приложением. Эти факты закрывают прежние вопросы владельцу. Текущий комплект предназначен для закрытого функционального тестирования (CLOSED_BETA.md); новый isolated security PASS и одобрение широкого публичного выпуска по-прежнему отсутствуют.

Дополнительный read-only host preflight: Windows11 Home, hypervisor present; WindowsSandbox/Hyper-V PowerShell module и VirtualBox/QEMU/VMware в проверенных обычных путях не обнаружены. Наличие WSL executable само по себе не создаёт изолированный Windows guest для native HWND/WebView2 tests. Системные компоненты не устанавливались и не перенастраивались.
