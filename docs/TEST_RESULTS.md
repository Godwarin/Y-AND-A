# Результаты BETA-0.42

Обновлено 5 ноября 2026 года. Бинарники сохраняют внутреннюю версию0.4.0-rc.1.

| Область | Результат |
|---|---|
| Свежая изолированная security regression |13/13PASS на frozen Android/AirPlay receivers,lpac69 |
| Свежий Android protocol |13/13PASS:TLS/H264/synthetic silent PCM,lpac69 |
| Изоляция до продукта |7OS controls,private USER32,Python parent/child/quota/timeout,read-only owner proof PASS |
| Cleanup |Exit0,descendants terminated,guest baseline rollback verified,VM saved |
| Телефоны владельца |OPPO Reno5 Lite/Android13,iPhone17/iOS27:connect/video/audio OWNER_REPORTED_PASS |
| Прежние проверки |Native24 с synthetic pixel check,AirPlay26,CTest6,Rust11/Clippy,Vitest3/Edge8,check/lint/build,APK parser24/QR4. Исторические результаты для тех же hashes |
| Файлы |100frozen hashes,APK v3/cert/permissions,manifest signature,archive CRC/paths,57PE imports,negative signature/APK checks PASS |
| Зависимости |OSV625 без query errors; оставшиеся glib/proc-macro-error entries вне Windows target. Не exhaustive native CVE audit |
| Предыдущий Defender |Release folder:exit0,no threats; hashes scanned комплекта в beta-0.42-defender-final.json. После переупаковки выполняется отдельная финальная проверка |

Точные scope/commands/allowlist/limits/hashes: [isolated evidence](evidence/isolated-security-validation.json). [Итог безопасности](SECURITY_VALIDATION_BETA_0.42.md) фиксирует ограничения. Fresh APK OS intent/permission revocation, отдельные phone rotation/stop/denial, fresh Tauri UI и общий fuzz/MITM не заявляются.

GitHub preparation выполняет metadata/file packaging без запуска product/tests/builds/VM на host. Windows ZIP обновляет docs при неизменности100application/runtime files. Source/signature/package/readiness и upload-plan связывают готовые assets с snapshot. Known-secret scan не доказывает отсутствие любого мыслимого секрета.

GitHub upload, 5 ноября: PASS — все 308 исходных файлов в commit 0fb8cbe50f3298b9ac3d5f55bd59876fc58db73a совпали по Git blob SHA; recursive tree не усечён, лишних/отсутствующих файлов нет. Main обновлён с expected_sha и без force. Visibility повторно подтверждена private. Source ZIP соответствует исходному commit; отдельный docs commit фиксирует результат. Release list пуст: EXE/APK/assets/tag пока не загружены. CUA прекратил UI этап из-за неопределённого адреса браузера; это ограничение инструмента, не ошибка продукта. Новые product tests/builds/VM не запускались. Исторические журналы сохраняются локально в docs/history.

## Удаление запускателя резервной копии из GitHub, 5 ноября 2026

По просьбе владельца файл «СОХРАНИТЬ КЛЮЧИ.cmd» удалён из текущего main и исключён из ROOT_FILES экспортера, чтобы не возвращаться при следующей подготовке. Личные ключи и резервные копии не затрагиваются. Продуктовый код, EXE и APK не меняются; независимый агент не запускался. Проверка этого этапа: remote tree — файл отсутствует, остальные файлы сохранены. Старые commits не переписываются. Локальные подготовленные архивы соответствуют прежнему snapshot: перед загрузкой Release обновить source ZIP без запускателя и переподписать manifest; текущие assets не загружать как обновлённые.
