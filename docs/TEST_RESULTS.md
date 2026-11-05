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

Исходники, release и visibility в GitHub не выгружались/не менялись. Перед записью заново проверить remote head и hashes. Исторические журналы сохраняются локально в docs/history.