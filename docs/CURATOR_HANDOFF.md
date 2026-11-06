# Передача проекта Куратору

Обновлено 5 ноября 2026 года. По прямой команде владельца чистые исходники загружены в main закрытого репозитория Godwarin/Y-AND-A (id1444941523). Исходный snapshot: commit 0fb8cbe50f3298b9ac3d5f55bd59876fc58db73a, tree 5526bbe23b340e4cc78c44f57e48d2a871746c91. Все 308 remote blob hashes сверены с локальным snapshot, совпадение полное. Следующий отдельный docs commit фиксирует факт загрузки; source ZIP соответствует исходному commit. Visibility остаётся private. Tag, Release и assets пока не созданы.

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

GitHub connector поддерживает blobs/trees/commits, но не release asset upload. GitHub CLI не установлен. Браузерный этап остановлен CUA: адрес страницы Windows не удалось определить достаточно надёжно; продолжать UI ввод в этом turn нельзя. Playwright по умолчанию требует отсутствующий Chrome. Для Releases нужен доступный авторизованный web UI либо отдельно подготовленный CLI; credentials из connector не извлекать. Остаётся создать tag BETA-0.42 на исходном commit выше, Draft/Pre-release и приложить 7 подготовленных assets, сверить uploaded hashes. Public visibility/публикация — отдельное решение. Private vulnerability reporting сейчас включённым не объявлять.

Продуктовые tests/builds и VM в этом подготовительном этапе не запускать: app code не меняется. Подробные старые записи сохранены локально в history/pre-github-upload-2026-11-05; в source export они не входят. Очистка ранее удалила1,89GiB caches; keys/backup/SDK/VM/версии/regression evidence сохранены.

## Удаление запускателя резервной копии из GitHub, 5 ноября 2026

По просьбе владельца файл «СОХРАНИТЬ КЛЮЧИ.cmd» удалён из текущего main и исключён из ROOT_FILES экспортера, чтобы не возвращаться при следующей подготовке. Личные ключи и резервные копии не затрагиваются. Продуктовый код, EXE и APK не меняются; независимый агент не запускался. Проверка этого этапа: remote tree — файл отсутствует, остальные файлы сохранены. Старые commits не переписываются. Локальные подготовленные архивы соответствуют прежнему snapshot: перед загрузкой Release обновить source ZIP без запускателя и переподписать manifest; текущие assets не загружать как обновлённые.

## Независимый статический аудит, 5 ноября 2026

Независимая статическая проверка возобновлена после остановки координатора из-за лимита модели. Отчёт и решения по семи перепроверенным цепочкам находятся в локальном отчёте `docs/security-independent-2026-11-05/REPORT.md`. Полный прогон имеет статус incomplete. Первыми проверить границы FairPlay, выбор получателя Android и связь двух APK перед подписью. Не переносить выводы на новый EXE или APK без привязки к хэшам и проверки в изоляции.

## Исправления после независимого аудита, 5 ноября 2026

Меры по семи перепроверенным путям реализованы в рабочих исходниках. Доказательства, оставшиеся проверки и ограничения собраны в [записи об исправлениях](SECURITY_REMEDIATION_2026-11-05.md). Следующий этап — новый комплект, изолированная проверка и телефоны. BETA-0.42 заблокирована для публикации, старые доказательства действуют только для прежних байтов.

## Кандидат 0.42a для проверки на телефонах

Собран и сверен комплект `release/0.42a`. Внутренняя версия Windows 0.4.0-rc.2, Android versionName 0.42a и code 401. Сертификат APK сохранён. [Инструкция](DEVICE_TEST_0.42a.md), [SHA-256 и результаты сборки](evidence/0.42a-local-build.json).

6 ноября 2026 памяти хватило для восьми запусков офлайн-стенда. Сравнительная диагностика локализовала отказ в создании процесса с AppContainer. Обычный ограниченный токен создал приостановленный системный `cmd.exe`, а AppContainer и LPAC вернули код 2. Приёмники 0.42a в госте не запускались. Снимок восстановлен, состояние `NEEDS_VALIDATION`. Следующий шаг — короткая системная трассировка создания AppContainer в госте. После успешной регрессии и теста владельца подготовить чистый снимок исходников и подписанный комплект. Публикация 0.42a заблокирована. [План стенда](ISOLATED_STAND_PLAN.md), [результаты попыток](evidence/0.42a-isolated-validation.json).

Трассировка подготовлена. При пороге 5888 МиБ первый замер показал 5795 МиБ, после проверки владельцем доступно 4017 МиБ. Гость для трассировки ещё не запускался. В готовом APK статически проверены обработка внешних Intent, проверка отпечатка сертификата и TLS 1.3.

Владелец сообщил, что проверка 0.42a прошла успешно. Статус `OWNER_REPORTED_PASS` относится к общему результату. Для отдельных устройств сохраняется `UNVERIFIED_ON_DEVICE` до указания модели, ОС и сценария. [Отчёт владельца](evidence/0.42a-owner-validation.json).

Для закрытого GitHub используется отдельный каталог `publish/github-0.42a`. Команды `scripts/prepare-github.py --artifact-version 0.42a` и `scripts/verify-github-source.py --artifact-version 0.42a` формируют снимок и проверяют его локально. Следующий этап публикации бинарников требует отдельных доказательств и подписанного комплекта.

Снимок и локальный архив исходников 0.42a прошли проверку. В архив вошли 317 файлов снимка, 526 входов зависимостей и их манифест. Входы 0.42a содержат закреплённый ImGui. В `publish/upload-plan.json` связаны хэши снимка, архива и отчётов. [Команды упаковки и проверки](BUILD_FROM_SOURCE.md).

Файловая и реестровая трассировки AppContainer получены в госте. Запись профиля найдена в ветке тестового пользователя. При запуске три запроса к тому же идентификатору в другой ветке вернули `C0000034`. Изменение контекста запуска ещё требует проверки. Попытки при 4911 и 5347 МиБ прервались по лимиту памяти, снимок восстановлен. Сетевой статус остаётся `NEEDS_VALIDATION`. [Результаты и ограничения](TEST_RESULTS.md).

При запасе свыше 8 ГиБ проверен полноценный вход тестового пользователя. Пробный обычный AppContainer создан из этого сеанса в приостановленном состоянии. Подготовлен локальный контроллер запуска LPAC из того же сеанса с проверкой токена и сохранением контрольных проб перед запуском приёмников.

Контроллер создал дочерний AppContainer, но запрос признака LPAC не дал подтверждения. Вариант с проверкой фактических прав остановлен по тайм-ауту после входа гостя. Для следующей попытки добавлены отдельные отметки диска, хэшей, профиля, ACL и пробного запуска. Ограничение памяти при доступных свыше 8 ГиБ не сработало. Снимок восстановлен, сетевой статус `NEEDS_VALIDATION`.
