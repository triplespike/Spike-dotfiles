set -g fish_greeting ""

# Локальные скрипты пользователя
fish_add_path -g "$HOME/.local/bin"

# Алиасы
alias pls="sudo"
command -q bat && alias cat="bat --paging=never"
if command -q eza
    alias ls="eza --icons=auto --git --group-directories-first --header"
    alias ll="eza -la --icons=auto --git --group-directories-first --header"
    alias tree="eza --tree --icons=auto"
end
alias lavat="lava"

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

if status is-interactive
    command -q starship && starship init fish | source
    command -q zoxide && zoxide init fish | source
    command -q fzf && fzf --fish | source
    command -q fastfetch && fastfetch
end
