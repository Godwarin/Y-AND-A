# Проверка загрузок Y AND A

Получайте готовые загрузки через Releases. Для Windows нужен полный ZIP с папкой `runtime`. Для Android нужен APK из того же выпуска. Архив исходников содержит код и лицензии.

Для 0.42c скачайте файл `Y-AND-A-0.42c-SHA256.txt` со страницы релиза. В PowerShell вычислите SHA-256 скачанного архива и сравните всю строку хеша с одноимённой записью в файле.

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath 'Y-AND-A-0.42c-win64.zip'
```

У Android APK есть подпись издателя. В 0.42c EXE без Authenticode. Суммы SHA-256 позволяют сверить загруженные файлы с опубликованными.

Для исторического 0.42a также доступна отдельная подпись манифеста. В PowerShell 7 запустите `scripts/verify-release-signature.ps1` с параметрами `-Manifest`, `-ExpectedPublisherFingerprint` и `-ExpectedArtifactVersion`. Ожидаемый отпечаток издателя получите из доверенного канала отдельно от загрузки.

[Состояние 0.42a](TEST_RESULTS.md) · [Проверка на Windows](DEVICE_TEST_0.42a.md)
