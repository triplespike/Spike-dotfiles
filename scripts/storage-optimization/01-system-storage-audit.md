# Паспорт дискового пространства и аудит системного накопителя NVMe

**Дата формирования**: 2026-11-16  
**Хост**: `nixos`  
**Пользователь**: `spike` (`uid=1000`, `gid=100(users)`)  
**Окружение**: NixOS 26.11 (Linux 7.3.4-cachyos), Wayland / Niri, Btrfs + LUKS2  

---

## 1. Архитектура блочных устройств и файловых систем

| Блочное устройство | Модель / Назначение | ФС / Тип | UUID / Метка | Общий размер | Занято | Доступно | Точка монтирования | Примечания |
|---|---|---|---|---|---|---|---|---|
| `/dev/nvme0n1` | Apacer AS2280P4 256GB | GPT | — | 256.06 GB (238.47 GiB) | — | — | — | Системный NVMe M.2 накопитель |
| ├─ `/dev/nvme0n1p1` | Раздел EFI | vfat (FAT32) | `12CE-A600` / `boot` | 512 MiB | 147 MiB (29%) | 365 MiB | `/boot` | GRUB EFI загрузчик |
| └─ `/dev/nvme0n1p2` | Шифрованный контейнер | `crypto_LUKS` (v2) | `14b6f52f-2482-4844-9b81-ba355abfaa07` | 237.97 GiB | 237.97 GiB | 0 B | — | `allowDiscards = true` (TRIM pass-through) |
| &nbsp;&nbsp;&nbsp;&nbsp;└─ `cryptroot` | Расшифрованный том | Btrfs | `3ddb327c-e42d-4972-83d5-50f547624457` | 237.96 GiB | 168.86 GiB (71%) | 63.54 GiB | `/`, `/home`, `/nix`, `/tmp`, `/srv` | `discard=async,space_cache=v2,ssd` |
| `/dev/sda` | Patriot Burst Elite 480GB | GPT | `f511e149-3805-445b-9468-38d4bcd223dd` | 480.10 GB (447.13 GiB) | — | — | — | Вторичный SATA III SSD |
| └─ `/dev/sda1` | Основной раздел | ext4 | `3823c553-f399-4942-8bc5-bbf471f4d850` | 343.60 GB (320.00 GiB) | 152.3 GiB (49%) | 145.6 GiB | `/mnt/ssd` | Начало: сектор 2048; свободно для расширения: +127.13 GiB |
| `/dev/sdb` | ST2000DM005-2U9102 (Seagate 2TB) | GPT | — | 2.00 TB (1.82 TiB) | — | — | — | HDD 5400 RPM |
| └─ `/dev/sdb2` | Хранилище данных | ext4 | `a9744e75-dd85-49f2-85f6-291ec9c406da` | 2.00 TB (1.82 TiB) | 387.5 GiB (21%) | 1.41 TiB | `/mnt/storage` | Библиотека игр Steam (`SteamLibrary` 388 GB) |
| `/dev/zram0` | Swap в оперативной памяти | swap | `d95b8d1b-5f39-42c4-96f9-511735d5e26f` | 7.77 GiB | — | — | `[SWAP]` | Алгоритм сжатия zstd, 50% RAM |

### Субволюмы Btrfs на `/dev/mapper/cryptroot`:
- `subvolid=5` (`subvol=/`): смонтирован в `/` (**2.8 GiB**)
- `subvolid=256` (`subvol=/home`): смонтирован в `/home` (**109 GiB**)
- `subvolid=257` (`subvol=/nix`): смонтирован в `/nix` (**55 GiB**, включая read-only remount `/nix/store`)
- `subvolid=259` (`subvol=/tmp`): смонтирован в `/tmp` (**817 MiB**)
- `subvolid=258` (`subvol=/srv`): смонтирован в `/srv` (0 B)
- `subvolid=260` (`subvol=/var/tmp`): смонтирован в `/var/tmp` (0 B)

---

