{ config, pkgs, lib, inputs, ... }:

let
  themeInjectZen = pkgs.writeShellScriptBin "theme-inject-zen" ''
    export ZEN_NEWTAB_TEMPLATE="${./zen-newtab/index.html}"
    exec ${pkgs.python3}/bin/python3 ${./scripts/theme-inject-zen.py} "$@"
  '';

  newtabUrl = "file://${config.home.homeDirectory}/.config/zen/newtab/index.html";
  autoconfigPref = pkgs.writeText "z-autoconfig.js" ''
    pref("general.config.filename", "custom-newtab.cfg");
    pref("general.config.obscure_value", 0);
    pref("general.config.sandbox_enabled", false);
  '';

  customNewtabCfg = pkgs.writeText "custom-newtab.cfg" ''
    // AutoConfig for custom newtab URL
    try {
      const applyCustomNewTab = () => {
        try {
          const { AboutNewTab } = ChromeUtils.importESModule("resource:///modules/AboutNewTab.sys.mjs");
          AboutNewTab.newTabURL = "${newtabUrl}";
          Services.prefs.setStringPref("zen.custom.newtab_applied", AboutNewTab.newTabURL);
        } catch (e) {}
      };
      applyCustomNewTab();
      Services.obs.addObserver({ observe: applyCustomNewTab }, "final-ui-startup");
      Services.obs.addObserver({ observe: applyCustomNewTab }, "browser-delayed-startup-finished");
    } catch (e) {}
  '';
