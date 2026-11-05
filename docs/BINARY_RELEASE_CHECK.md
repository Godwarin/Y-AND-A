# Проверка загрузок BETA-0.42

Для Release предназначены Windows ZIP целиком,Android APK,source ZIP и4файла проверки:manifest,signature,SHA256 list,public key. Один EXE без runtime не является переносимым комплектом. Готовые assets в Git history не добавляются.

## Доказательства

- 100application/runtime files совпадают с owner-tested hashes в evidence/artifact-relocation.json; -FromTestedPackage не пересобирает код.
- APK v3,прежний RSA3072 cert SHA2562657a1dc1b3754231d3b6add16e51354f08bc8f0b26cd8137bac6d34fd0871c3. Backup/cleartext/debuggable выключены;6permissions без SMS/contacts/files.
- Source/Windows ZIP сверяются по каждому ожидаемому hash. Frozen runtime связывает исторические functional reports с бинарниками.57PE ASLR/NX,3own EXE CFG; imports/delay-imports не выявили missing CRT на проверенной Windows,это не clean-Windows runtime.
- Paths/case collisions/symlink/encryption/CRC и bounded known-secret scan проверяются без извлечения/исполнения. Negative fixtures отвергли altered APK/manifest/signature и иной publisher.
- Fresh isolated receiver13+13PASS: [итог](SECURITY_VALIDATION_BETA_0.42.md). Hardware reports и прежние UI/native tests отдельны.

## Финальная упаковка

prepare-github.py → verify-github-source.py → package.ps1 -FromTestedPackage → package-source.ps1 → sign-release.ps1 → verify-package.ps1/verify-release-signature.ps1 → check-release-readiness.ps1 -Scope BinaryReleaseCandidate. audit-release-light.py --output publish/github-final-metadata.json проверяет архивы/snapshot без изменения входов. Final scan/readiness/upload-plan receipts находятся вне snapshot:нет self-hash cycle.

BETA_SCOPED_REGRESSION_PASS в manifest означает только13+13scope для точных components/test hashes,не full certification/public approval. Fingerprint d6981a413e80a1df15ad984c34441413514abdfc794daa9a267b7ec04c78e060; private key в assets не включается. EXE без Authenticode,AirPlay для trusted LAN.

Прежние beta-0.42-* receipts со старыми ZIP hashes — история. Текущие hashes определяются финальным signed manifest и publish/upload-plan.json. Remote uploads/visibility не менялись; перед загрузкой повторить remote/head/asset checks.