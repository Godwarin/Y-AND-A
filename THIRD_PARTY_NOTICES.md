# Y AND A — компоненты и лицензии

Код Y AND A предоставляется под GPL-3.0-only, полный текст в LICENSE. Исходники доработанного GPL receiver сохраняются в vendor/airplay-windows; изменения — docs/airplay-yanda.patch.

| Компонент | Закреплённая версия | Источник | Лицензия |
|---|---|---|---|
| Tauri | Rust 2.12.5 / API и CLI 2.12.4 | https://github.com/tauri-apps/tauri | MIT / Apache-2.0 |
| React / React DOM | 19.3.1 | https://github.com/facebook/react | MIT |
| lucide-react | 1.66.0 | https://github.com/lucide-icons/lucide | ISC |
| ZXing core (Android offline scanner) | 3.5.4 | https://github.com/zxing/zxing | Apache-2.0 |
| qrcode / dijkstrajs (browser encoder) | 1.5.4 / 1.0.3 | https://github.com/soldair/node-qrcode | MIT |
| getrandom | 0.4.3 | https://github.com/rust-random/getrandom | MIT / Apache-2.0 |
| AirPlay-Windows | v0.4.1 / f739810e35887cf572b69275a52dc6f32323d65d + локальный patch | https://github.com/moieric11/AirPlay-Windows | GPL-3.0 |
| UxPlay/RPiPlay/playfair производные части | включены upstream receiver | см. vendor/airplay-windows/THIRD_PARTY_NOTICES.md | GPL-3.0 |
| FFmpeg обоих Windows receivers | 8.1.2#3, LGPL build без GPL codecs | официальный vcpkg overlay native/media-ports; provenance рядом | LGPL-2.1+ |
| OpenSSL обоих Windows receivers | 3.6.5#2 | vcpkg baseline afa249f12f52ed8a3b919f195495ba8b330288d1 | Apache-2.0 |
| SDL2 / SDL2_ttf AirPlay | 2.32.10 / 2.24.0 | тот же manifest | zlib |
| libplist AirPlay | 2.8.0 | тот же manifest | LGPL-2.1+ |
| ImGui и другие транзитивные зависимости receiver | pinned upstream CMake/manifest | vendor/airplay-windows | см. upstream notices и runtime/airplay-yanda/licenses |
| Оригинальная ASCII 42 | архив владельца от 2026-11-03 | vendor/42-animation-kit | предоставлена владельцем для проекта; 2026-11-04 владелец подтвердил собственное авторство и разрешение распространения в составе приложения |

BETA-0.42 (внутренняя версия0.4.0-rc.1) для подготовки внешнего распространения. Рядом с portable ZIP должен предоставляться source ZIP с собственным кодом, полным доработанным GPL receiver, проверенными исходными архивами нативных зависимостей, доступными Cargo source archives и production npm source packages. dependency-sources/SOURCE_INPUTS.json содержит hashes; изменения GPL receiver находятся в его полном source tree (исторический docs/airplay-yanda.patch описывает только прежний этап). Notices сохраняются. 2026-11-04 владелец подтвердил, что сам создал ресурс42 и разрешает его распространение с приложением; это подтверждение владельца, а не независимое заключение о правах. Это описание комплектности, не юридическое заключение. Наличие отдельного процесса не отменяет лицензионные обязанности.

Контрольные суммы конкретных release ZIP перечисляются в подписанном manifest рядом с выпуском. Проект не устанавливает драйверы, Bonjour и правила Firewall.


Android companion0.4.0-rc.1: native Java app, Android SDK/API36/build tools36.0.0, JDK21 (build only, not shipped). ZXing core3.5.4 SHA256: 71de5d89341b5fcf5dd89da7f44e84d825d0e084cdf3ec77c9abe26b0f0ceb13; ZXing Authors, Apache-2.0. Apache license and this notice are included in APK assets. Phone APK does not contain the Windows FFmpeg/OpenSSL libraries. Own sender/receiver code remains GPL-3.0-only.
