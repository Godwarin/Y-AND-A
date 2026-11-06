# Сборка Y AND A из исходников

Для Windows 11 x64 понадобятся Visual Studio 2022 Build Tools с Desktop C++ и Windows SDK, Rust, закреплённый Node 24 и WebView2. Для Android понадобятся JDK 21, Android SDK и Build Tools. Используйте официальные дистрибутивы. Пакеты JavaScript и Rust закреплены в `package-lock.json` и `src-tauri/Cargo.lock`.

```powershell
./scripts/bootstrap-node.ps1
$nodeVersion = (Get-Content toolchain/node-version.txt -Raw).Trim()
$env:Path = (Resolve-Path "toolchain/node-$nodeVersion-win-x64").Path + ';' + $env:Path
npm.cmd ci
npm.cmd run check
npm.cmd run build
./scripts/build-airplay.ps1
./scripts/build-android-receiver.ps1
npm.cmd run package
```

Перед сборкой APK ознакомьтесь с условиями Android SDK. Следующие команды подготавливают SDK и APK без подписи издателя.

```powershell
./scripts/bootstrap-android.ps1 -AcceptSdkLicense
./scripts/build-android.ps1 -Unsigned
```

Для установки своей сборки подпишите APK собственным сертификатом. APK с другим сертификатом не обновляет установленное приложение издателя. Состав сторонних компонентов и лицензии перечислены в [уведомлениях](../THIRD_PARTY_NOTICES.md).
