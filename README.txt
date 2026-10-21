XREAL Beam Windows ADB Tool
===========================

Публичная публикация: сначала прочитайте README.md, LICENSE.txt,
LICENSE-SCOPE.md и VALIDATION.md. Текущий авторский код — только для бесплатного
личного некоммерческого использования физическими лицами; прочие цели требуют
отдельного письменного разрешения. Сторонние компоненты имеют свои лицензии.
Пресеты экспериментальны; backup не полный, коды ошибок ADB/Fastboot
не везде проверяются, сброс удаляет данные. Ниже сохранена исходная инструкция.

Что это
-------
Это переносимый набор для Windows. Он использует `adb.exe` и `fastboot.exe`
из этой же папки, поэтому не требует установки ADB/Fastboot в PATH.

Скрипт умеет:
- делать backup текущего состояния устройства;
- отдельно выгружать `settings global/system/secure` в txt;
- применять пользовательские `.txt` файлы с ADB-командами;
- применять `beam-app`: отключение пакетов из `beam-app.sh`;
- применять `beam-settings`: настройки из `beam-settings.sh`;
- применять `extra_optim`: отдельный экономный/тихий пресет из `extra_optim.sh`;
- устанавливать APK-файлы из папки `app`;
- восстанавливать настройки и disabled-пакеты из backup;
- перезагружать устройство;
- делать factory reset через `adb reboot bootloader` и `fastboot erase`.

Как пользоваться
----------------
1. Подключи XREAL Beam по USB.
2. Включи USB debugging на устройстве.
3. Если Android спросит разрешение для компьютера, нажми `Allow` / `Разрешить`.
4. Если нужно установить приложения, положи `.apk` файлы в папку `app`.
5. Запусти `run.bat` двойным кликом.
6. Выбери нужный пункт меню.

Backup
------
Перед любым изменяющим действием скрипт автоматически делает backup.

Backup сохраняется в:

`backups\YYYYMMDD-HHMMSS`

В backup сохраняются:
- список ADB-устройств;
- `getprop`;
- `settings global`;
- `settings secure`;
- `settings system`;
- список всех пакетов;
- список отключённых пакетов;
- состояние батареи.

Важно: это не полный образ устройства и не backup пользовательских файлов.
Это backup состояния, которое нужно для отката изменений этих ADB-скриптов.

Меню
----
`1. Check device`

Проверяет, что устройство видно по ADB. Ничего не меняет.

`2. Backup only`

Создаёт backup вручную. Ничего не меняет.

`3. Export settings snapshot`

Сохраняет текущие настройки в папку:

`settings-snapshots\YYYYMMDD-HHMMSS`

Выгружаются файлы:

- `adb shell settings list global.txt`
- `adb shell settings list system.txt`
- `adb shell settings list secure.txt`
- `adb shell getprop.txt`
- `adb shell pm list packages -d.txt`

Это удобно, если нужно сравнить Beam до/после оптимизаций или выложить свежие
настройки на форум.

`4. Apply commands from txt`

Применяет команды из `.txt` файла, лежащего в папке `commands`.
Перед применением автоматически создаётся backup. Для запуска нужно выбрать
файл и ввести подтверждение `APPLY`.

Поддерживаются строки вида:

`adb shell settings put global window_animation_scale 0`

`settings put system screen_off_timeout 300000`

`pm disable-user --user 0 com.android.nfc`

`adb install -r app\example.apk`

Пустые строки и комментарии, начинающиеся с `#`, `;` или `//`, игнорируются.
Логи выполнения сохраняются в папку `command-logs`.

`5. Apply beam-app`

Применяет `beam-app.sh`: отключает список пакетов командой:

`adb shell pm disable-user --user 0 PACKAGE`

Это может отключать чувствительные системные компоненты. Если после применения
что-то работает неправильно, используй восстановление из backup или включай
нужные пакеты вручную.

`6. Apply beam-settings`

Применяет все настройки из `beam-settings.sh`.

Это более агрессивный профиль: RK3566/GPU/RAM/media/thermal/Wi-Fi/power,
отключение анимаций, ограничение фоновых процессов, очистка кэша.

`7. Apply extra_optim`

Применяет `extra_optim.sh`.

Это отдельный экономный/тихий пресет: balanced CPU/GPU, quiet thermal,
Wi-Fi power save, streaming-настройки, `background_process_limit=3`,
сенсоры в low-power. В конце скрипт спросит, делать ли reboot.

`8. Install APKs from app folder`

Устанавливает все `.apk` файлы из папки `app` командой:

`adb install -r -d FILE.apk`

`9. Full run`

Полный прогон:

`backup -> beam-app -> beam-settings -> install APKs`

`extra_optim` сюда намеренно не включён, потому что он конфликтует с частью
настроек `beam-settings`.

`10. Restore from backup`

Восстанавливает состояние из выбранной папки backup:
- приводит список disabled-пакетов к состоянию backup;
- записывает обратно `settings global`;
- записывает обратно `settings secure`;
- записывает обратно `settings system`.

Перед восстановлением скрипт делает ещё один backup текущего состояния.
Для подтверждения нужно ввести `RESTORE`.

Ограничение: восстановление не возвращает удалённые пользовательские файлы,
не восстанавливает данные приложений и не является полным системным образом.

`11. Reboot device`

Делает backup и перезагружает устройство через:

`adb reboot`

`12. Factory reset via fastboot`

Делает factory reset через ADB/Fastboot:

`adb reboot bootloader`

ждёт 5 секунд, затем:

`fastboot erase userdata`

`fastboot erase cache`

`fastboot reboot`

Перед этим скрипт делает backup ADB-readable состояния. Для подтверждения
нужно ввести `RESET`.

Внимание: этот пункт стирает userdata/cache. Будут удалены установленные
приложения, данные приложений, локальные файлы и настройки устройства.

`13. Status`

Показывает устройство, модель, build, количество disabled-пакетов и состояние
батареи.

`0. Exit`

Выход.

Ручной откат пакета
------------------
Если нужно вернуть отдельный пакет:

`adb shell pm enable --user 0 PACKAGE`

Пример:

`adb shell pm enable --user 0 com.android.keychain`

Конфликты пресетов
------------------
`beam-settings` и `extra_optim` частично конфликтуют.

Примеры:
- `beam-settings` ставит `wifi_power_save=0`;
- `extra_optim` ставит `wifi_power_save=1`;
- `beam-settings` ставит `background_process_limit=1`;
- `extra_optim` ставит `background_process_limit=3`.

Поэтому `extra_optim` лучше использовать как отдельный пресет, а не смешивать
с полным прогоном.
