# Shell programs: fish, starship, zoxide, fzf, bat, eza, fastfetch
{ config, pkgs, lib, inputs, ... }:

let
  esc = builtins.fromJSON ''"\u001b"'';
in {
  programs = {
    bash = {
      enable = true;
      initExtra = ''
        fastfetch
      '';
    };

    fastfetch = {
      enable = true;
      settings = {
        logo = {
          type = "kitty-direct";
          source = "${../../assets/fastfetch/Easy.png}";
          width = 26;
          height = 13;
          padding = {
            top = 1;
            left = 2;
            right = 4;
          };
        };
        display = {
          separator = " 󰅂 ";
          color.separator = "bright_black";
        };
        modules = [
          { type = "custom"; format = "${esc}[38;2;103;143;228m╭─   Система ──────────────────────────────────────${esc}[0m"; }
          { type = "os"; key = "│   Дистрибутив"; keyColor = "bright_blue"; }
          { type = "kernel"; key = "│ 󰌢  Ядро       "; keyColor = "bright_blue"; }
          { type = "uptime"; key = "│ 󱫐  Аптайм     "; keyColor = "bright_blue"; }
          {
            type = "command";
            key = "│ 󰔠  Возраст ОС ";
            keyColor = "bright_blue";
            text = "echo $(( ($(date +%s) - $(cat ~/.config/fastfetch/install-date 2>/dev/null || stat -c %Y /nix/store 2>/dev/null || stat -c %Y /etc/nixos)) / 86400 )) дней";
          }
          { type = "custom"; format = "${esc}[38;2;103;143;228m╰───────────────────────────────────────────────────${esc}[0m"; }
          { type = "custom"; format = "${esc}[38;2;171;102;204m╭─ 󱂬  Десктоп ──────────────────────────────────────${esc}[0m"; }
          { type = "wm"; key = "│ 󰧨  Композитор "; keyColor = "bright_magenta"; }
          { type = "terminal"; key = "│   Терминал   "; keyColor = "bright_magenta"; }
          { type = "shell"; key = "│ 󰞷  Оболочка   "; keyColor = "bright_magenta"; }
          { type = "display"; key = "│ 󰍹  Монитор    "; keyColor = "bright_magenta"; }
          { type = "custom"; format = "${esc}[38;2;171;102;204m╰───────────────────────────────────────────────────${esc}[0m"; }
          { type = "custom"; format = "${esc}[38;2;121;185;181m╭─   Аппаратная часть ─────────────────────────────${esc}[0m"; }
          { type = "cpu"; key = "│   Процессор  "; keyColor = "bright_cyan"; }
          { type = "gpu"; key = "│ 󰢮  Видеокарта "; keyColor = "bright_cyan"; format = "{1} {2}"; }
          { type = "memory"; key = "│ 󰘚  Память ОЗУ "; keyColor = "bright_cyan"; }
          { type = "disk"; key = "│ 󰋊  Диск (Root)"; folders = "/"; keyColor = "bright_cyan"; }
          { type = "custom"; format = "${esc}[38;2;121;185;181m╰───────────────────────────────────────────────────${esc}[0m"; }
          { type = "colors"; symbol = "circle"; paddingLeft = 2; }
        ];
      };
    };

    bat = {
      enable = true;
      config = {
        theme = "base16-256";
        pager = "less -FR";
      };
    };

    eza = {
      enable = true;
      enableFishIntegration = true;
      icons = "auto";
      git = true;
      extraOptions = [
        "--group-directories-first"
        "--header"
      ];
    };

    firefox.enable = true;

    fish = {
      enable = true;
      shellAliases = {
        pls = "sudo";
        cat = "bat --paging=never";
      };
      shellAbbrs.upp = "nh os switch";
      plugins = [
        {
          name = "done";
          src = pkgs.fishPlugins.done.src;
        }
        {
          name = "sponge";
          src = pkgs.fishPlugins.sponge.src;
        }
      ];
      interactiveShellInit = ''
        set -g fish_greeting ""
        fastfetch
      '';
    };

    fzf = {
      enable = true;
      enableFishIntegration = true;
    };

    git.enable = true;

    starship = {
      enable = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
      settings = {
        add_newline = true;
        format = "[](fg:#678FE4)[   ](fg:#080B16 bg:#678FE4)[](fg:#678FE4 bg:#1B2437)$directory$git_branch$git_status$nix_shell$cmd_duration$line_break[╰─](fg:#678FE4) $character";
        character = {
          success_symbol = "[❯](bold #678FE4)[❯](bold #AB66CC)";
          error_symbol = "[❯](bold #FD4663)[❯](bold #FD4663)";
        };
        directory = {
          truncation_length = 3;
          truncation_symbol = "…/";
          truncate_to_repo = false;
          style = "fg:#E8EDFF bg:#1B2437 bold";
          format = "[ $path ]($style)[](fg:#1B2437) ";
        };
        git_branch = {
          style = "fg:#EEF4FF bg:#715CD6 bold";
          format = "[](fg:#715CD6)[ 󰘬 $branch ]($style)";
        };
        git_status = {
          style = "fg:#EEF4FF bg:#715CD6";
          format = "[$all_status$ahead_behind ]($style)[](fg:#715CD6) ";
        };
        nix_shell = {
          style = "fg:#181B24 bg:#AB66CC bold";
          format = "[](fg:#AB66CC)[ 󱄅 nix ]($style)[](fg:#AB66CC) ";
        };
        cmd_duration = {
          min_time = 2000;
          style = "fg:#AFB1B6 bg:#141B29";
          format = "[](fg:#141B29)[ 󱫐 $duration ]($style)[](fg:#141B29) ";
        };
      };
    };

    zoxide = {
      enable = true;
      enableFishIntegration = true;
    };
  };
}