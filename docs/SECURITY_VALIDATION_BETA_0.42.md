# Итог проверки BETA-0.42, 5 ноября 2026

**PASS в объёме запланированной проверки защит и протокола.** Блокирующих проблем в завершённых проверках не обнаружено. Можно переходить к подготовке публичного бета-выпуска после решения владельца. Это ограниченное регрессионное ревью, не независимый пентест и не гарантия отсутствия любых ошибок.

## Свежие изолированные результаты

| Проверка | Результат |
|---|---|
| Security regression на настоящих Android/AirPlay receivers | 13/13 PASS |
| Android TLS/H264/PCM protocol | 13/13 PASS |
| Offline network, explicit environment, read-only target/tools, scratch-only writes, resource limits, loopback, descendant cleanup | Все семь controls PASS на dummy до запуска тестов |
| USER32 private window, Python parent/child/quota/timeout | PASS |
| Владение AirPlay TCP7000 | Независимый доверенный контроллер проверил Job PID membership и точный путь настоящего receiver EXE |
| Заключительное локальное сканирование актуального release/BETA-0.42 | Microsoft Defender завершился exit0, угроз не найдено; hashes комплекта в beta-0.42-defender-final.json |
| Завершение | Exit0, все дочерние процессы завершены; VM возвращена к исходному сохранённому снимку |

В security regression проверены абсолютные Android auth/packet deadlines, подключение другого адреса при медленном клиенте, отказ неавторизованных AirPlay routes, запрет spoof lifecycle marker, некорректные длины запросов, ALLOW/DENY, неверные/устаревшие/истёкшие approval IDs, другой sender key и предел concurrent clients. В protocol suite проверены TLS1.2 rejection, неверный token, сверка сертификата синтетическим клиентом, heartbeat, настоящий H264 decode с отдельными SPS/PPS, смена разрешения, синтетический PCM, audio flags, stop, one-use session, oversize rejection и отсутствие dumps в runtime.

Доказательства, hashes точных компонентов/скриптов/ISO, команды, environment allowlist и лимиты: [isolated-security-validation.json](evidence/isolated-security-validation.json). Попытка lpac69 использовала неизменённые receivers из BETA-0.42. Windows UI EXE и код APK в этом прогоне не запускались. Синтетические media/ключи явно публичные; экран реального телефона не записывался.

Предыдущий незавершённый прогон остановился на вспомогательном PowerShell Get-NetTCPConnection внутри LPAC. Прямой запрос таблицы TCP из LPAC тоже оказался ограничен. Проверка PID сохранена: контроллер читает системную таблицу через GetExtendedTcpTable и пишет подтверждение в каталог, который тест может только читать. Dummy отдельно доказал запрет записи туда. Права продукта не расширялись, EXE/APK не пересобирались, настоящие security assertions не отключались.

## Проверки файлов и прежние подтверждения

Подписи APK и манифеста, SHA-256,100 frozen application/runtime files,57PE import graphs, архивные CRC/пути/известные признаки секретов, лицензии, lockfile integrity metadata и source snapshot проверены отдельно. Отрицательные metadata fixtures отвергают изменённый/неподписанный APK, изменённый manifest/signature и другой publisher key. Известные OSV advisories разобраны ранее для625версий; оставшиеся glib/proc-macro-error записи не входят в сохранённый Windows target tree. Это не исчерпывающий CVE-аудит нативных библиотек.

Прежние native24 с pixel check, AirPlay26, CTest/Rust/frontend/Edge проверки сохраняются как исторические результаты для тех же бинарных hashes. За новый изолированный прогон они не выдаются. Владелец отдельно подтвердил подключение, видео и звук на OPPO Reno5 Lite/Android13 и iPhone17/iOS27.

## Границы решения

- AirPlay предназначен для доверенной LAN. Первое имя приёмника не удостоверяет его подлинность; PIN/SRP в этой реализации отсутствует. Android QR certificate pinning имеет другую модель доверия.
- У Windows EXE нет Authenticode. Отдельная подпись manifest требует доверенного publisher fingerprint и не убирает предупреждение неизвестного издателя.
- Новые изолированные Tauri/WebView2 UI/pixel smoke, Android OS intent/permission revocation, отдельные физические rotation/stop/denial, общее fuzzing и активный LAN MITM этим этапом не выполнены.
- DRM/FLAG_SECURE и ограничения AudioPlaybackCapture не обходятся. Полную совместимость со всеми телефонами эти fixtures не доказывают.

По следующему поручению владельца комплект локально подготовлен к GitHub: source ZIP включает итоговые документы и проверочный скрипт, Windows ZIP получает актуальные инструкции при неизменности100application files. Финальная упаковка проверяет manifest/signature/source hashes. GitHub visibility и содержимое репозитория на этом этапе не менялись; публичная публикация требует отдельного решения владельца.
