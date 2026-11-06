# Сборка кандидата Y AND A 0.4.0-rc.1

Windows11 x64, Visual Studio2022 Build Tools C++/Windows SDK, Rust stable, CMake из Build Tools, JDK21. Локальный Node24.22.2 выбирается scripts/run-tool.mjs; при первичной подготовке скачайте официальный Node и проверьте SHASUMS. `package-lock.json` и `src-tauri/Cargo.lock` сохраняют зависимости. Для tests нужен Python environment из requirements-tests.txt и установленный Edge.

Source ZIP включает собственный код Android/Rust/React, полный изменённый GPL AirPlay receiver, официальный FFmpeg8.1.2#3 overlay с provenance, `.cargo/config.toml` с CFG flags, исходные архивы нативных зависимостей, доступные registry source archives Cargo и production npm packages в `dependency-sources/`. Их SHA256 находится в SOURCE_INPUTS.json; lockfiles дополнительно содержат upstream checksums. Исходники, лицензии и подписи архива публикуются рядом с бинарной версией. Это не заявление о byte-for-byte reproducibility всех PE/APK timestamps.

Публичная source-ветка не содержит приватных ключей автора. Для проверки Java/DEX/resources можно собрать unsigned APK:

```powershell
# Сначала самостоятельно прочитайте и примите Android SDK terms.
./scripts/bootstrap-android.ps1 -AcceptSdkLicense
./scripts/build-android.ps1 -Unsigned
```

Для установки своей изменённой APK подпишите её собственным сертификатом штатным apksigner. Такой сертификат не обновит APK автора без удаления/изменения package identity. Никогда не публикуйте чужие release signing keys. Обычный build-android.ps1 без -Unsigned предназначен для владельца: он использует сохранённый DPAPI credential и отказывается молча создавать замену ключа. Восстановление ключа автора выполняется локально по его закрытым инструкциям.

Основная сборка и проверки:

```powershell
npm ci
npm run check
npm run lint
npm test
npm run e2e
./scripts/build-airplay.ps1
./scripts/build-android-receiver.ps1
./.venv/Scripts/python.exe scripts/test-android-protocol.py
./.venv/Scripts/python.exe scripts/test-security-candidate.py
cargo test --release --manifest-path src-tauri/Cargo.toml
cargo clippy --release --manifest-path src-tauri/Cargo.toml --all-targets -- -D warnings
npm run package
```

build-airplay.ps1 использует официальный vcpkg commit `afa249f12f52ed8a3b919f195495ba8b330288d1`; FFmpeg8.1.2#3 находится в native/media-ports, git tree `c40aaa40e075d25ef1e812daa7333778890b6b0d`. Это сохраняет ABI8 вместо автоматического перехода на9. OpenSSL3.6.5, libplist2.8.0; SDK и временные каталоги сборки — собственные TEMP-пути, без глобальных установок драйверов/Firewall. Не запускайте vcpkg параллельно самому себе. Первый build может занять десятки минут. Source package уже содержит overlay; prepare-media-port.py только воспроизводит загрузку его20 upstream файлов с проверкой Git blob hashes.

Для проверки системного разрешения и настоящего phone capture необходим физический телефон. Программные fixtures не заменяют аппаратную проверку. Нативный smoke использует отдельный WebView2 profile и тестовый debug port только своего процесса; production EXE debug port не включает.

Упаковка владельцем после проверки APK:

```powershell
./scripts/package.ps1 -SkipArchive
./toolchain/node-v24.22.2-win-x64/node.exe scripts/smoke-desktop.mjs 'release/BETA-0.42/Windows/Y AND A.exe' --airplay
./.venv/Scripts/python.exe scripts/collect-source-inputs.py
./scripts/package.ps1
python scripts/prepare-github.py
./scripts/package-source.ps1
./scripts/verify-package.ps1
./scripts/sign-release.ps1
```

Не распространяйте build, .local, credential/backup files или caches. Оригинальная анимация42 сохранена без изменения геометрии; история и полное ТЗ находятся в архиве. Для внешних разработчиков актуальная архитектура и ограничения — ARCHITECTURE.md и SECURITY_RELEASE_REVIEW.md; предыдущее security NO-GO относится к0.3.0-hotfix1.

## Структура BETA-0.42

config/release.json и scripts/release-layout.ps1 задают имя выпуска отдельно от product version. scripts/build-android.ps1 сохраняет APK в build/android, package.ps1 кладёт его внутрь release/BETA-0.42/Windows под исходным versioned именем и рядом как Y-AND-A-BETA-0.42-android.apk. Параметр -ArtifactVersion BETA-0.42 поддерживается package/package-source/verify-package. Подпись manifest создаётся в этой же папке. Исходники оригинальной42 находятся в vendor/42-animation-kit и public/animation. Локальный входной original.zip сохраняется у владельца, в чистый GitHub snapshot не включается. Устаревший ADB путь сохранён только в локальном archive и не нужен для сборки. Apache текст находится в licenses/Apache-2.0.txt.

В source checkout нет готовых Windows DLL, SDK/JDK, node_modules или signing secrets. Сначала подготовьте официальные tools и pinned dependencies по инструкции выше; read-only source snapshot не обещает offline build без отдельного dependency-sources комплекта. Для security аудита скачивание/install dependencies из target scripts запрещено: стенд заранее получает только уже доступные локальные tools через read-only ISO.

Замороженная BETA-0.42 предшествует [исправлениям безопасности](SECURITY_REMEDIATION_2026-11-05.md). Для публикации нужны новый комплект и новые результаты по его хэшам. Штатные скрипты блокируют повторную подпись и готовность прежней метки.

ImGui закреплён полным commit и списком SHA-256. Сборка использует `build/airplay/_deps/imgui-pinned-src`, проверяя его до компиляции. Для архива исходников используйте `scripts/collect-source-inputs.py` после подготовки закреплённых файлов и архивов. `package-source.ps1` повторно проверяет хэши ImGui и native архивов при упаковке. Если изменился утверждённый состав Windows ZIP, обновите `config/windows-package-files.json` по результатам проверки нового состава.

Для 0.42a доступны отдельные входы архива. Режим ниже использует локальный кэш и закреплённый набор ImGui из каталога сборки. В кэше Cargo проверяются доступные архивы из `Cargo.lock`.

```powershell
python -B scripts/collect-source-inputs.py --artifact-version 0.42a
python -B scripts/prepare-github.py --artifact-version 0.42a
python -B scripts/verify-github-source.py --artifact-version 0.42a
./scripts/package-source.ps1 -ArtifactVersion 0.42a
./scripts/verify-package.ps1 -ArtifactVersion 0.42a -SourceOnly
```

Проверка `-SourceOnly` сверяет архив исходников с его манифестами. Проверка Windows ZIP, native smoke и сетевые тесты входят в отдельный этап.

Для нового комплекта после упаковки и регрессионных проверок обновите записи о результатах по его хэшам, затем выполните `sign-release.ps1`, `verify-package.ps1` и `check-release-readiness.ps1 -Scope BinaryReleaseCandidate`. Подпись требует совпадения отдельного APK, вложенного APK и результата его проверки.
