# Итог, 5 ноября 2026

Изолированные security13/13 и Android protocol13/13 PASS на точных frozen BETA-0.42 receivers после всех OS sandbox probes. Подробности и ограничения: [SECURITY_VALIDATION_BETA_0.42.md](SECURITY_VALIDATION_BETA_0.42.md). Это scoped regression result; исторические NEEDS_VALIDATION ниже описывают прежние этапы. Публикация не выполнялась. По поручению владельца подготовлен актуальный source ZIP с итоговыми документами и проверочным скриптом; готовность комплекта проверяется packaging/signature/readiness tools.

# История до завершения lpac69
# Текущий статус, 5 ноября 2026

Проверка чистых исходников для закрытого GitHub выполняется командой python scripts/verify-github-source.py. Результат этого этапа относится к составу копии проекта, целостности, поиску секретов, лицензиям и документации.

Новая изолированная перепроверка EXE/APK остаётся NEEDS_VALIDATION, 0 из 26 продуктовых проверок. Подтверждённые владельцем подключение, видео и звук на Android/iPhone перечислены в TEST_RESULTS.md. Далее сохранён исторический отчёт об исправлениях кандидата 0.4.0-rc.1.

Проверка готовых загрузок по отдельному запросу владельца 5 ноября: официальный Microsoft Defender не нашёл угроз во всей release/BETA-0.42; подписи APK/манифеста, неизменность100 файлов, архивы и57PE проверены. OSV625 повторён без ошибок. Команды и ограничения — BINARY_RELEASE_CHECK.md. Ни сканирование, ни метаданные не заменяют новые изолированные protocol/security tests. Бинарники и видимость GitHub не публиковались/не изменялись.

# Повторная проверка: кандидат Y AND A 0.4.0-rc.1

Дата:2026-11-04. **Комплект закрытой функциональной беты для друзей; массовая публикация не одобрена. Новые phone flows и изолированная проверка защит ещё требуют подтверждения.** Это не независимый пентест и не гарантия отсутствия неизвестных ошибок. Предыдущий NO-GO в SECURITY_AUDIT.md относится к0.3.0-hotfix1; прежние архивы не исправлялись задним числом.

## Границы продолжения проверки 2026-11-04

Применён security-audit в focused guidance mode к исправлениям и комплекту кандидата. Ниже PASS — сохранённые результаты до прерывания, сверяемые по hashes, а не новый прогон по этому навыку. Новые сетевые/native/crypto tests не запускались: требуемая OS-enforced isolation с закрытой сетью, allowlist environment, read-only target/toolchain, scratch-only writes и ресурсными лимитами недоступна. Независимой верификации свежими агентами и полного six-phase audit не было. Новых подтверждённых уязвимостей при ограниченном просмотре не установлено; это не доказательство их отсутствия. Повторные dynamic checks — NEEDS_VALIDATION. Подробный scope/план в SECURITY_FOLLOWUP_2026-11-04.md.

## Результаты исправлений

| Замечание прошлого аудита | Изменение и доказательство | Статус кандидата |
|---|---|---|
| YA-01: AirPlay без авторизации отправителя | Валидная Ed25519 подпись клиента + явное разрешение на ПК по fingerprint и peer. Управляющие/медийные routes без этого отвечают470. Другой ключ отклоняется. Разрешение RAM-only до stop. ID20s, старые/неверные ID не принимаются. | Исправлено программно; новый handshake требует аппаратного теста iPhone |
| YA-02: сетевые ресурсы AirPlay | Макс16 concurrent control clients,32 accepts/s,40 requests/s/client. Content-Length строго разбирается; duplicate/Transfer-Encoding/overflow/oversize отклоняются до body allocation. Неавторизованное тело≤64KiB, header≤64KiB; artwork≤8MiB только после auth. Абсолютное чтение запроса, idle timeout до auth; авторизованная пауза сохраняется. H264/HEVC max_pixels16M/thread2, включая fallback. Media peer проверяется перед обработкой. | CTest6 и negative tests PASS |
| YA-03: медленный Android pre-auth sender | Nonblocking listener/TLS, до8 pending handshakes/по1 на IP,32 accepts/s; единый deadline handshake+auth4s и ограниченный TTL QR. Header+body packet10s, write3s. Победившая одноразовая auth закрывает listener и остальные pending sockets. Rust сохраняет video timeout после auth. | Trickled auth, incomplete packet, восстановление и подключение другого адреса во время медленного клиента PASS |
| YA-04: доступный ключ подписи APK | Keystore не менялся; обе копии закрыты owner/System/Admin DACL, plaintext password заменён CurrentUser DPAPI. Другим локальным пользователям запрещено менять исходники/скрипты сборки. Portable backup AES-256-GCM/PBKDF2-SHA256 с проверкой целостности, ручным секретом владельца. | Локальная защита и прежние crypto tests PASS; 2026-11-04 владелец сообщил об успешном создании и переносе backup отдельно |
| YA-05: доверие к дистрибутиву | ECDSA P-256 подпись manifest с SHA256/размерами ZIP/APK, стабильный публичный ключ. Private key DPAPI-only. Проверка wrong publisher/tampered data и подписанных файлов. | Компенсация для доверенного Telegram-канала; Authenticode у EXE отсутствует |
| YA-06: обновления native | Официальные pinned OpenSSL3.6.5#2, FFmpeg8.1.2#3, libplist2.8.0; обновлены freetype2.15.0, libpng1.6.59, zlib1.3.2. FFmpeg8 ABI сохранён официальным overlay, источники/patches/hashes включены. | SDK rebuild и protocol/native tests PASS |
| YA-07: dev minimatch | Override11.0.1, совместимость check/lint/build/e2e проверена. Полный и production npm audit:0 известных advisories. | Исправлено |

