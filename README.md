# Y AND A — BETA-0.42

Экран и звук Android/iPhone на Windows11 x64 в доверенной локальной сети. На Android используется собственное приложение: отладка и режим разработчика не нужны. На iPhone — AirPlay с подтверждением подключения на ПК.

## Скачать и начать

Готовые сборки размещаются в [Releases](https://github.com/Godwarin/Y-AND-A/releases), когда выпуск опубликован. Для Windows нужен **win64.zip целиком**, для Android — **android.apk** из того же выпуска. Кнопка GitHub **Code → Download ZIP** скачивает исходники для разработки.

[Подключение телефона](docs/USER_GUIDE.md) · [Что такое GitHub и Releases](docs/GITHUB_FIRST_STEPS.md) · [Описание BETA-0.42](docs/RELEASE_NOTES_BETA_0.42.md)

## Статус беты

BETA-0.42 — название успешно проверенных владельцем компонентов0.4.0-rc.1. На OPPO Reno5 Lite/Android13 и iPhone17/iOS27 подтверждены подключение, видео и звук. Это пользовательское подтверждение, не лабораторный тест агента. Изолированные regression tests защит13/13 и Android protocol13/13 прошли; [объём и ограничения](docs/SECURITY_VALIDATION_BETA_0.42.md) зафиксированы отдельно. Решение о публикации принимает автор.

## Запуск готовой сборки

Windows: распакуйте весь win64.zip и запустите Y AND A.exe внутри Windows. Папка runtime должна оставаться рядом. Права администратора не нужны.
Android10+: установите APK из того же выпуска, создайте QR на ПК, отсканируйте и разрешите показ экрана в системном диалоге. Для звука приложений требуется разрешение на запись аудио; микрофонный источник не используется.
iPhone: включите AirPlay в Y AND A → Пункт управления → Повтор экрана → Y AND A → разрешите свой телефон на ПК, сверив IP с настройками Wi-Fi iPhone.

Готовые файлы публикуются отдельным выпуском после проверки; наличие исходников само по себе не означает, что бинарный релиз уже загружен. Локальный комплект владельца находится в release/BETA-0.42. История версий — [docs/RELEASES.md](docs/RELEASES.md).

## Ограничения и данные

Используйте собственную доверенную сеть, не открывайте порты программы в интернет. AirPlay не удостоверяет первый выбранный по имени приёмник. DRM/FLAG_SECURE и запреты записи звука соблюдаются. Экран/звук не записываются приложением на диск, телеметрия отсутствует в собственном коде.

EXE пока без Authenticode. Отдельная ECDSA подпись манифеста не убирает предупреждение неизвестного издателя. Проверяйте SHA256 и источник загрузки; антивирус и SmartScreen не отключайте.

[Инструкция](docs/USER_GUIDE.md) · [Приватность](docs/PRIVACY.md) · [Проверка безопасности](docs/SECURITY_RELEASE_REVIEW.md) · [Проверка готовых загрузок](docs/BINARY_RELEASE_CHECK.md) · [Сообщения о безопасности](SECURITY.md)

[Как предложить исправление](CONTRIBUTING.md).

## Разработка

Tauri2 + React/TypeScript + Rust; Windows native C++ FFmpeg/SDL viewer; Android Java MediaProjection/AudioPlaybackCapture. Полные исходники изменённого GPL AirPlay receiver сохранены в vendor/airplay-windows. Сборка описана в [docs/BUILD_FROM_SOURCE.md](docs/BUILD_FROM_SOURCE.md); код под GPL-3.0-only, сторонние лицензии — [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

config/release.json разделяет distribution label BETA-0.42 и внутренний product version0.4.0-rc.1. Не пересобирать проверенные EXE/APK только ради номера. Ключи автора не входят в репозиторий; собственную изменённую APK подписывают собственным сертификатом.

Служебные каталоги archive,build,downloads,node_modules,dist,runtime,toolchain binaries,.venv,.local,publish и release binaries не входят в чистый source snapshot. Замороженные source archives зависимостей предоставляются отдельно с исходным release ZIP. Текущий handoff: [docs/CURATOR_HANDOFF.md](docs/CURATOR_HANDOFF.md).
