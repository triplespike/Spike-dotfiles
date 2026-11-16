# Набор инструментов оптимизации хранилища и миграции данных

Комплексный производственный набор скриптов, паспортов и декларативных конфигураций NixOS для аудита системного NVMe (238 ГБ), безопасной очистки дискового пространства, переноса тяжелых данных на вторичные накопители и онлайн-расширения раздела `/dev/sda1` без размонтирования и потери данных.

---

## Структура каталога

| Файл | Описание | Права |
|---|---|---|
| [`01-system-storage-audit.md`](./01-system-storage-audit.md) | Полный паспорт дискового пространства NVMe (170 ГБ занято) с детализацией `/nix/store`, `~/.cache`, `~/projects`, `~/.ollama`, игр в `~/.local` и геометрией `/dev/sda1`. | Чтение |
| [`02-safe-cleanup.sh`](./02-safe-cleanup.sh) | Безопасная очистка локальных кэшей (Trash, Rust target/, pip, appimage, spotify, zen, npm) и безопасный Nix GC (User + System 179-180). | Исполняемый (`+x`) |
| [`03-migrate-ollama.sh`](./03-migrate-ollama.sh) | Миграция каталога моделей Ollama (19 ГБ) на `/mnt/ssd` с двухуровневой переадресацией (симлинк + `OLLAMA_MODELS` в systemd сервисе и обертке). Поддерживает `--rollback` и опрос готовности сокета. | Исполняемый (`+x`) |
| [`04-migrate-gaming.sh`](./04-migrate-gaming.sh) | Аудит библиотек Steam и миграция инстансов PrismLauncher (26 ГБ) на `/mnt/ssd`. Поддерживает чекпоинты Stable Diffusion (`--with-sd-models`), динамический расчет места, защиту от запущенного Minecraft и полный `--rollback`. | Исполняемый (`+x`) |
| [`05-online-resize-sda1.sh`](./05-online-resize-sda1.sh) | Верифицированное онлайн-расширение раздела `/dev/sda1` (+127.13 GiB) с 320 GiB до 447.13 GiB и онлайн-расширение ext4 без размонтирования `/mnt/ssd`. | Исполняемый (`+x`, sudo) |
| [`nixos-storage-optimization.nix`](./nixos-storage-optimization.nix) | Декларативный NixOS модуль: еженедельный `nix.gc`, автоматический `nix.optimise`, ограничение меню GRUB до 5 поколений (`boot.loader.grub.configurationLimit = 5`). | Чтение / Nix |

---

## Подробное описание скриптов и CLI-параметров

### 1. `02-safe-cleanup.sh` — Безопасная локальная очистка и Nix GC
Освобождает до ~24.1 ГБ без прав root (локальные кэши + пользовательский Nix GC) и дополнительно ~9.1 ГБ при системном GC.
- **Очищаемые кэши**: `~/.local/share/Trash`, `~/projects/spiketify/src-tauri/target`, `~/.cache/pip`, `~/.cache/appimage-run`, `~/.cache/spotify/Data`, `~/.cache/zen/*/cache2`, `~/.npm/_cacache`, битый чекпоинт SD, неиспользуемые gcroots сборок.
- **Гарантии сохранности**: Исходные коды проектов, конфигурации программ, учетные записи и вкладки браузера не затрагиваются. Поколения системы 181 (booted) и 182 (current) строго сохраняются; удаляются только устаревшие 179 и 180 с ядром zen.
- **Параметры командной строки**:
  - `-n, --dry-run` : Режим симуляции (анализирует размеры и показывает план без удаления).
  - `-y, --yes, --force` : Выполнить очистку без интерактивных запросов подтверждения.
  - `--with-system-gc` : Включить удаление старых поколений NixOS 179-180 (требует `sudo`).
  - `--skip-nix-gc` : Очистить только локальные кэши, пропустив `nix-collect-garbage`.
  - `-h, --help` : Показать справку и выйти. Неизвестные параметры возвращают код ошибки 1.

### 2. `03-migrate-ollama.sh` — Миграция моделей Ollama (19 ГБ)
Переносит каталог `~/.ollama` на `/mnt/ssd/ollama` и настраивает двухуровневую адресацию:
1. Символическая ссылка: `~/.ollama` -> `/mnt/ssd/ollama`.
2. Переменная окружения: `OLLAMA_MODELS=/mnt/ssd/ollama/models` (в `~/.config/systemd/user/ollama.service` и в обертке `~/.local/bin/ollama`).
- **Защита и отказоустойчивость**:
  - Перед переносом останавливает сервис `ollama.service`.
  - Проверяет, не выполнена ли уже миграция (не блокирует повторный вызов при малом остатке места).
  - После миграции ожидает готовности сокета API (цикл опроса до 10 секунд). При сбое запуска производит автоматический откат.
  - Поддерживает безопасный откат `--rollback`: восстанавливает оригинальный каталог из `~/.ollama.bak`, возвращает конфигурации сервиса и перезапускает демон.
- **Параметры командной строки**:
  - `-n, --dry-run` : Режим симуляции (проверяет статус сервиса и пути без записи).
  - `-y, --yes, --force` : Выполнить миграцию без запроса подтверждения.
  - `--rollback` : Откатить миграцию, восстановив `~/.ollama` из резервной копии.
  - `-h, --help` : Показать справку и выйти.