in {
  imports = [
    inputs.zen-browser.homeModules.beta
  ];

  home.packages = [
    themeInjectZen
  ];

  # Создаём начальный theme-colors.css и самодостаточный newtab/index.html до запуска браузера
  home.activation.initZenThemeColors = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    rm -f "${config.home.homeDirectory}/.config/zen/newtab/style.css" \
          "${config.home.homeDirectory}/.config/zen/newtab/app.js" \
          "${config.home.homeDirectory}/.config/zen/newtab/theme-colors.css"
    run ${themeInjectZen}/bin/theme-inject-zen || true
  '';

  programs.zen-browser = {
    enable = true;
    setAsDefaultBrowser = false; # Ассоциации MIME уже заданы через xdg.mimeApps в home.nix

    # Gecko читает AutoConfig рядом с реальным бинарником (/proc/self/exe в unwrapped-пакете),
    # а не в обёртке wrapFirefox, поэтому кладём z-autoconfig.js и custom-newtab.cfg прямо туда.
    unwrappedPackage =
      (inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.beta-unwrapped.override {
        inherit (config.programs.zen-browser) policies enablePrivateDesktopEntry;
      }).overrideAttrs (old: {
        postInstall =
          (old.postInstall or "")
          + ''
            for libdir in "$out"/lib/zen-bin-*; do
              chmod -R u+w "$libdir"
              install -m 644 ${autoconfigPref} "$libdir/defaults/pref/z-autoconfig.js"
              install -m 644 ${customNewtabCfg} "$libdir/custom-newtab.cfg"
            done
          '';
      });

    policies = {
      DisableTelemetry = true;
      DisableFirefoxStudies = true;
      DisablePocket = true;
      DisableAppUpdate = true;
      DontCheckDefaultBrowser = true;
      DisableFeedbackCommands = true;
      AutofillCreditCardEnabled = false;
      EnableTrackingProtection = {
        Value = true;
        Locked = true;
        Cryptomining = true;
        Fingerprinting = true;
      };

      ExtensionSettings = {
        "uBlock0@raymondhill.net" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/uBlock0@raymondhill.net/latest.xpi";
          installation_mode = "force_installed";
        };
        "gemini-voyager@nagi-ovo" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/gemini-voyager@nagi-ovo/latest.xpi";
          installation_mode = "normal_installed";
        };
        "page-assist@nazeem" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/page-assist@nazeem/latest.xpi";
          installation_mode = "normal_installed";
        };
        "{c2c003ee-bd69-42a2-b0e9-6f34222cb046}" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/%7Bc2c003ee-bd69-42a2-b0e9-6f34222cb046%7D/latest.xpi";
          installation_mode = "normal_installed";
        };
        "jid1-0dhOSYKGj326og@jetpack" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/jid1-0dhOSYKGj326og@jetpack/latest.xpi";
          installation_mode = "normal_installed";
        };
        "ryoku-zen-palette@local" = {
          install_url = "file://${./vendor/ryoku/zen/ryoku-zen-palette-1.0.3.xpi}";
          installation_mode = "force_installed";
        };
      };
    };

    profiles."Default Profile" = {
      id = 0;
      isDefault = true;
      path = "default"; # Замените на имя вашего профиля Zen при необходимости

      presets.betterfox.enable = true;

      settings = {
        "browser.shell.checkDefaultBrowser" = false;
        "browser.startup.page" = 3; # Восстанавливать открытые вкладки и окна
        "browser.startup.homepage" = newtabUrl;
        "browser.newtabpage.enabled" = true;
        "browser.newtab.preload" = false; # Не предзагружать стандартный about:newtab для Ctrl+T
        "zen.urlbar.replace-newtab" = false; # Открывать кастомную новую вкладку вместо плавающего urlbar
        "zen.urlbar.behavior" = "float"; # Красивый плавающий URLbar по центру при Ctrl+L
        "browser.sessionstore.max_windows_undo" = 0;
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
        "zen.widget.linux.transparency" = true;
        "zen.theme.acrylic-sidebar" = true;
        "zen.theme.acrylic-urlbar" = true;
        "zen.theme.border-radius" = 0;
        "zen.theme.content-element-separation" = 0;
        "zen.theme.gradient.show-custom-colors" = true;
        "layers.acceleration.force-enabled" = true;
        "svg.context-properties.content.enabled" = true;
        "layout.css.color-mix.enabled" = true;
      };

      mods = [
        "4ab93b88-151c-451b-a1b7-a1e0e28fa7f8" # No Sidebar Scrollbar
        "906c6915-5677-48ff-9bfc-096a02a72379" # Floating Status Bar
        "7190e4e9-bead-4b40-8f57-95d852ddc941" # Tab title fixes
        "803c7895-b39b-458e-84f8-a521f4d7a064" # Hide Inactive Workspaces
      ];

      search = {
        force = true;
        default = "google";
        engines = {
          "nixos-packages" = {
            name = "NixOS Packages";
            urls = [
              { template = "https://search.nixos.org/packages?query={searchTerms}"; }
            ];
            icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
            definedAliases = [ "@np" ];
          };
          "nixos-options" = {
            name = "NixOS Options";
            urls = [
              { template = "https://search.nixos.org/options?query={searchTerms}"; }
            ];
            icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
            definedAliases = [ "@no" ];
          };
          "nixos-wiki" = {
            name = "NixOS Wiki";
            urls = [
              { template = "https://wiki.nixos.org/w/index.php?search={searchTerms}"; }
            ];
            icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
            definedAliases = [ "@nw" ];
          };
          "github" = {
            name = "GitHub";
            urls = [
              { template = "https://github.com/search?q={searchTerms}"; }
            ];
            definedAliases = [ "@gh" ];
          };
          "youtube" = {
            name = "YouTube";
            urls = [
              { template = "https://www.youtube.com/results?search_query={searchTerms}"; }
            ];
            definedAliases = [ "@yt" ];
          };
          "archwiki" = {
            name = "ArchWiki";
            urls = [
              { template = "https://wiki.archlinux.org/index.php?search={searchTerms}"; }
            ];
            definedAliases = [ "@aw" ];
          };
        };
      };

      userChrome = ''
        @import url("theme-colors.css");

        /* Zen Browser 1.24+ — Live Glass/Neon Theme (LWT SSE + theme-colors.css fallback) */
        :root {
          --zen-live-bg: var(--lwt-accent-color, var(--zen-bg));
          --zen-live-fg: var(--lwt-text-color, var(--zen-fg));
          --zen-live-surface: var(--arrowpanel-background, var(--zen-surface));
          --zen-live-surface-alt: var(--tab-selected-bgcolor, var(--zen-surface-alt));
          --zen-live-primary: var(--tab-line-color, var(--zen-primary));
          --zen-live-accent: var(--lwt-toolbarbutton-icon-fill-attention, var(--zen-accent));
          --zen-live-hover: color-mix(in srgb, var(--toolbar-field-highlight-color, var(--zen-primary)) 45%, transparent);
          --zen-live-border: color-mix(in srgb, var(--zen-live-primary) 34%, transparent);
          --zen-live-glow: color-mix(in srgb, var(--zen-live-primary) 32%, transparent);
          --zen-live-tinted: color-mix(in srgb, var(--zen-live-bg) 92%, var(--zen-live-primary));
          --zen-live-toolbar: color-mix(in srgb, var(--zen-live-tinted) 76%, transparent);
          --zen-live-sidebar: color-mix(in srgb, var(--zen-live-surface) 72%, transparent);
          --zen-live-urlbar: color-mix(in srgb, var(--zen-live-surface) 88%, transparent);

          --zen-themed-toolbar-bg: color-mix(in srgb, var(--zen-live-tinted) 84%, transparent) !important;
          --zen-themed-toolbar-bg-transparent: var(--zen-live-toolbar) !important;
          --zen-appcontent-border-color: color-mix(in srgb, var(--zen-live-primary) 36%, transparent) !important;
          --zen-primary-color: var(--zen-live-primary) !important;
          --zen-colors-primary: var(--zen-live-primary) !important;
          --zen-colors-primary-foreground: #FFFFFF !important;
          --zen-colors-secondary: var(--zen-live-surface-alt) !important;
          --zen-colors-tertiary: var(--zen-live-surface) !important;
          --zen-colors-hover-bg: var(--zen-live-hover) !important;
          --zen-colors-border: var(--zen-live-border) !important;
          --zen-colors-border-contrast: color-mix(in srgb, var(--zen-live-accent) 48%, transparent) !important;
          --zen-colors-input-bg: var(--zen-live-surface) !important;
          --zen-branding-dark: var(--zen-live-bg) !important;
          --zen-branding-bg: var(--zen-live-bg) !important;
          --zen-main-browser-background: color-mix(in srgb, var(--zen-live-tinted) 82%, transparent) !important;
          --zen-main-browser-background-toolbar: var(--zen-live-toolbar) !important;
          --zen-dialog-background: var(--zen-live-surface) !important;
          --zen-urlbar-background: var(--zen-live-urlbar) !important;
          --zen-element-separation: 0px !important;
        }

        :root,
        #main-window,
        #zen-main-app-wrapper {
          background: var(--zen-themed-toolbar-bg-transparent) !important;
          color: var(--zen-live-fg) !important;
        }

        #navigator-toolbox {
          background: transparent !important;
          backdrop-filter: none !important;
          border: none !important;
          box-shadow: none !important;
        }

        #titlebar {
          background-color: var(--zen-live-sidebar) !important;
          backdrop-filter: blur(26px) saturate(150%) !important;
        }

        /* Верхняя панель, кнопки и индикатор Space */
        #zen-sidebar-top-buttons .toolbarbutton-1,
        #zen-sidebar-foot-buttons .toolbarbutton-1 {
          border-radius: 10px !important;
          transition: background-color 0.16s ease, box-shadow 0.16s ease, transform 0.14s ease !important;
        }

        #zen-sidebar-top-buttons .toolbarbutton-1:hover,
        #zen-sidebar-foot-buttons .toolbarbutton-1:hover {
          background-color: var(--zen-live-hover) !important;
          box-shadow: 0 0 0 1px var(--zen-live-border) !important;
          transform: translateY(-1px);
        }

        #zen-workspaces-button {
          border-radius: 12px !important;
          background: linear-gradient(135deg, color-mix(in srgb, var(--zen-live-primary) 18%, var(--zen-live-surface)) 0%, color-mix(in srgb, var(--zen-live-accent) 14%, var(--zen-live-surface)) 100%) !important;
          border: 1px solid var(--zen-live-border) !important;
          transition: all 0.16s ease !important;
        }

        #zen-workspaces-button:hover {
          border-color: var(--zen-live-primary) !important;
          box-shadow: 0 0 12px var(--zen-live-glow) !important;
        }

        /* Область просмотра контента: вплотную к краям без внутренней рамки */
        #zen-tabbox-wrapper {
          padding: 0 !important;
          margin: 0 !important;
        }

        #tabbrowser-tabbox,
        #tabbrowser-tabpanels,
        .browserSidebarContainer {
          border-radius: 0 !important;
          border: none !important;
          box-shadow: none !important;
        }

        /* Вкладки: плавный сдвиг, градиент и левый неоновый индикатор */
        .tabbrowser-tab {
          margin-block: 2px !important;
        }

        .tabbrowser-tab .tab-stack {
          transition: transform 0.16s cubic-bezier(0.22, 1, 0.36, 1) !important;
        }

        .tabbrowser-tab:hover .tab-stack {
          transform: translateX(3px);
        }

        .tabbrowser-tab .tab-background {
          border-radius: 10px !important;
          border: 1px solid transparent !important;
          transition: background 0.18s ease, border-color 0.18s ease, box-shadow 0.18s ease !important;
        }

        .tabbrowser-tab:hover .tab-background {
          background: var(--zen-live-hover) !important;
          border-color: var(--zen-live-border) !important;
        }

        .tabbrowser-tab[selected="true"] .tab-background,
        .tabbrowser-tab[visuallyselected="true"] .tab-background {
          background: linear-gradient(90deg, color-mix(in srgb, var(--zen-live-primary) 26%, var(--zen-live-surface)) 0%, color-mix(in srgb, var(--zen-live-accent) 16%, var(--zen-live-surface)) 100%) !important;
          border: 1px solid var(--zen-live-primary) !important;
          box-shadow: inset 3px 0 0 var(--zen-live-primary), 0 3px 14px var(--zen-live-glow) !important;
        }

        .tabbrowser-tab[selected="true"] .tab-label,
        .tabbrowser-tab[visuallyselected="true"] .tab-label {
          font-weight: 600 !important;
          color: #FFFFFF !important;
        }

        /* Кнопка новой вкладки в сайдбаре */
        #tabs-newtab-button,
        #zen-tabs-wrapper #tabs-newtab-button {
          border-radius: 10px !important;
          border: 1px dashed var(--zen-live-border) !important;
          margin-top: 4px !important;
          transition: all 0.16s ease !important;
        }

        #tabs-newtab-button:hover {
          background: var(--zen-live-hover) !important;
          border-style: solid !important;
          border-color: var(--zen-live-primary) !important;
        }

        /* Адресная строка и выпадающий плавающий URLbar */
        #urlbar,
        #urlbar-background,
        .urlbar-background {
          border-radius: 12px !important;
          background-color: var(--zen-live-urlbar) !important;
          backdrop-filter: blur(22px) saturate(140%) !important;
          border: 1px solid var(--zen-live-border) !important;
          transition: border-color 0.18s ease, box-shadow 0.18s ease !important;
        }

        #urlbar[focused="true"] > #urlbar-background,
        #urlbar[focused="true"] .urlbar-background,
        #urlbar[open="true"] > #urlbar-background {
          border-color: var(--zen-live-primary) !important;
          box-shadow: 0 0 0 2px var(--zen-live-glow), 0 12px 34px var(--zen-shadow) !important;
        }

        .urlbarView-row[selected] {
          background: linear-gradient(90deg, color-mix(in srgb, var(--zen-live-primary) 26%, transparent), color-mix(in srgb, var(--zen-live-accent) 18%, transparent)) !important;
          border-radius: 8px !important;
        }

        /* Меню и всплывающие панели */
        menupopup,
        panel[type="arrow"],
        .panel-arrowcontent {
          --panel-background: var(--zen-live-surface) !important;
          --panel-color: var(--zen-live-fg) !important;
          --panel-border-color: var(--zen-live-border) !important;
          border-radius: 12px !important;
        }

        menuitem:hover,
        menu:hover {
          background-color: var(--zen-live-hover) !important;
          color: #FFFFFF !important;
          border-radius: 6px !important;
        }

        * {
          scrollbar-color: var(--zen-live-primary) var(--zen-live-bg) !important;
          scrollbar-width: thin !important;
        }
      '';

      userContent = ''
        @import url("theme-colors.css");

        @-moz-document url("about:home"), url("about:newtab"), url("about:blank"), url("about:privatebrowsing") {
          body, #root, .outer-wrapper {
            background-color: var(--zen-bg) !important;
            color: var(--zen-fg) !important;
          }
        }

        @-moz-document url-prefix("about:") {
          :root {
            --in-content-page-background: var(--zen-bg) !important;
            --in-content-box-background: var(--zen-surface) !important;
            --in-content-border-color: var(--zen-border) !important;
            --in-content-text-color: var(--zen-fg) !important;
            --in-content-primary-button-background: var(--zen-primary) !important;
            --in-content-primary-button-text-color: #FFFFFF !important;
          }
        }

        * {
          scrollbar-color: var(--zen-primary) var(--zen-bg) !important;
          scrollbar-width: thin !important;
        }
      '';
    };
  };
}
