# График смен

- `web/index.html` — приложение (одна страница). Эта же версия опубликована на claude.ai и содержит личный список на октябрь между метками `@personal-start` и `@personal-end`.
- `tools/build.py` — собирает публичные файлы в `dist/`: страницу без личных данных, архив для itch.io, `version.json` и страницу внутри APK.
- `android/` — приложение Android: оболочка WebView, которая сама скачивает обновления.
- `ShiftPlanner/` — ранняя версия на SwiftUI, не обновлялась.

## Выпуск обновления

1. В `web/index.html` увеличьте `WEB_BUILD` на 1 и при желании поменяйте `APP_VERSION`. Кратко опишите изменения в `tools/notes.txt`.
2. Если менялся код Android, увеличьте `versionCode` (и `versionName`) в `android/version.properties`.
3. Соберите:
   ```
   python3 tools/build.py
   cd android && ANDROID_HOME=<путь к SDK> ./gradlew assembleRelease
   cp app/build/outputs/apk/release/app-release.apk ../dist/grafik-smen.apk
   ```
4. Скопируйте в открытый репозиторий `0WahTanG0/grafik-smen`: `dist/web/index.html` → `index.html`, `dist/version.json`, `dist/grafik-smen.apk`, архив для itch.io. Приложения подхватят обновление при следующем запуске.
5. На itch.io загрузите новый архив вместо старого в том же проекте. Сохранённые данные не теряются: страница хранит их под постоянным ключом `grafik-smen:data`.

## Ключ подписи

APK подписан ключом из `android/keystore/` (`release.jks` и `keystore.properties`). В git ключ не хранится. Без него новый APK нельзя установить поверх старого, поэтому храните копию ключа отдельно. Обновления страницы (`index.html`) ключ не требуют.
