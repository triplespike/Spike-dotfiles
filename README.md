# Spike-dotfiles 🌌

<div align="center">

![NixOS](https://img.shields.io/badge/NixOS-Unstable-5277C3?style=for-the-badge&logo=nixos&logoColor=white)
![Wayland](https://img.shields.io/badge/Wayland-Niri-FCC624?style=for-the-badge&logo=wayland&logoColor=black)
![Desktop](https://img.shields.io/badge/Shell-Noctalia-678FE4?style=for-the-badge)
![Terminal](https://img.shields.io/badge/Terminal-Ghostty-FD4663?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-79B9B5?style=for-the-badge)

*A dark cosmic / cyberpunk daily-driver rice on NixOS featuring the Niri scroll-compositor and Noctalia shell, inspired by the Nullscapes aesthetic.*

**[Reddit Showcase on r/unixporn](https://www.reddit.com/r/unixporn/comments/1wtkorx/niri_my_first_rice_on_nixos_x_noctalia/)**

</div>

---

> [!WARNING]
> ### ⚠️ Please Read Before Using!
> 
> * **First Rice & Beginner Notice:** This is my very first rice and my first public dotfiles repo, shared after posting on [r/unixporn](https://www.reddit.com/r/unixporn/comments/1wtkorx/niri_my_first_rice_on_nixos_x_noctalia/). I'm still learning NixOS, so this configuration is tailored specifically to my personal daily machine.
> * **DO NOT blindly run `nixos-rebuild switch`:** This repository is **NOT an automated installer** or a universal turn-key OS template. Applying someone else's system configuration directly onto your machine can break your boot, display drivers, or graphical session.
> * **Hardware-Specific Environment:** These dotfiles are specifically tuned for an **NVIDIA GPU** (proprietary drivers + Wayland buffer limits), AMD CPU, and a single 1080p @ 75Hz display.
> * **No Warranty & No Tech Support:** Everything here is provided strictly **AS-IS**. I take zero responsibility for broken setups, and I cannot provide personal tech support or triage GitHub issues for different hardware or distributions.
> * **Recommended Approach — Cherry-pick! 🍒:** The best way to use these dotfiles is to browse the configs, take inspiration, and cherry-pick what you like (Noctalia capsule blur, Niri keybindings, Ghostty/Fish styling, Fastfetch art, or Satty screenshot pipeline) into your own existing system!

---

## 🎨 Aesthetic & Rice Overview

| Component | Software / Details |
| :--- | :--- |
| **OS** | [NixOS](https://nixos.org/) (Unstable channel, Linux Zen kernel) |
| **Compositor** | [Niri](https://github.com/YaLTeR/niri) (Scrollable-tiling Wayland compositor) |
| **Shell & Bar** | [Noctalia](https://github.com/noctalia-dev/noctalia) (Custom C++ capsule blur patch included) |
| **Terminal** | [Ghostty](https://ghostty.org/) (Nullscapes deep cosmic palette) |
| **Shell** | [Fish](https://fishshell.com/) + [Starship](https://starship.rs/) prompt |
| **Fetch** | [Fastfetch](https://github.com/fastfetch-cli/fastfetch) with bundled art (`assets/fastfetch/Easy.png`) |
| **Launcher** | [Fuzzel](https://codeberg.org/dnkl/fuzzel) |
| **Screenshots** | [Satty](https://github.com/gabm/Satty) with instant screen freeze via Noctalia screencopy |
| **Display Manager** | SDDM with [Astronaut theme](https://github.com/keyitdev/sddm-astronaut-theme) (Black Hole preset) |
| **Bootloader** | GRUB with [HyperFluent theme](https://github.com/Coopydood/HyperFluent-GRUB-Theme) |
| **Audio** | PipeWire + WirePlumber (software mixer volume curve) |
| **Cursor** | Catppuccin Mocha Dark |

---

## 🖼️ Wallpaper

The live animated wallpaper shown in the showcase video is from **Wallpaper Engine**:
* **Steam Workshop:** [Nullscapes - Wallpaper (No Text) by Kiba](https://steamcommunity.com/sharedfiles/filedetails/?id=3741021206) (Workshop ID: `3741021206`).
* A high-resolution static version is included in this repository: [`assets/wallpapers/nullscapes.png`](assets/wallpapers/nullscapes.png).

---

## ⌨️ Keybindings Cheatsheet

| Keybinding | Action |
| :--- | :--- |
| `Mod + Return` | Spawn Terminal ([Ghostty](https://ghostty.org/)) |
| `Mod + D` | Application Launcher ([Fuzzel](https://codeberg.org/dnkl/fuzzel)) |
| `Mod + Q` | Close Active Window |
| `Mod + Space` | Toggle Keyboard Layout (`US` ↔ `RU`) |
| `Print` | Capture Screenshot (Freeze screen + [Satty](https://github.com/gabm/Satty) annotation) |
| `Mod + H / L` | Focus Column Left / Right |
| `Mod + J / K` | Focus Window Down / Up |
| `Mod + Shift + H / L` | Move Column Left / Right |
| `Mod + Shift + J / K` | Move Window Down / Up |
| `Mod + R` | Switch Preset Window Width |
| `Mod + F` | Maximize Column |
| `Mod + Shift + F` | Fullscreen Window |
| `Mod + 1..9` | Switch to Workspace 1–9 |
| `XF86Audio*` | Volume up / down / mute (with Noctalia OSD) |
| `XF86MonBrightness*`| Screen brightness up / down (with Noctalia OSD) |

---

## 🚀 Structure & How to Explore

```
Spike-dotfiles/
├── assets/
│   ├── fastfetch/Easy.png      # Fastfetch anime art logo
│   └── wallpapers/nullscapes.png # High-res static wallpaper
├── patches/
│   └── noctalia-bar-capsule-blur.patch # C++ patch for rounded capsule blur in Noctalia
├── configuration.nix           # System-level NixOS configuration
├── flake.nix                   # Flake inputs & system declaration
├── hardware-configuration.nix.example # Hardware config template
├── home.nix                    # Home Manager: Niri, Noctalia, Ghostty, Fish, Themes
├── LICENSE                     # MIT License
└── README.md                   # This document
```

### If you want to adapt this to your own system:
1. **Never copy wholesale without checking hardware**:
   Generate your own hardware config:
   ```bash
   sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix
   ```
2. **Review `configuration.nix`**:
   Adjust your video drivers (`services.xserver.videoDrivers`), username, and timezone.
3. **Review `home.nix`**:
   Adjust monitor connector names (`output "HDMI-A-1"` under Niri config) to match `niri msg outputs`.
4. Test build before switching:
   ```bash
   nixos-rebuild build --flake .#nixos
   ```

---

## 📜 License

This project is licensed under the [MIT License](LICENSE).
