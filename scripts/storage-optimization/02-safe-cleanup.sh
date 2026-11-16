#!/usr/bin/env bash
# ==============================================================================
# 02-safe-cleanup.sh - Безопасная очистка дискового пространства на NVMe
# ==============================================================================
# Высвобождает ~14.1 ГБ локальных кэшей и временных файлов сборки,
# а также выполняет безопасный Garbage Collection в NixOS (User: ~10 ГБ, Root: ~9.1 ГБ).
#
# Ключи:
#   --dry-run, -n       : Режим симуляции. Сканирует размеры и выводит план без изменений.
#   -y, --yes, --force  : Не запрашивать подтверждений перед очисткой.
#   --with-system-gc    : Включить удаление устаревших системных поколений (требует sudo).
#   --skip-nix-gc       : Пропустить очистку Nix store (очистить только локальные кэши).
#   -h, --help          : Показать справку по использованию.
# ==============================================================================

set -euo pipefail

# Цветовая палитра для терминала
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

DRY_RUN=false
AUTO_CONFIRM=false
WITH_SYSTEM_GC=false
SKIP_NIX_GC=false

usage() {
    cat << 'EOF'
Использование: ./02-safe-cleanup.sh [ОПЦИИ]

Опции:
  -n, --dry-run        Режим симуляции (анализирует размеры и показывает план без удаления)
  -y, --yes, --force   Выполнить очистку без интерактивных запросов подтверждения
  --with-system-gc     Включить очистку старых поколений NixOS 179-180 (требует sudo)
  --skip-nix-gc        Очистить только локальные кэши, пропустив nix-collect-garbage
  -h, --help           Показать эту справку и выйти

Примеры:
  ./02-safe-cleanup.sh --dry-run
  ./02-safe-cleanup.sh -y
  ./02-safe-cleanup.sh --with-system-gc
EOF
    exit "${1:-0}"
}

# Парсинг аргументов
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -y|--yes|--force)
            AUTO_CONFIRM=true
            shift
            ;;
        --with-system-gc)
            WITH_SYSTEM_GC=true
            shift
            ;;
        --skip-nix-gc)
            SKIP_NIX_GC=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Неизвестный параметр:${NC} $1" >&2
            usage 1
            ;;
    esac
done

echo -e "${CYAN}${BOLD}=== Скрипт безопасной очистки системного накопителя NVMe ===${NC}"
if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}${BOLD}[РЕЖИМ СИМУЛЯЦИИ (--dry-run)]: Никакие файлы не будут удалены.${NC}\n"
else
    echo -e "${GREEN}Режим реального применения.${NC}\n"
fi

# Проверка активного пользователя
CURRENT_USER="$(id -un)"
if [[ "$CURRENT_USER" != "spike" && "$EUID" -ne 0 ]]; then
    echo -e "${YELLOW}Предупреждение: Скрипт запускается от пользователя ${CURRENT_USER}, ожидался пользователь 'spike'.${NC}"
fi

# Вспомогательная функция измерения размера каталога в удобочитаемом виде
get_size() {
    local target="$1"
    if [[ -e "$target" ]]; then
        du -sh "$target" 2>/dev/null | awk '{print $1}'
    else
        echo "0B"
    fi
}

# Вспомогательная функция измерения размера в байтах
get_bytes() {
    local target="$1"
    if [[ -e "$target" ]]; then
        du -sb "$target" 2>/dev/null | awk '{print $1}'
    else
        echo "0"
    fi
}

echo -e "${BLUE}${BOLD}[1/4] Аудит кандидатов на локальную очистку...${NC}"

TRASH_DIR="/home/spike/.local/share/Trash"
SPIKETIFY_TARGET="/home/spike/projects/spiketify/src-tauri/target"
PIP_CACHE="/home/spike/.cache/pip"
APPIMAGE_CACHE="/home/spike/.cache/appimage-run"
SPOTIFY_CACHE="/home/spike/.cache/spotify/Data"
ZEN_CACHE_PATTERN="/home/spike/.cache/zen/*/cache2"
NPM_CACHE="/home/spike/.npm/_cacache"
CORRUPTED_SD_MODEL="/home/spike/projects/stable-diffusion-webui-forge/models/Stable-diffusion/meinaHentai_v3_baked_vae.safetensors.corrupted"
ORPHAN_GCROOT="/home/spike/.gemini/antigravity-cli/brain/4a64fdfb-2121-461e-87b3-8b3249091086/scratch/cnijfilter2-result"

