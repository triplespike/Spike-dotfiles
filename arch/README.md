# Spike-dotfiles для Arch Linux / CachyOS / EndeavourOS

Портативная версия риса **Niri + Ghostty + Fish + Starship + Fastfetch + Theme Manager + Ryoku-утилиты**, очищенная от NixOS-зависимостей и хардкодов железа.

## Быстрая установка

```bash
git clone https://github.com/triplespike/Spike-dotfiles.git ~/Spike-dotfiles
cd ~/Spike-dotfiles
./arch/install.sh
```

> Если пакеты уже стоят и нужно только разложить конфиги и собрать `ryoku-livewall`:
> ```bash
> ./arch/install.sh --no-packages
> ```

Существующие конфиги автоматически сохраняются в `~/.config-backup-spike-<дата>/`.

## Что ставится и работает из коробки

- **Niri** (`~/.config/niri/config.kdl`, `theme.kdl`, `autostart.sh`) — без жёсткого `HDMI-A-1`, подхватит ваш монитор автоматически.
- **Theme Manager (`Mod+Shift+T`)** — 7 тем с локальными обоями прямо из `assets/wallpapers/` (Steam / Wallpaper Engine не обязательны!), автоопределением монитора и синхронизацией Niri, Ghostty, Cava, Btop, Vesktop, VSCode, Firefox и Zen Browser.
- **Лёгкие видеообои `ryoku-livewall`** — собирается локально в `~/.local/bin/ryoku-livewall` (`wlr-layer-shell` + `wl_shm` + `libav`, резерв — `mpvpaper`/`swaybg`).
- **Авто-пауза обоев в играх и фуллскрине** — `systemd --user` сервис `wallpaper-autopause.service`.
- **Живая перекраска Zen Browser без перезапуска** — локальный SSE-мост `theme-zen-bridge.service` (`127.0.0.1:47616`). Чтобы включить в Zen Browser, просто перетащите `vendor/ryoku/zen/ryoku-zen-palette-1.0.3.xpi` в окно браузера.
- **Экранные и медиа-утилиты:**
  - `Mod+Shift+O` — `ocr-grab` (OCR выделенной области, `eng+rus` -> буфер обмена)
  - `Mod+Shift+R` — `qr-scan` (распознавание QR-кода -> буфер + открытие URL)
  - `Mod+Ctrl+C` — `color-pick` (пипетка цвета `hyprpicker` -> hex)
  - `Mod+Shift+M` — `songrec-grab` (распознавание трека Shazam/SongRec)
  - В терминале: `discord-compress <файл.mp4>` (2-pass сжатие видео до `<10 MB`).

## Опционально (из AUR)
- `noctalia-shell` — верхняя панель и лаунчер (если не установлена, `Mod+D` автоматически открывает `rofi -show drun`, а статичные обои ставит `swaybg`).
- `zen-browser-bin` — браузер (если не установлен, `Mod+B` откроет Firefox).
- `catppuccin-cursors-mocha` — тема курсора.
