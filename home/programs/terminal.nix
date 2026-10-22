# Terminal programs: ghostty, mpv
{ config, pkgs, lib, ... }:

{
  programs = {
    ghostty = {
      enable = true;
      settings = {
        font-family = "JetBrainsMono Nerd Font";
        window-width = 96;
        window-height = 25;
        window-save-state = "never";
        window-padding-x = 14;
        window-padding-y = 12;
        window-padding-balance = true;
        cursor-style = "bar";
        cursor-style-blink = true;
        mouse-hide-while-typing = true;
        window-decoration = false;
        background = "080B16";
        foreground = "E8EDFF";
        background-opacity = 0.76;
        background-blur-radius = 20;
        palette = [
          "0=#080B16" "1=#FD4663" "2=#678FE4" "3=#E0AF68"
          "4=#678FE4" "5=#AB66CC" "6=#82B8E8" "7=#E8EDFF"
          "8=#46516F" "9=#FF6B8B" "10=#7DCFFF" "11=#F1F3FF"
          "12=#829AFF" "13=#C77DFF" "14=#AED8FF" "15=#FFFFFF"
        ];
        cursor-color = "#A8B7FF";
        selection-background = "#344879";
        selection-foreground = "#FFFFFF";
        command = "fish";
        keybind = [
          "shift+insert=paste_from_clipboard"
          "ctrl+v=paste_from_clipboard"
        ];
        clipboard-read = "allow";
        clipboard-paste-protection = false;
      };
    };

    mpv = {
      enable = true;
      scripts = with pkgs.mpvScripts; [
        uosc
        thumbfast
        mpris
      ];
      config = {
        osc = false;
        osd-bar = false;
        border = false;
        hwdec = "auto-safe";
        vo = "gpu-next";
        gpu-context = "wayland";
        save-position-on-quit = true;
        sub-auto = "fuzzy";
        sub-font = "JetBrainsMono Nerd Font";
        sub-font-size = 36;
        sub-color = "#E8EDFF";
        sub-border-color = "#080B16";
        sub-border-size = 2.5;
        "autofit-larger" = "80%x85%";
      };
      scriptOpts = {
        uosc = {
          timeline_style = "bar";
          timeline_line_width = 3;
          timeline_size = 32;
          progress = "always";
          progress_size = 3;
          controls = "menu,subtitles<has_many_subtitles>,audio<has_many_audio>,video<has_many_video>,gap,prev,play-pause,next,gap,fullscreen";
          color = "foreground=678fe4,foreground_text=e8edff,background=080b16,background_text=e8edff,curtain=080b16,success=7dcfff,error=fd4663";
          opacity = "timeline=0.85,controls=0.85,timeline_persisted=0.6";
        };
      };
    };
  };
}