### 3. `04-migrate-gaming.sh` — Миграция игровых данных и аудит библиотек Steam
Проверяет библиотеки Steam и переносит инстансы PrismLauncher (26 ГБ), а также опционально модели Stable Diffusion (8.6 ГБ) на `/mnt/ssd`.
- **Аудит Steam**:
  - Подтверждает размещение библиотек игр на вторичных дисках (`/mnt/storage/SteamLibrary` ~388 ГБ и `/mnt/ssd/SteamLibrary` ~153 ГБ).
  - Каталог `~/.local/share/Steam` (8.2 ГБ) содержит рантаймы Proton (GE-Proton, Proton-CachyOS) и Steamworks redistributables, которые безопасно остаются на NVMe для высокой скорости запуска.
- **Защита целостности Minecraft**:
  - Обнаруживает не только GUI-процесс `prismlauncher`, но и активные экземпляры Java (`PrismLauncher/instances`, `net.minecraft`). Блокирует перенос при работающей игре для исключения повреждения сохранений миров.
- **Динамический расчет требуемого места**:
  - Не требует статичные 45 ГБ, если PrismLauncher уже мигрирован. Если переносятся только модели SD, проверяется только 10 ГБ.
- **Полный откат (`--rollback`)**:
  - Восстанавливает как PrismLauncher из `~/.local/share/PrismLauncher.bak`, так и чекпоинты Stable Diffusion из `Stable-diffusion.bak`.
- **Параметры командной строки**:
  - `-n, --dry-run` : Режим симуляции (проверяет доступное место и выводит план).
  - `-y, --yes, --force` : Применить миграцию без запросов подтверждения.
  - `--with-sd-models` : Включить перенос чекпоинтов Stable Diffusion WebUI Forge (8.6 ГБ).
  - `--rollback` : Откатить миграцию PrismLauncher и Stable Diffusion из резервных копий.
  - `-h, --help` : Показать справку и выйти.

### 4. `05-online-resize-sda1.sh` — Онлайн-расширение раздела /dev/sda1 (+127.13 GiB)
Расширяет раздел `/dev/sda1` с 320 GiB до полного физического объема накопителя 447.13 GiB и увеличивает ext4 на лету.
- **Гарантии безопасности**:
  - Начальный сектор 2048 (выравнивание по 1 МиБ) не изменяется — существующие 152.3 GiB данных не затрагиваются.
  - UUID раздела и UUID файловой системы сохраняются.
  - Процедура выполняется без размонтирования `/mnt/ssd`.
  - Проверяется счетчик ошибок ext4 (`/sys/fs/ext4/sda1/errors_count == 0`).
  - Использует корректные столбцы `lsblk -o NAME,SIZE,START,FSTYPE,MOUNTPOINT` для отчета о завершении.
- **Шаги выполнения**:
  1. `sgdisk -e /dev/sda` — перенос резервного заголовка GPT в конец диска.
  2. `growpart -v /dev/sda 1` — расширение границ раздела 1 в таблице GPT ядра.
  3. `resize2fs /dev/sda1` — онлайн-расширение файловой системы ext4.
  4. Контрольная верификация целостности и финальный отчет.
- **Параметры командной строки**:
  - `-n, --dry-run` : Режим симуляции (проверка геометрии GPT и ФС без изменений; не требует root).
  - `-y, --yes, --force` : Выполнить операцию без интерактивного подтверждения.
  - `-h, --help` : Показать справку и выйти.

---

## Рекомендуемый порядок выполнения

### Шаг 1. Ознакомление с паспортом дискового пространства
```bash
cat scripts/storage-optimization/01-system-storage-audit.md
```

### Шаг 2. Безопасная очистка кэшей и запуск User Nix GC (~24.1 ГБ)
Сначала симуляция:
```bash
./scripts/storage-optimization/02-safe-cleanup.sh --dry-run
```
Применение:
```bash
./scripts/storage-optimization/02-safe-cleanup.sh
```
*(Для очистки старых системных поколений 179-180 и высвобождения еще ~9.1 ГБ запустите: `./scripts/storage-optimization/02-safe-cleanup.sh --with-system-gc`)*

### Шаг 3. Онлайн-расширение вторичного SSD /dev/sda1 (+127.13 GiB)
Перед миграцией тяжелых моделей и игр расширяем емкость `/mnt/ssd` с 320 GiB до 447 GiB.
Сначала симуляция:
```bash
./scripts/storage-optimization/05-online-resize-sda1.sh --dry-run
```
Применение (требуется sudo):
```bash
sudo ./scripts/storage-optimization/05-online-resize-sda1.sh
```

### Шаг 4. Миграция моделей Ollama на /mnt/ssd (высвобождает 19.0 ГБ на NVMe)
Симуляция:
```bash
./scripts/storage-optimization/03-migrate-ollama.sh --dry-run
```
Применение:
```bash
./scripts/storage-optimization/03-migrate-ollama.sh
```

### Шаг 5. Миграция PrismLauncher и SD моделей на /mnt/ssd (высвобождает до 34.6 ГБ на NVMe)
Симуляция:
```bash
./scripts/storage-optimization/04-migrate-gaming.sh --dry-run --with-sd-models
```
Применение:
```bash
./scripts/storage-optimization/04-migrate-gaming.sh --with-sd-models
```

### Шаг 6. Декларативное закрепление в NixOS
Подключите модуль `nixos-storage-optimization.nix` в `/etc/nixos/configuration.nix`:
```nix
imports = [
  # ...
  /home/spike/Spike-dotfiles/scripts/storage-optimization/nixos-storage-optimization.nix
];
```
Примените конфигурацию:
```bash
sudo nixos-rebuild switch --flake /etc/nixos#default
```
Модуль обеспечит еженедельный `nix.gc`, автоматическую оптимизацию store и ограничение меню GRUB до 5 записей.