Дополнительно: Rust event queue256 и строка≤4096 bytes; повторяющийся Android audio-unavailable coalesced. Android фиксирует destination до permission/MediaProjection consent, новые intents во время этого flow не меняют адресата. QR parser больше не строит рекурсивные URI из alt; строгий список полей/путь/порт/локальные IPv4,24 негативных/положительных JVM checks. Production CSP отделён от dev localhost. Собственные C++ receivers и Rust собираются с CFG/CET compatibility flags.

При дополнительном ревью найден и закрыт spoof служебного события через метод сетевого запроса `YANDA_VIDEO`: embedded log теперь пропускает только полный точный формат lifecycle events. Реальный запрос с таким методом не создаёт video marker; negative test PASS. Исправлен также CRLF в приватном stdin approval protocol, проверены ALLOW/DENY через настоящие helper процессы. Эти находки были исправлены до итогового пакета, результаты промежуточных неудачных прогонов не являются финальным verdict.

## Что проверено на готовых компонентах

- Android actual APK: подпись прежним RSA3072/V3 certificate, versionCode400; parser24, desktop QR→ZXing4 rotations, manifest/permissions/credentials checks PASS. Сертификат SHA256 `2657a1dc1b3754231d3b6add16e51354f08bc8f0b26cd8137bac6d34fd0871c3`.
- TLS/H264/SDL transport13/13 PASS на новом Android helper. Проверены отказ TLS1.2 и неверного token, одноразовая сессия, decode/rotation, queue/audio flags, отсутствие media/certificate dumps.
- Security regression13/13 PASS: absolute deadlines, another peer during slow Android auth, unauthorised routes, lifecycle spoof rejection, неверный/старый approval ID, DENY/ALLOW, другой sender key, concurrent cap,20s expiry. Только owned helpers/loopback/public synthetic credentials.
- Native Windows smoke24/24, page errors0: настоящий видимый synthetic video pixel check, compact/rotation/restore, native volume/lifecycle, актуальные helpers и интерфейс разрешения. AirPlay protocol26/26, включая проверку подписей и авторизованный media setup. Авторазрешение теста допускает только заранее известный fixture key с loopback; реальные LAN senders автоматически не разрешаются.
- CTest6/6, Rust11/11 и Clippy(-D warnings), TypeScript/lint/Vite/Vitest3, Playwright8/8 PASS. UI approval visually inspected on synthetic fixture; оригинальная42 сохранена.
- OSV625 package/version queries завершены без ошибок после повторения transient503. Остались glib unsoundness GHSA/RustSec aliases и proc-macro-error unmaintained из не входящих в Windows target зависимостей. Это не новые подтверждённые уязвимости Windows binary. Full/prod npm audit0. Нативный exhaustive CVE/fuzz audit не заявляется.
- Source ZIP получает полные GPL changes и526 проверенных public dependency source inputs. Секреты/DPAPI/backup/build-state в public ZIP запрещены verifier. Контрольные суммы, PE flags и финальные archive tests привязываются к конкретным hashes в evidence и подписанном manifest; их значения не переносить между пересборками.

Команды и машинные результаты: `docs/evidence/security-candidate.json`, `android-protocol.json`, `android-apk.json`, `native-smoke.json`, `airplay-protocol.log`, `dependency-osv.json`, `npm-audit-all.json`, `packaging-verification.json`. Скрипты: test-security-candidate.py, test-android-protocol.py, smoke-desktop.mjs, verify-package.ps1, sign-release.ps1, verify-release-signature.ps1.

## Остаточные ограничения и действия владельца

1. Новый iPhone approval и обновлённый APK ещё требуют реальных video/audio/rotation/stop/denial тестов. Предыдущее подтверждение OPPO/iPhone для0.3.0 не заменяет эту проверку. Android destination freeze оценён по коду; runtime intent-race/permission tests на телефоне агент не выполнял.
2. AirPlay рассчитан на доверенную LAN. Подтверждение ключа отправителя на ПК не является PIN/SRP, вводимым на iPhone, и не доказывает подлинность выбранного по имени приёмника при первом подключении. Публичные/недоверенные сети, поддельные mDNS приёмники и активный LAN MITM выходят за обещания этого режима. Android QR certificate pinning имеет другую модель доверия. Не рекламировать оба режима как одинаковую сквозную защиту.
3. EXE/DLL без Authenticode могут вызывать предупреждения Windows. Отдельная подпись manifest полезна только при доверенном, отдельно закреплённом publisher fingerprint. Подмена канала первой загрузки не решается ключом из того же ZIP. Владелец выбирает доверенную доставку через свой Telegram и при необходимости оформляет настоящую Windows signing identity; секреты в чат не передаются.
4. Владелец 2026-11-04 подтвердил создание переносимого backup и перенос в отдельное место; агент сам backup/носитель не проверял. DPAPI не переживает любую потерю Windows-учётки. Ужесточение ACL не отзывает ключ, если он был скопирован ранее; признаков такой утечки не обнаружено, отсутствие прежнего копирования не доказано.
5. Владелец уточнил закрытый Telegram-канал для знакомых без username; обратная связь лично автору. Исходники и notices приложены. Владелец подтвердил авторство42 и разрешение распространения с приложением. Юридическое заключение/магазинная сертификация не выполнялись.

**Пока эти действия не подтверждены, распространяемый комплект следует считать кандидатом для проверки, а не окончательным разрешением массового публичного выпуска.** Инструкция владельцу — OWNER_RELEASE_STEPS.md; инструкция пользователям — USER_GUIDE.md/PRIVACY.md. Подпись manifest указывает candidate status, пока решение не пересмотрено явно.