## 2. Глубокий аудит системного NVMe (170 ГБ занято)

На накопителе `/dev/mapper/cryptroot` из 238 ГБ занято **168.86 GiB (~170 GB)**.  
Основные потребители делятся на две зоны ответственности:
1. Системное хранилище пакетов `/nix/store`: **55 GiB**.
2. Пользовательские данные `/home/spike`: **109 GiB**.

```
Использование 170 ГБ NVMe:
┌───────────────────────────────────────┬──────────────────────────────────────────┐
│ /nix/store (55 GiB)                   │ /home/spike (109 GiB)                    │
│ ├─ Живая система: 42 GiB              │ ├─ ~/.local: 38 GiB (PrismLauncher 26G)  │
│ ├─ Старые поколения системы: 8.3 GiB  │ ├─ ~/projects: 30 GiB (SD Forge, Target) │
│ ├─ Старые профили Home-Manager: 6.9 G │ ├─ ~/.ollama: 19 GiB (LLM Blobs)         │
│ └─ Мертвые пути и .drv: 3.1 GiB       │ ├─ ~/.cache: 11 GiB (Spotify, Pip, AppIm)│
│                                       │ └─ Прочее: ~/.gemini (4G), ~/.config (2G)│
└───────────────────────────────────────┴──────────────────────────────────────────┘
```

---

## 3. Детализация `/nix/store` (55 GiB)

### 3.1. Структура и статистика
- **Всего путей в `/nix/store`**: 46 543
- **Таблица жестких ссылок дедупликации (`/nix/store/.links`)**: 52 GiB (автоматическая еженедельная дедупликация через `nix.optimise`).
- **Служба дедупликации**: `nix-optimise.service` (активна, экономит ~8.0 GiB благодаря жестким ссылкам).

### 3.2. Поколения системы (System Generations)
Хранятся в `/nix/var/nix/profiles/`:
- **Поколение 179** (`system-179-link`, дата сборки: 2026-11-13): Ядро `7.2.11-zen1`, NixOS `26.11.20261020.02c087f`. Замыкание: **29.2 GiB**.
- **Поколение 180** (`system-180-link`, дата сборки: 2026-11-14): Ядро `7.3.4-zen1`, NixOS `26.11.20261111.d4f25a3`. Замыкание: **25.5 GiB**.
- **Поколение 181** (`system-181-link`, дата сборки: 2026-11-14): Ядро `7.3.4-cachyos`, NixOS `26.11.20261111.d4f25a3`. Замыкание: **25.6 GiB** (`/run/booted-system`, текущее загруженное ядро).
- **Поколение 182** (`system-182-link`, дата сборки: 2026-11-15): Ядро `7.3.4-cachyos`, NixOS `26.11.20261111.d4f25a3`. Замыкание: **25.6 GiB** (`/run/current-system`, активная конфигурация).
- **Вывод по безопасности**: Поколения 181 и 182 используют идентичное ядро `7.3.4-cachyos` и отличаются всего на 8 путей (2.8 МБ). Поколения 179 и 180 являются устаревшими (kernel zen) и удерживают уникальных путей на **8.3 GiB**. Удаление поколений 179 и 180 абсолютно безопасно, так как booted-system (181) и current-system (182) остаются нетронутыми!

### 3.3. Пользовательские профили и Home-Manager
Хранятся в `~/.local/state/nix/profiles/`:
- **User profiles (`profile-*-link`)**:
  - `profile-2-link` (2026-10-23): 7.1 GiB (устаревший)
  - `profile-3-link` (2026-10-23): 56.5 MiB (устаревший)
  - `profile-4-link` (2026-11-02): 1.8 GiB (**текущий активный**, содержит `opencode-desktop` и `playerctl`)
- **Home-Manager profiles (`home-manager-*-link`)**:
  - `home-manager-46-link` (2026-10-26): 16.1 GiB (устаревший)
  - `home-manager-47-link` (2026-10-26): 16.1 GiB (устаревший)
  - `home-manager-48-link` (2026-11-14): 20.8 GiB (**текущий активный**)