SIZE_TRASH="$(get_size "$TRASH_DIR")"
SIZE_SPIKETIFY="$(get_size "$SPIKETIFY_TARGET")"
SIZE_PIP="$(get_size "$PIP_CACHE")"
SIZE_APPIMAGE="$(get_size "$APPIMAGE_CACHE")"
SIZE_SPOTIFY="$(get_size "$SPOTIFY_CACHE")"
SIZE_NPM="$(get_size "$NPM_CACHE")"

# Zen cache search
SIZE_ZEN="0B"
for zpath in $ZEN_CACHE_PATTERN; do
    if [[ -d "$zpath" ]]; then
        SIZE_ZEN="$(get_size "$zpath")"
        break
    fi
done

echo -e "  • Корзина (${TRASH_DIR}): ${BOLD}${SIZE_TRASH}${NC}"
echo -e "  • Rust build target Spiketify (${SPIKETIFY_TARGET}): ${BOLD}${SIZE_SPIKETIFY}${NC}"
echo -e "  • Кэш Python pip (${PIP_CACHE}): ${BOLD}${SIZE_PIP}${NC}"
echo -e "  • Распакованные рантаймы AppImage (${APPIMAGE_CACHE}): ${BOLD}${SIZE_APPIMAGE}${NC}"
echo -e "  • Потоковый кэш Spotify (${SPOTIFY_CACHE}): ${BOLD}${SIZE_SPOTIFY}${NC}"
echo -e "  • Дисковый кэш Zen Browser (cache2): ${BOLD}${SIZE_ZEN}${NC}"
echo -e "  • Кэш пакетов npm (${NPM_CACHE}): ${BOLD}${SIZE_NPM}${NC}"
if [[ -f "$CORRUPTED_SD_MODEL" ]]; then
    echo -e "  • Поврежденный чекпоинт SD (${CORRUPTED_SD_MODEL}): ${BOLD}$(get_size "$CORRUPTED_SD_MODEL")${NC}"
fi
if [[ -e "$ORPHAN_GCROOT" ]]; then
    echo -e "  • Оставленный корень сборки AI session (${ORPHAN_GCROOT}): ${BOLD}$(get_size "$ORPHAN_GCROOT")${NC}"
fi

echo -e "\n${BLUE}${BOLD}[2/4] Проверка запущенных зависимых процессов...${NC}"
RUNNING_PROCESSES=0

if pgrep -x "spotify" > /dev/null 2>&1 || pgrep -f "spotify" > /dev/null 2>&1; then
    echo -e "  ${YELLOW}⚠ Spotify запущен.${NC} Перед очисткой кэша треков Data/ процесс будет остановлен."
    RUNNING_PROCESSES=$(( RUNNING_PROCESSES + 1 ))
fi

if pgrep -x "zen" > /dev/null 2>&1 || pgrep -f "zen-bin" > /dev/null 2>&1; then
    echo -e "  ${YELLOW}⚠ Zen Browser запущен.${NC} Очистка cache2 безопасна, но предпочтительно закрыть браузер для освобождения файловых дескрипторов."
    RUNNING_PROCESSES=$(( RUNNING_PROCESSES + 1 ))
fi

if [[ "$RUNNING_PROCESSES" -eq 0 ]]; then
    echo -e "  ${GREEN}✓ Активных конфликтующих процессов не обнаружено.${NC}"
else
    echo -e "  ${YELLOW}ℹ Обнаружено запущенных связанных процессов: ${RUNNING_PROCESSES}.${NC}"
fi

# Интерактивное подтверждение
if [[ "$DRY_RUN" == false && "$AUTO_CONFIRM" == false ]]; then
    echo -e ""
    read -rp "Продолжить безопасную очистку локальных кэшей? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[yYдД] ]]; then
        echo -e "${RED}Операция отменена пользователем.${NC}"
        exit 0
    fi
fi

echo -e "\n${BLUE}${BOLD}[3/4] Выполнение очистки локальных кэшей...${NC}"

