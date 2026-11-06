# Проверка загрузок Y AND A

Получайте готовые загрузки через Releases. Для Windows нужен полный ZIP с папкой `runtime`. Для Android нужен APK из того же выпуска. Архив исходников содержит код и лицензии.

Проверяйте SHA-256 файлов и подпись манифеста по ожидаемым метке выпуска и отпечатку издателя. Отпечаток берите из доверенного канала отдельно от загрузки. В PowerShell 7 запустите `scripts/verify-release-signature.ps1` с параметрами `-Manifest`, `-ExpectedPublisherFingerprint` и `-ExpectedArtifactVersion`. EXE 0.42a не имеет Authenticode. Подпись манифеста удостоверяет архивы при проверке скриптом.

[Состояние 0.42a](TEST_RESULTS.md) · [Проверка на Windows](DEVICE_TEST_0.42a.md)