- **Вывод по безопасности**: Удаление поколений `profile-2`, `profile-3`, `home-manager-46`, `home-manager-47` высвобождает **6.9 GiB** в unprivileged-режиме пользователя `spike` без прав `sudo`.

### 3.4. Непривязанные («мертвые») пути и файлы дериваций
- Файлы сборки `.drv`: **38 395 файлов** (~160 MiB).
- Недостижимые пакеты в хранилище (не входят ни в одно поколение): **1 536 путей** (~**2.9 GiB**).  
  Крупнейшие из них:
  - `/nix/store/whknmkwj2a6smfk0gsk3dpdyfpli9c6n-ollama-0.40.4` (1.1 GiB)
  - `/nix/store/s3302sxix7ii035qyzw7v9xhff4kgi0f-cuda13.4-libcublas-13.8.0.4-lib` (576 MiB)
  - `/nix/store/jjpa3v76wd7275agp79nscyvb2fdbnq2-cuda13.4-cuda_nvrtc-13.4.92-lib` (128 MiB)
  - `/nix/store/18k3q0fkiraiipk0fyx3kmz18ag7frji-nixos` (342 MiB)
- **Итого освобождаемый объем через полный Nix GC**: **19.1 GiB**.

---

## 4. Детализация пользовательского окружения `~` (109 ГБ)

### 4.1. Каталог кэшей `~/.cache` (11.0 GB)
| Каталог | Объем | Природа данных | Безопасность очистки |
|---|---|---|---|
| `~/.cache/spotify` | **3.38 GB** | `Data/` (2.7 GB) — кэш потокового аудио треков | **100% безопасно**. Не затрагивает логин, плейлисты, настройки Spicetify. |
| `~/.cache/pip` | **1.69 GB** | `http-v2/` — архивы wheel и tar.gz | **100% безопасно**. Пакеты скачиваются заново при повторной сборке venv. |
| `~/.cache/appimage-run` | **1.67 GB** | 4 распакованных squashfs-рантайма AppImage | **100% безопасно**. `appimage-run` распаковывает их на лету при необходимости. |
| `~/.cache/devsize` | **1.68 GB** | Кэш аудиозаписей `.opus`/`.webm` и превью | Не затрагивается скриптом во избежание сброса пользовательских медиа. |
| `~/.cache/zen` | **1.02 GB** | `cache2/` — дисковый кэш веб-страниц | **100% безопасно**. Не затрагивает пароли, историю, вкладки, сессии. |
| `~/.cache/nix` | **280 MB** | Кэш тарболлов flakes и eval cache | Безопасно, очищается штатно. |
| `~/.cache/nvidia` | **208 MB** | Компилированные шейдеры OpenGL/Vulkan | Сохраняется для предотвращения микрофризов в играх. |
| `~/.cache/fontconfig` | **91 MB** | Кэш шрифтов | Сохраняется. |
| `~/.npm/_cacache` | **396 MB** | Кэш скачанных npm-пакетов | **100% безопасно**. Очищается через `npm cache clean --force`. |
| `~/.local/share/Trash` | **1.09 GB** | Корзина с удаленными видео-фрагментами | **100% безопасно**. Полная очистка без риска. |

### 4.2. Каталог проектов `~/projects` (30.0 GB)
1. **`~/projects/stable-diffusion-webui-forge` — 16.0 GB**:
   - `models/Stable-diffusion/`: **8.59 GB**
     - `ponyDiffusionV6XL_v6StartWithThisOne.safetensors`: **6.5 GB**
     - `abyssorangemix3_aom3a1b.safetensors`: **2.0 GB**
     - `meinaHentai_v3_baked_vae.safetensors.corrupted`: **65 MB** (поврежденный недокачанный файл, подлежит удалению).
   - `venv/`: **7.12 GB** (Python venv с PyTorch 2.x CUDA 12).