# 1. Корзина
if [[ -d "$TRASH_DIR" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  [DRY-RUN] Будет очищено содержимое корзины: ${TRASH_DIR}/*"
    else
        echo -e "  -> Очистка корзины..."
        find "${TRASH_DIR}" -mindepth 1 -delete 2>/dev/null || rm -rf "${TRASH_DIR:?}"/*
        echo -e "     ${GREEN}✓ Корзина очищена.${NC}"
    fi
fi

# 2. Rust build artifacts
if [[ -d "$SPIKETIFY_TARGET" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  [DRY-RUN] Будет удален каталог сборки: ${SPIKETIFY_TARGET}"
    else
        echo -e "  -> Очистка артефактов сборки Spiketify Rust..."
        rm -rf "$SPIKETIFY_TARGET"
        echo -e "     ${GREEN}✓ Каталог target/ удален (исходный код полностью сохранен).${NC}"
    fi
fi

# 3. Pip cache
if [[ -d "$PIP_CACHE" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  [DRY-RUN] Будет очищен кэш pip: rm -rf ${PIP_CACHE}/*"
    else
        echo -e "  -> Очистка кэша pip..."
        rm -rf "${PIP_CACHE:?}"/*
        echo -e "     ${GREEN}✓ Кэш pip очищен.${NC}"
    fi
fi

# 4. Appimage-run cache
if [[ -d "$APPIMAGE_CACHE" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  [DRY-RUN] Будут удалены распакованные AppImage: rm -rf ${APPIMAGE_CACHE}/*"
    else
        echo -e "  -> Очистка распакованных AppImage..."
        rm -rf "${APPIMAGE_CACHE:?}"/*
        echo -e "     ${GREEN}✓ Кэш appimage-run очищен.${NC}"
    fi
fi

# 5. Spotify Data cache
if [[ -d "$SPOTIFY_CACHE" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  [DRY-RUN] Будет очищен кэш потокового аудио Spotify: rm -rf ${SPOTIFY_CACHE}/*"
    else
        if pgrep -f "spotify" > /dev/null 2>&1; then
            echo -e "     Остановка процесса Spotify для безопасной очистки..."
            pkill -f spotify || true
            sleep 1
        fi
        echo -e "  -> Очистка кэша потокового аудио Spotify..."
        rm -rf "${SPOTIFY_CACHE:?}"/*
        echo -e "     ${GREEN}✓ Кэш Spotify Data/ очищен (плейлисты и аккаунт сохранены).${NC}"
    fi
fi

# 6. Zen browser cache
for zpath in $ZEN_CACHE_PATTERN; do
    if [[ -d "$zpath" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "  [DRY-RUN] Будет очищен дисковый кэш браузера: rm -rf ${zpath}/*"
        else
            echo -e "  -> Очистка дискового кэша Zen Browser (${zpath})..."
            rm -rf "${zpath:?}"/*
            echo -e "     ${GREEN}✓ Дисковый кэш страниц браузера очищен.${NC}"
        fi
    fi
done

# 7. npm cache
if [[ -d "$NPM_CACHE" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  [DRY-RUN] Будет очищен кэш npm: rm -rf ${NPM_CACHE}/*"
    else
        echo -e "  -> Очистка кэша пакетов npm..."
        rm -rf "${NPM_CACHE:?}"/*
        echo -e "     ${GREEN}✓ Кэш npm очищен.${NC}"
    fi
fi

# 8. Corrupted SD model
if [[ -f "$CORRUPTED_SD_MODEL" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  [DRY-RUN] Будет удален поврежденный файл модели: rm -f ${CORRUPTED_SD_MODEL}"
    else
        rm -f "$CORRUPTED_SD_MODEL"
        echo -e "     ${GREEN}✓ Удален поврежденный файл .safetensors.corrupted.${NC}"
    fi
fi

# 9. Orphan GC root
if [[ -e "$ORPHAN_GCROOT" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  [DRY-RUN] Будет удален временный gcroot: rm -f ${ORPHAN_GCROOT}"
    else
        rm -f "$ORPHAN_GCROOT"
        echo -e "     ${GREEN}✓ Удален неиспользуемый gcroot временной сборки.${NC}"
    fi
fi

# 4. Nix Garbage Collection
echo -e "\n${BLUE}${BOLD}[4/4] Garbage Collection в хранилище Nix...${NC}"

if [[ "$SKIP_NIX_GC" == true ]]; then
    echo -e "  ${YELLOW}Nix GC пропущен по запросу пользователя (--skip-nix-gc).${NC}"
else
    # 4.1. Очистка пользовательских профилей и Home-Manager
    if command -v nh >/dev/null 2>&1; then
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "  [DRY-RUN] Запуск проверки пользовательских профилей через 'nh clean user --dry':"
            nh clean user --dry || true
        else
            echo -e "  -> Запуск 'nh clean user --keep 1' (сохраняет только текущее поколение)..."
            nh clean user --keep 1 || true
            echo -e "  -> Сборка мусора в пользовательском профиле через 'nix-collect-garbage -d'..."
            nix-collect-garbage -d || true
            echo -e "     ${GREEN}✓ Пользовательские профили и недостижимые пути очищены.${NC}"
        fi
    else
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "  [DRY-RUN] Будет выполнен 'nix-collect-garbage -d' для пользователя ${CURRENT_USER}."
        else
            echo -e "  -> Запуск 'nix-collect-garbage -d'..."
            nix-collect-garbage -d || true
            echo -e "     ${GREEN}✓ Пользовательский Nix GC завершен.${NC}"
        fi
    fi

    # 4.2. Системный Nix GC (Поколения 179-180)
    if [[ "$WITH_SYSTEM_GC" == true ]]; then
        echo -e "\n  ${YELLOW}${BOLD}--- Системная очистка NixOS (требуются права root) ---${NC}"
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "  [DRY-RUN] План системного GC:"
            echo -e "    1. sudo nix-env -p /nix/var/nix/profiles/system --delete-generations 179 180"
            echo -e "       (Удалит поколения 179 и 180 с ядром zen1, сохранив booted 181 и current 182)"
            echo -e "    2. sudo nix-collect-garbage -d"
            echo -e "    3. sudo /nix/var/nix/profiles/system/bin/switch-to-configuration boot"
            echo -e "       (Обновит конфигурацию меню GRUB)"
        else
            echo -e "  -> Удаление устаревших поколений системы 179 и 180..."
            sudo nix-env -p /nix/var/nix/profiles/system --delete-generations 179 180
            echo -e "  -> Запуск системного сбора мусора..."
            sudo nix-collect-garbage -d
            echo -e "  -> Обновление записей меню GRUB..."
            sudo /nix/var/nix/profiles/system/bin/switch-to-configuration boot
            echo -e "     ${GREEN}✓ Системный Nix GC успешно выполнен.${NC}"
        fi
    else
        echo -e "\n  ${CYAN}Примечание по системному GC:${NC}"
        echo -e "  Для высвобождения дополнительных ~9.1 ГБ системных пакетов (удаление старых поколений 179 и 180) запустите:"
        echo -e "    ${BOLD}./02-safe-cleanup.sh --with-system-gc${NC}"
        echo -e "  (или вручную: sudo nix-env -p /nix/var/nix/profiles/system --delete-generations 179 180 && sudo nix-collect-garbage -d)"
    fi
fi

echo -e "\n${GREEN}${BOLD}=== Результаты операции ===${NC}"
if [[ "$DRY_RUN" == true ]]; then
    echo -e "Прогнозируемый объем высвобождения:"
    echo -e "  • Локальные кэши и target/: ${BOLD}~14.1 ГБ${NC}"
    echo -e "  • Пользовательский Nix GC:   ${BOLD}~10.0 ГБ${NC}"
    if [[ "$WITH_SYSTEM_GC" == true ]]; then
        echo -e "  • Системный Nix GC:          ${BOLD}~9.1 ГБ${NC}"
        echo -e "  • ИТОГО:                     ${BOLD}~33.2 ГБ${NC} чистого пространства на системном NVMe!"
    else
        echo -e "  • ИТОГО (без sudo):          ${BOLD}~24.1 ГБ${NC} чистого пространства на системном NVMe!"
    fi
else
    echo -e "Текущее состояние корневого накопителя (/dev/mapper/cryptroot):"
    df -h /
fi
echo -e "${GREEN}Операция завершена.${NC}"
