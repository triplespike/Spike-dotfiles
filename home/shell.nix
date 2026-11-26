{ config, pkgs, ... }:

let
  esc = builtins.fromJSON ''"\u001b"'';
in {
  programs = {
    bash = {
      enable = true;
      shellAliases = {
        lava = "lava";
        lavat = "lava";
        upp = "nh os switch";
        upd = "nh os switch -u -a";
      };
      initExtra = ''
        fastfetch
      '';
    };

    fastfetch = {
      enable = true;
      settings = let
        frameColor = "${esc}[94m";
        sec1Color = "${esc}[94m";
        sec2Color = "${esc}[95m";
        sec3Color = "${esc}[96m";
        bold = "${esc}[1m";
        reset = "${esc}[0m";
        rBorder = "${esc}[87G${frameColor}│${reset}";
      in {
        logo = {
          type = "kitty-direct";
          source = "${config.home.homeDirectory}/.config/fastfetch/logo.png";
          width = 26;
          height = 13;
          padding = {
            top = 1;
            left = 2;
            right = 4;
          };
        };
        display = {
          separator = "  󰅂  ";
          color.separator = "bright_black";
          percent = {
            type = 3;
          };
          size = {
            maxPrefix = "GB";
            ndigits = 1;
          };
          bar = {
            border = {
              left = "";
              leftElapsed = "";
              right = "";
              rightElapsed = "";
            };
            char = {
              total = "";
              elapsed = "";
            };
            color = {
              elapsed = "bright_cyan";
              total = "bright_black";
            };
            width = 8;
          };
        };
        modules = [
          {
            type = "custom";
            format = "${frameColor}╭─ ${bold}${sec1Color}  system${reset}${frameColor} ─────────────────────────────────────────╮${reset}";
          }
          {
            type = "os";
            key = "${frameColor}│${reset}    os    ";
            keyColor = "bright_blue";
            format = "{name} {version-id}${rBorder}";
          }
          {
            type = "kernel";
            key = "${frameColor}│${reset}  󰌢  kernel";
            keyColor = "bright_blue";
            format = "{release}${rBorder}";
          }
          {
            type = "uptime";
            key = "${frameColor}│${reset}  󱫐  uptime";
            keyColor = "bright_blue";
            format = "{?days}{days}д {?}{hours}ч {minutes}м${rBorder}";
          }
          {
            type = "command";
            key = "${frameColor}│${reset}  󰔠  age   ";
            keyColor = "bright_blue";
            text = "echo $(( ($(date +%s) - $(cat ~/.config/fastfetch/install-date 2>/dev/null || stat -c %Y /nix/store 2>/dev/null || stat -c %Y /etc/nixos)) / 86400 )) дней";
            format = "{result}${rBorder}";
          }
          {
            type = "custom";
            format = "${frameColor}├─ ${bold}${sec2Color}󱂬  desktop${reset}${frameColor} ────────────────────────────────────────┤${reset}";
          }
          {
            type = "wm";
            key = "${frameColor}│${reset}  󰧨  wm    ";
            keyColor = "bright_magenta";
            format = "{pretty-name}${rBorder}";
          }
          {
            type = "terminal";
            key = "${frameColor}│${reset}    term  ";
            keyColor = "bright_magenta";
            format = "{pretty-name}${rBorder}";
          }
          {
            type = "shell";
            key = "${frameColor}│${reset}  󰞷  shell ";
            keyColor = "bright_magenta";
            format = "{pretty-name}${rBorder}";
          }
          {
            type = "custom";
            format = "${frameColor}├─ ${bold}${sec3Color}  hardware${reset}${frameColor} ───────────────────────────────────────┤${reset}";
          }
          {
            type = "cpu";
            key = "${frameColor}│${reset}    cpu   ";
            keyColor = "bright_cyan";
            format = "{1}${rBorder}";
          }
          {
            type = "gpu";
            key = "${frameColor}│${reset}  󰢮  gpu   ";
            keyColor = "bright_cyan";
            format = "{2}${rBorder}";
          }
          {
            type = "memory";
            key = "${frameColor}│${reset}  󰘚  ram   ";
            keyColor = "bright_cyan";
            format = "{percentage-bar} {used} / {total}${rBorder}";
          }
          {
            type = "disk";
            key = "${frameColor}│${reset}  󰋊  disk  ";
            keyColor = "bright_cyan";
            folders = "/";
            format = "{size-percentage-bar} {size-used} / {size-total}${rBorder}";
          }
          {
            type = "custom";
            format = "${frameColor}╰─────────────────────────────────────────────────────╯${reset}";
          }
          {
            type = "colors";
            symbol = "circle";
            paddingLeft = 3;
          }
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

    fish = {
      enable = true;
      shellAliases = {
        pls = "sudo";
        cat = "bat --paging=never";
        zen = "zen-beta";
        lava = "lava";
        lavat = "lava";
      };
      shellAbbrs = {
        upp = "nh os switch";
        upd = "nh os switch -u -a";
      };
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

        # Адаптивная подсветка синтаксиса Fish под активную тему терминала
        set -g fish_color_normal normal
        set -g fish_color_command blue --bold
        set -g fish_color_keyword magenta --bold
        set -g fish_color_quote cyan
        set -g fish_color_redirection normal
        set -g fish_color_end magenta
        set -g fish_color_error red --bold
        set -g fish_color_param normal
        set -g fish_color_comment brblack
        set -g fish_color_selection --background=brblack
        set -g fish_color_search_match --background=brblack
        set -g fish_color_operator magenta
        set -g fish_color_escape cyan
        set -g fish_color_autosuggestion brblack
        set -g fish_color_cwd blue
        set -g fish_color_user blue
        set -g fish_color_host magenta
        set -g fish_color_cancel red

        fastfetch
      '';
    };

    fzf = {
      enable = true;
      enableFishIntegration = true;
    };

    git = {
      enable = true;
      settings = {
        safe.directory = "/etc/nixos";
        user = {
          name = "Spike";
          email = "spike@nixos.local";
        };
      };
    };

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

    yazi = {
      enable = true;
      enableFishIntegration = true;
      enableBashIntegration = true;
      settings = {
        mgr = {
          show_hidden = true;
          sort_by = "natural";
          sort_dir_first = true;
          linemode = "size";
        };
        preview = {
          image_filter = "lanczos3";
          max_width = 1200;
          max_height = 1200;
        };
      };
      theme = {
        manager = {
          cwd = { fg = "#7DCFFF"; italic = true; };
          hovered = { fg = "#E8EDFF"; bg = "#1B2437"; bold = true; };
          preview_hovered = { underline = true; };
          find_keyword = { fg = "#FD4663"; bold = true; };
          find_position = { fg = "#AB66CC"; normal = true; };
          marker_selected = { fg = "#AB66CC"; bg = "#AB66CC"; };
          marker_copied = { fg = "#7DCFFF"; bg = "#7DCFFF"; };
          marker_cut = { fg = "#FD4663"; bg = "#FD4663"; };
          tab_active = { fg = "#E8EDFF"; bg = "#1B2437"; bold = true; };
          tab_inactive = { fg = "#AFB1B6"; bg = "#080B16"; };
          border_style = { fg = "#616771"; };
        };
        status = {
          separator_open = "";
          separator_close = "";
          separator_style = { fg = "#1B2437"; bg = "#1B2437"; };
          mode_normal = { fg = "#080B16"; bg = "#678FE4"; bold = true; };
          mode_select = { fg = "#080B16"; bg = "#AB66CC"; bold = true; };
          mode_unset = { fg = "#080B16"; bg = "#FD4663"; bold = true; };
          progress_label = { fg = "#E8EDFF"; bold = true; };
          progress_normal = { fg = "#678FE4"; bg = "#1B2437"; };
          progress_error = { fg = "#FD4663"; bg = "#1B2437"; };
          permissions_t = { fg = "#678FE4"; };
          permissions_r = { fg = "#C8CBE6"; };
          permissions_w = { fg = "#FD4663"; };
          permissions_x = { fg = "#7DCFFF"; };
          permissions_s = { fg = "#AFB1B6"; };
        };
        filetype = {
          rules = [
            { mime = "image/*"; fg = "#7DCFFF"; }
            { mime = "video/*"; fg = "#AB66CC"; }
            { mime = "audio/*"; fg = "#678FE4"; }
            { mime = "application/zip"; fg = "#FD4663"; }
            { mime = "application/tar"; fg = "#FD4663"; }
            { mime = "application/bzip2"; fg = "#FD4663"; }
            { mime = "application/gzip"; fg = "#FD4663"; }
            { mime = "application/x-tar"; fg = "#FD4663"; }
            { mime = "application/x-7z-compressed"; fg = "#FD4663"; }
            { mime = "application/x-rar"; fg = "#FD4663"; }
            { url = "*/"; fg = "#678FE4"; bold = true; }
            { url = "*"; fg = "#E8EDFF"; }
          ];
        };
      };
    };
  };
}
