# Изменения

## BETA-0.42 — исходники в GitHub, 5 ноября 2026

- По команде владельца загружены 308 чистых файлов в main закрытого Godwarin/Y-AND-A; remote blob hashes сверены полностью.
- Исходный commit 0fb8cbe50f3298b9ac3d5f55bd59876fc58db73a соответствует подготовленному source ZIP. Следующий docs commit фиксирует факт выгрузки.
- Ключи, backup, SDK, VM, runtime binaries и release assets в Git не включены; EXE/APK не менялись.
- Tag и Release с семью assets остаются следующим этапом: connector не поддерживает assets, браузерный инструмент остановлен из-за неопределённого URL. Visibility не менялась.

## BETA-0.42 — подготовка GitHub,5 ноября 2026

- Завершены isolated security13/13 и Android protocol13/13 на неизменённых receivers. Scope/ограничения и hardware reports разделены.
- Для LPAC исправлен тестовый PID lookup:trusted controller проверяет TCP owner/Job/executable,target читает защищённый proof. Assertions/ограничения не ослаблены.
- Подготовлены README,описание беты,GitHub инструкция новичку,contributing и русские issue/PR templates.
- Source ZIP включает итоговые docs/test script и pinned sources. Windows ZIP получает актуальные public docs/evidence. Manifest подписывается прежним key с точным scoped validation status.
- 100application files,APK cert и внутренние версии сохранены без пересборки. GitHub upload/visibility не менялись.
- Удалены1,89GiB regenerable caches; старые journals распределены по архиву. Keys/backup/SDK/VM/версии сохранены.

## BETA-0.42 — метка,4 ноября 2026

Owner-tested0.4.0-rc.1 обозначена BETA-0.42 без пересборки. История — archive/releases. Владелец подтвердил connect/video/audio на OPPO Reno5 Lite/Android13 и iPhone17/iOS27.

## Ранее

0.3.0/hotfix1:Android companion без отладки,QR/MediaProjection/AudioPlaybackCapture и исправление black viewer.0.2.0 debugging path — история,0.1.0 — AirPlay. Подробные записи сохраняются локально в docs/history.

## Удаление запускателя резервной копии из GitHub, 5 ноября 2026

По просьбе владельца файл «СОХРАНИТЬ КЛЮЧИ.cmd» удалён из текущего main и исключён из ROOT_FILES экспортера, чтобы не возвращаться при следующей подготовке. Личные ключи и резервные копии не затрагиваются. Продуктовый код, EXE и APK не меняются; независимый агент не запускался. Проверка этого этапа: remote tree — файл отсутствует, остальные файлы сохранены. Старые commits не переписываются. Локальные подготовленные архивы соответствуют прежнему snapshot: перед загрузкой Release обновить source ZIP без запускателя и переподписать manifest; текущие assets не загружать как обновлённые.