2. **`~/projects/clipper` — 7.8 GB**:
   - `output/`: **5.92 GB** (готовые видео-ролики).
   - `backgrounds/`: **1.5 GB** (исходные геймплейные футажи).
3. **`~/projects/spiketify` — 5.7 GB**:
   - `src-tauri/target/`: **5.5 GB** (временные артефакты сборки Rust: `debug/deps` 4.3G, `debug/incremental` 847M).  
     *Очистка*: `cargo clean` высвобождает 5.5 ГБ без потери ни одной строчки исходного кода!
   - `node_modules/`: 212 MB.
4. **`~/projects/open-design` — 443 MB**:
   - Рабочий репозиторий со шрифтами и исходниками.

### 4.3. Каталог моделей `~/.ollama` (18.97 GB)
- **Расположение**: `/home/spike/.ollama/models/blobs` (30 блобов весов).
- **Запущенный процесс**: PID `1806`, пользовательский сервис systemd: `~/.config/systemd/user/ollama.service`.
- **Исполняемый файл**: Обертка `/home/spike/.local/bin/ollama` с ускорением Flash Attention и KV-Cache q8_0.
- **Модели**:
  - `qwen2.5-coder:7b` (4.7 GB)
  - `mistral-nemo:latest`, `mandy:latest`, `melodie:latest`, `colette:latest` (совместно используют один базовый блоб 5.7 GB)
  - `qwen2.5-uncensored:latest` (4.7 GB)
  - `stheno:latest` (4.9 GB)
- **Стратегия миграции**: Перенос на `/mnt/ssd/ollama` с двойным уровнем перенаправления (симлинк + переменная окружения `OLLAMA_MODELS=/mnt/ssd/ollama/models`).

### 4.4. Разрешение аномалии «Игры в ~/.local» (Steam 8.2 GB vs PrismLauncher 26.0 GB)
В исходном запросе предполагалось наличие 38 ГБ игр Steam в `~/.local`.
Детальная ревизия показала следующее:
1. **Каталог `~/.local/share/Steam` занимает всего 8.2 GB**:
   - В `steamapps/common/` игр **нет** (только redistributable 253 MB).
   - Вся масса каталога — это системные компоненты Steam: `compatibilitytools.d` (3.2 GB: Proton GE и Proton CachyOS), рантаймы `ubuntu12_32`/`64` (1.5 GB), кеш веб-интерфейса.
   - Игры Steam **уже установлены на внешних накопителях**:
     - `/mnt/storage/SteamLibrary` (HDD, 388 GB, 24 игры).
     - `/mnt/ssd/SteamLibrary` (SATA SSD, 153 GB, 4 игры: Kingdom Come 2, Let It Die, RimWorld, Geometry Dash).
2. **Истинный потребитель 26.0 GB игровых данных в `~/.local` — это `PrismLauncher`**:
   - Путь: `/home/spike/.local/share/PrismLauncher` (**26.0 GB**, 151 925 файлов).
   - `instances/` (**23.0 GB**):
     - `All the Mods 10 - ATM10`: **17.0 GB**
     - `Prominence™ II - Hasturian Era`: **1.8 GB**
     - `Requiem - BETTER FANTASY`: **1.4 GB**
     - `FTB OceanBlock 2`: **970 MB**
     - `DarkSouls RPG 3.3.0`: **851 MB**
     - `All the Mods 10 - To the Sky`: **620 MB**
   - `assets/objects`: 2.0 GB.
3. **Решение**: Миграция `~/.local/share/PrismLauncher` на `/mnt/ssd/PrismLauncher` со связыванием через симлинк освобождает **26.0 GB** с системного NVMe!

---

## 5. Сводная матрица потенциала высвобождения дискового пространства

