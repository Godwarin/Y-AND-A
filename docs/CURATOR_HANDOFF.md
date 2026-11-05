# Передача проекта Куратору

Обновлено 5 ноября 2026 года. Текущий этап — локальная подготовка к выгрузке в GitHub. Remote upload/commit/tag/release и изменение visibility на этом этапе не выполняются. Godwarin/Y-AND-A (id1444941523) проверен через connector: private,size0,admin/push доступны. Перед записью перепроверить head/содержимое и не перезаписывать чужие изменения.

## Приложение и доказательства

BETA-0.42 содержит owner-tested бинарники0.4.0-rc.1.100application/runtime files сохраняются побайтно по evidence/artifact-relocation.json, APK code400 и cert прежние. Свежий lpac69: security13/13 + Android protocol13/13PASS, exit0, descendants terminated.7OS controls, private GUI/Python probes и read-only ownership proof проверены до продукта. Trusted parent проверяет TCP7000 PID по Job membership/exact executable. Scope/hashes/commands/allowlist/limits — evidence/isolated-security-validation.json и SECURITY_VALIDATION_BETA_0.42.md.

VM возвращена к baseline313d48f4-4026-4a99-8740-348809af3555, saved, reader stopped; host security не менялась. Прежние native24/AirPlay26/compile/frontend/Edge результаты исторические для тех же bytes. Владелец отдельно подтвердил подключение/видео/звук на OPPO Reno5 Lite/Android13 и iPhone17/iOS27; отдельные последние rotation/stop/denial не подтверждены. Fresh APK/UI/fuzz/MITM не заявлять. Scoped PASS не является полным независимым аудитом.

## Подготовленный состав

- publish/github: allowlisted исходники, инструкции, licenses/notices, evidence, русские issue/PR templates. Manifest/hygiene review находятся рядом вне snapshot. В Code отправлять только содержимое snapshot.
- release/BETA-0.42:7assets — Windows ZIP, APK, source ZIP, manifest,signature,SHA256 list,public key. В source ZIP дополнительно526pinned public dependency source inputs и их manifest. Ключей/backup/SDK/VM нет.
- RELEASE_NOTES_BETA_0.42.md: текст будущего Release; tag/title BETA-0.42,target main,Draft=true,Pre-release=true.
- GITHUB_FIRST_STEPS.md: инструкция новичку. README различает Code/Download ZIP и готовые Releases; SECURITY описывает private vulnerability reporting, которое включается при переходе в Public до анонса.
- publish/upload-plan.json: hashes/размеры/remote expectations/transport. publish/GITHUB_PREVIEW.md: локальная демонстрация фактического состава, не существующая GitHub-страница.

Windows ZIP переупаковывается с актуальными public docs/evidence;100application files не меняются. Source ZIP создаётся из текущего snapshot. Прежний DPAPI publisher key подписывает metadata. BETA_SCOPED_REGRESSION_PASS устанавливается только при совпадении components,13+13results,7controls,cleanup и hashes обоих test entrypoints; это не public approval. Fingerprint d6981a413e80a1df15ad984c34441413514abdfc794daa9a267b7ec04c78e060. Private keys не выводить/не выгружать.

## Проверки и следующий шаг

Порядок: prepare-github.py → verify-github-source.py → package.ps1 -FromTestedPackage → package-source.ps1 → sign-release.ps1 → verify-package.ps1/verify-release-signature.ps1 → check-release-readiness.ps1 -Scope BinaryReleaseCandidate → audit-release-light.py с output вне snapshot. Final packaging/scan receipts писать в publish, чтобы не создавать self-hash cycle. После упаковки не менять входящие source/evidence без повторной упаковки.

GitHub connector поддерживает blobs/trees/commits, но не release asset upload. GitHub CLI не установлен. Для Releases использовать авторизованный web UI либо отдельно подготовить CLI; credentials из connector не извлекать. После нового решения владельца: перепроверить repo/head/visibility и hashes, загрузить чистые source files в main, поставить tag на фактический commit, создать Draft/Pre-release и приложить7assets, сверить uploaded hashes. Public visibility/публикация — отдельное решение. Private vulnerability reporting сейчас включённым не объявлять.

Продуктовые tests/builds и VM в этом подготовительном этапе не запускать: app code не меняется. Подробные старые записи сохранены локально в history/pre-github-upload-2026-11-05; в source export они не входят. Очистка ранее удалила1,89GiB caches; keys/backup/SDK/VM/версии/regression evidence сохранены.