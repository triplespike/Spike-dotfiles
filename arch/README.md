# Spike-dotfiles для Arch Linux / CachyOS / EndeavourOS

Полный перенос риса **Niri + Noctalia + Ghostty + Fish + Starship + Fastfetch + Zen Browser + Theme Manager + Ryoku-утилиты** на Arch-подобные дистрибутивы за один шаг.

## Быстрая установка

```bash
git clone https://github.com/triplespike/Spike-dotfiles.git ~/Spike-dotfiles
cd ~/Spike-dotfiles
./arch/install.sh
```

> Если пакеты уже стоят и нужно только разложить конфиги и пересобрать `ryoku-livewall`:
> ```bash
> ./arch/install.sh --no-packages
> ```

Существующие конфиги автоматически сохраняются в `~/.config-backup-spike-<дата>/`.

## Что ставится и настраивается автоматически

- **Noctalia Shell** (`extra/noctalia`) — верхняя капсульная панель, центр управления, OSD и лаунчер (`config.toml` + все 10 оффлайн-палитр), плюс тёмный `rofi` в резерв.
- **Тёмная тема GTK + Qt/Dolphin и курсор** (`adw-gtk3-dark`, `BreezeDark` в `kdeglobals`, `Papirus-Dark`, `catppuccin-mocha-dark-cursors`) — конфиги GTK 3/4, Qt/KDE (`QT_QPA_PLATFORMTHEME=kde`), `gsettings` (`prefer-dark`) и XCursor.
- **Zen Browser (`zen-browser-bin`) + Firefox** — `user.js`, стеклянный `userChrome.css`, кастомная новая вкладка, и встроенный подписанный XPI `ryoku-zen-palette@local` для живой перекраски без перезапуска через `theme-zen-bridge.service`.
- **Niri** (`~/.config/niri/config.kdl`, `theme.kdl`, `autostart.sh`) — без жёсткого `HDMI-A-1`, с автопоиском установленных программ и пробросом `~/.local/bin`.
- **Theme Manager (`Mod+Shift+T`)** — все 10 цветовых тем с оффлайн-палитрами Noctalia, автоопределением монитора и плеером `ryoku-livewall` (`wlr-layer-shell` + `wl_shm` + `libav`, резерв — `mpvpaper`/`swaybg`). Видео-обои **Aperture GD**, **Catppuccin** и **Medieval Grim** (`medieval-loop.mp4`) уже лежат в `assets/wallpapers/`, а остальные 7 тем (**Nullscapes**, **Shardscapes**, **Nord Aurora**, **Sakura Moon**, **Golden Woods**, **Messy Room by Night**, **Tame Impala**) используют чистые `1080p` `.png` обои.
- **Авто-пауза обоев в играх и фуллскрине** — `wallpaper-autopause.service`.
- **Экранные и медиа-утилиты:**
  - `Mod+Shift+O` — `ocr-grab` (OCR выделенной области, `eng+rus` -> буфер обмена)
  - `Mod+Shift+R` — `qr-scan` (распознавание QR-кода -> буфер + открытие URL)
  - `Mod+Ctrl+C` — `color-pick` (пипетка цвета `hyprpicker` -> hex)
  - `Mod+Shift+M` — `songrec-grab` (распознавание трека Shazam/SongRec)
  - В терминале: `discord-compress <файл.mp4>` (2-pass сжатие видео до `<10 MB`).