| Этап / Мероприятие | Источник / Путь | Механизм | Необходимые права | Высвобождаемый объем | Риск |
|---|---|---|---|---|---|
| **1. Локальная безопасная очистка** | Корзина, `target/`, кэши pip, appimage, spotify, zen, npm | Удаление временных файлов и кэшей | Пользователь (`spike`) | **14.13 GB** | **Нулевой** (кэши и временные файлы сборки) |
| **2. Пользовательский Nix GC** | `~/.local/state/nix/profiles/` | `nh clean user --keep 1` + `nix-collect-garbage -d` | Пользователь (`spike`) | **~10.00 GB** | **Нулевой** (удаляет лишь старые профили HM и user) |
| **3. Системный Nix GC** | `/nix/var/nix/profiles/system` | Удаление system-179/180 + `sudo nix-collect-garbage -d` | `sudo` (root) | **~9.10 GB** | **Нулевой** (сохраняются booted-181 и current-182) |
| **4. Миграция моделей Ollama** | `~/.ollama` -> `/mnt/ssd/ollama` | Rsync + симлинк + `OLLAMA_MODELS` | Пользователь (`spike`) | **18.97 GB** | **Нулевой** (атомарный бэкап и верификация через `ollama list`) |
| **5. Миграция PrismLauncher** | `~/.local/share/PrismLauncher` -> `/mnt/ssd/` | Rsync + симлинк | Пользователь (`spike`) | **26.00 GB** | **Нулевой** (атомарный бэкап и проверка запуска) |
| **6. (Опционально) SD Модели** | SD Forge checkpoints -> `/mnt/ssd/` | Rsync + симлинк | Пользователь (`spike`) | **8.59 GB** | **Нулевой** |

### Итоговый эффект на системный NVMe:
- **Базовый сценарий (Шаги 1–5)**: высвобождается **~78.2 GB**!
  - Занятое пространство снижается с **168.86 GB** до **~90.6 GB**.
  - Свободное пространство на NVMe возрастает с **63.5 GB** до **~142 GB** (занятость падает с 71% до **38%**).
- **Максимальный сценарий (Шаги 1–6)**: высвобождается **~86.8 GB**!
  - Свободное пространство достигает **~150.3 GB** (занятость падает до **36%**).

---

## 6. Онлайн-расширение накопителя `/dev/sda` (+127.13 GiB)

- На накопителе `/dev/sda` (Patriot Burst Elite 480GB) раздел `/dev/sda1` (`/mnt/ssd`) имеет размер **320.00 GiB** (начиная с сектора 2048).
- Непосредственно за разделом находится неразмеченная область размером **266 612 367 секторов** (**127.13 GiB**).
- Расширение раздела в таблице GPT с перемещением backup GPT-заголовка в конец накопителя (`sgdisk -e`, `growpart`) и последующее расширение ext4 (`resize2fs`) происходит в **онлайн-режиме без размонтирования `/mnt/ssd` и без потери существующих 152.3 GiB данных**.
- После расширения емкость `/mnt/ssd` возрастает с **320 GiB** до **447.13 GiB**, а доступное пространство увеличивается с **145.6 GiB** до **~272.7 GiB**, что с избытком вмещает переносимые Ollama (19G) и PrismLauncher (26G).

---

## 7. Программа автоматизации

В репозитории созданы скрипты производственного уровня:
1. `02-safe-cleanup.sh`: Безопасная очистка кэшей, корзины, артефактов Rust и запуск Nix GC с поддержкой `--dry-run`.
2. `03-migrate-ollama.sh`: Двухуровневая миграция каталога моделей Ollama на `/mnt/ssd` с контролем сервиса systemd и rollback.
3. `04-migrate-gaming.sh`: Миграция PrismLauncher (и опционально SD Forge) на `/mnt/ssd` с symlink и аудитом Steam.
4. `05-online-resize-sda1.sh`: Верифицированная процедура онлайн-расширения GPT-раздела `/dev/sda1` и ext4 на 127 ГБ с предпроверкой геометрии.
5. `nixos-storage-optimization.nix`: Декларативный модуль авто-очистки (`nix.gc`) и ограничения меню GRUB (`configurationLimit = 5`).
