# Версии Y AND A

| Метка выпуска | Внутренняя версия | Состояние |
|---|---|---|
| BETA-0.42 | PC/APK0.4.0-rc.1, Android code400 | Владелец подтвердил Android/iPhone видео+звук; isolated security13/13 и protocol13/13 PASS, подготовка к GitHub |
|0.3.0-hotfix1|PC0.3.0/APK0.3.0|История: исправление native black viewer, прежний security NO-GO |
|0.3.0|0.3.0|История: первый Android companion, заменён hotfix |
|0.2.0|0.2.0|История: Android debugging path, больше не основной продукт |
|0.1.0|0.1.0|История: AirPlay |

Текущий beta комплект — release/BETA-0.42, готовые PC files в Windows. Исторические файлы сохранены локально в archive/releases и не входят в чистый GitHub snapshot. BETA label не требует пересборки успешно проверенных бинарников. Источником label/product соответствия служит config/release.json. Внутренний номер APK и его publisher certificate сохраняются для совместимого обновления.

Репозиторий Godwarin/Y-AND-A пока private. Изменение visibility и окончательное публичное security approval не выполнялись.

Для первого выпуска подготовлены tag BETA-0.42, target main, Draft=true и Pre-release=true. Это локальный план, tag/commit/release в GitHub пока не созданы. Описание: RELEASE_NOTES_BETA_0.42.md; инструкция новичку: GITHUB_FIRST_STEPS.md.
