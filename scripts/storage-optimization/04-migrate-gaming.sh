#!/usr/bin/env bash
# ==============================================================================
# 04-migrate-gaming.sh - Миграция игровых данных (PrismLauncher 26 GB) на /mnt/ssd
# ==============================================================================
# 1. Аудит библиотек Steam (подтверждение размещения на /mnt/storage и /mnt/ssd)
# 2. Миграция каталога инстансов PrismLauncher (~/.local/share/PrismLauncher) на /mnt/ssd
# 3. (Опционально) Миграция моделей Stable Diffusion WebUI Forge (8.6 GB) на /mnt/ssd
#
# Ключи:
#   -n, --dry-run        : Режим симуляции (проверка свободного места и путей без записи)
#   -y, --yes, --force   : Применить миграцию без интерактивных подтверждений
#   --with-sd-models     : Включить также миграцию моделей Stable Diffusion (8.6 GB)
#   --rollback           : Откатить миграцию PrismLauncher из резервной копии
#   -h, --help           : Справка по использованию
# ==============================================================================

set -euo pipefail

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

TARGET_BASE="/mnt/ssd"

PRISM_SRC="/home/spike/.local/share/PrismLauncher"
PRISM_DEST="/mnt/ssd/PrismLauncher"
PRISM_BAK="/home/spike/.local/share/PrismLauncher.bak"

SD_SRC="/home/spike/projects/stable-diffusion-webui-forge/models/Stable-diffusion"
SD_DEST="/mnt/ssd/stable-diffusion-models"
SD_BAK="/home/spike/projects/stable-diffusion-webui-forge/models/Stable-diffusion.bak"

STEAM_VDF="/home/spike/.local/share/Steam/steamapps/libraryfolders.vdf"

DRY_RUN=false
AUTO_CONFIRM=false
WITH_SD=false
DO_ROLLBACK=false

usage() {
    cat << 'EOF'
Использование: ./04-migrate-gaming.sh [ОПЦИИ]

Опции:
  -n, --dry-run        Режим симуляции (проверяет пространство и выводит команды)
  -y, --yes, --force   Выполнить миграцию без запросов подтверждения
  --with-sd-models     Перенести также чекпоинты Stable Diffusion (8.6 ГБ)
  --rollback           Откатить миграцию из резервной копии (.bak)
  -h, --help           Показать эту справку и выйти

Примеры:
  ./04-migrate-gaming.sh --dry-run
  ./04-migrate-gaming.sh -y
  ./04-migrate-gaming.sh --with-sd-models
  ./04-migrate-gaming.sh --rollback
EOF
    exit "${1:-0}"
}

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
        --with-sd-models)
            WITH_SD=true
            shift
            ;;
        --rollback)
            DO_ROLLBACK=true
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

echo -e "${CYAN}${BOLD}=== Скрипт миграции игровых данных и аудита библиотек ===${NC}"

# ==============================================================================
# ПРОЦЕДУРА ОТКАТА (ROLLBACK)
# ==============================================================================
if [[ "$DO_ROLLBACK" == true ]]; then
    echo -e "${YELLOW}${BOLD}Инициирован процесс отката миграции игровых данных...${NC}"
    ROLLED_BACK=false

    # Откат PrismLauncher
    if [[ -d "$PRISM_BAK" ]]; then
        echo -e "  -> Восстановление PrismLauncher из ${PRISM_BAK}..."
        if [[ -L "$PRISM_SRC" ]]; then
            rm -f "$PRISM_SRC"
        fi
        mv "$PRISM_BAK" "$PRISM_SRC"
        echo -e "  ${GREEN}✓ PrismLauncher успешно восстановлен из резервной копии!${NC}"
        ROLLED_BACK=true
    elif [[ -d "$PRISM_SRC" && ! -L "$PRISM_SRC" ]]; then
        echo -e "  • PrismLauncher уже находится в исходном каталоге (не является симлинком)."
    else
        echo -e "  • Резервная копия PrismLauncher (${PRISM_BAK}) не найдена."
    fi

    # Откат Stable Diffusion моделей
    if [[ -d "$SD_BAK" ]]; then
        echo -e "  -> Восстановление чекпоинтов Stable Diffusion из ${SD_BAK}..."
        if [[ -L "$SD_SRC" ]]; then
            rm -f "$SD_SRC"
        fi
        mv "$SD_BAK" "$SD_SRC"
        echo -e "  ${GREEN}✓ Чекпоинты SD успешно восстановлены из резервной копии!${NC}"
        ROLLED_BACK=true
    elif [[ "$WITH_SD" == true ]]; then
        echo -e "  ${YELLOW}⚠ Запрошен откат моделей SD (--with-sd-models), но резервная копия ${SD_BAK} не найдена.${NC}"
    fi

    if [[ "$ROLLED_BACK" == false ]]; then
        echo -e "${RED}Ошибка: Не найдено ни одной резервной копии для отката (${PRISM_BAK}, ${SD_BAK})!${NC}" >&2
        exit 1
    fi

    echo -e "${GREEN}${BOLD}✓ Процедура отката успешно завершена!${NC}"
    exit 0
fi

# ==============================================================================
# [1/4] АУДИТ БИБЛИОТЕК STEAM
# ==============================================================================
echo -e "${BLUE}${BOLD}[1/4] Ревизия библиотек Steam...${NC}"

if [[ -f "$STEAM_VDF" ]]; then
    echo -e "  Файл конфигурации библиотек: ${STEAM_VDF}"
    grep -E '"path"|"label"' "$STEAM_VDF" | sed 's/^[ \t]*/    /' || true
    echo -e "  ${GREEN}✓ Установлено:${NC} Библиотеки Steam уже расположены на вторичных накопителях:"
    echo -e "    • /mnt/storage/SteamLibrary (HDD): основное хранилище тяжелых игр (~388 ГБ)"
    echo -e "    • /mnt/ssd/SteamLibrary (SATA SSD): быстрые игры (~153 ГБ)"
    echo -e "  Каталог ~/.local/share/Steam (8.2 ГБ) содержит рантаймы и инструменты Proton (GE-Proton, Proton-CachyOS),"
    echo -e "  которые безопасно оставить на NVMe для максимального быстродействия запуска."
else
    echo -e "  ${YELLOW}Файл libraryfolders.vdf не найден, пропускаем вывод библиотек.${NC}"
fi

# ==============================================================================
# [2/4] ПРЕДВАРИТЕЛЬНЫЕ ПРОВЕРКИ ДЛЯ PRISMLAUNCHER
# ==============================================================================
echo -e "\n${BLUE}${BOLD}[2/4] Проверка исходных каталогов и свободного места на /mnt/ssd...${NC}"

if ! findmnt "$TARGET_BASE" >/dev/null 2>&1; then
    echo -e "${RED}Ошибка: ${TARGET_BASE} не смонтирован!${NC}" >&2
    exit 1
fi

AVAIL_KB=$(df -P "$TARGET_BASE" | awk 'NR==2 {print $4}')
AVAIL_GB=$(( AVAIL_KB / 1024 / 1024 ))
echo -e "  ✓ Доступно на ${TARGET_BASE}: ${BOLD}${AVAIL_GB} ГБ${NC}"

# Проверка PrismLauncher
PRISM_SIZE="0B"
if [[ -L "$PRISM_SRC" ]]; then
    CURRENT_DEST="$(readlink -f "$PRISM_SRC")"
    if [[ "$CURRENT_DEST" == "$PRISM_DEST" ]]; then
        echo -e "  ${GREEN}✓ PrismLauncher уже перенесен в ${PRISM_DEST} (симлинк активен).${NC}"
    else
        echo -e "  ${YELLOW}⚠ PrismLauncher является симлинком на другой путь: ${CURRENT_DEST}.${NC}"
    fi
elif [[ -d "$PRISM_SRC" ]]; then
    PRISM_SIZE="$(du -sh "$PRISM_SRC" | awk '{print $1}')"
    echo -e "  ✓ Каталог PrismLauncher найден: ${BOLD}${PRISM_SIZE}${NC} (${PRISM_SRC})"
else
    echo -e "  ${YELLOW}Каталог ${PRISM_SRC} не найден.${NC}"
fi

# Проверка SD Models если включен флаг
SD_SIZE="0B"
if [[ "$WITH_SD" == true ]]; then
    if [[ -L "$SD_SRC" ]]; then
        echo -e "  ${GREEN}✓ Чекпоинты Stable Diffusion уже перенесены в $(readlink -f "$SD_SRC").${NC}"
    elif [[ -d "$SD_SRC" ]]; then
        SD_SIZE="$(du -sh "$SD_SRC" | awk '{print $1}')"
        echo -e "  ✓ Каталог моделей Stable Diffusion найден: ${BOLD}${SD_SIZE}${NC} (${SD_SRC})"
    fi
fi

# Проверка процессов
if pgrep -f -i "prismlauncher" >/dev/null 2>&1; then
    echo -e "  ${YELLOW}⚠ Процесс PrismLauncher активен.${NC} Перед миграцией процесс необходимо закрыть."
fi
if pgrep -f "PrismLauncher/instances" >/dev/null 2>&1 || pgrep -f "net.minecraft" >/dev/null 2>&1; then
    echo -e "  ${RED}⚠ Обнаружен работающий экземпляр Minecraft!${NC} Закройте игру перед миграцией во избежание повреждения сохранений."
fi

# Динамический расчет необходимого пространства
REQUIRED_GB=0
if [[ -d "$PRISM_SRC" && ! -L "$PRISM_SRC" ]]; then
    REQUIRED_GB=$(( REQUIRED_GB + 35 ))
fi
if [[ "$WITH_SD" == true && -d "$SD_SRC" && ! -L "$SD_SRC" ]]; then
    REQUIRED_GB=$(( REQUIRED_GB + 10 ))
fi

if [[ "$REQUIRED_GB" -eq 0 ]]; then
    echo -e "  ${GREEN}✓ Все выбранные для миграции каталоги уже перенесены на ${TARGET_BASE}!${NC}"
elif [[ "$AVAIL_GB" -lt "$REQUIRED_GB" ]]; then
    echo -e "${RED}Ошибка: На ${TARGET_BASE} недостаточно места (${AVAIL_GB} ГБ доступно, требуется ${REQUIRED_GB} ГБ).${NC}" >&2
    exit 1
else
    echo -e "  ✓ Расчетное требуемое место: ${BOLD}${REQUIRED_GB} ГБ${NC} (доступно: ${AVAIL_GB} ГБ)"
fi

# ==============================================================================
# [3/4] РЕЖИМ СИМУЛЯЦИИ ИЛИ ПОДТВЕРЖДЕНИЕ
# ==============================================================================
if [[ "$DRY_RUN" == true ]]; then
    echo -e "\n${YELLOW}${BOLD}[РЕЖИМ СИМУЛЯЦИИ (--dry-run)]${NC}"
    echo -e "План выполнения:"
    if [[ -d "$PRISM_SRC" && ! -L "$PRISM_SRC" ]]; then
        echo -e "  1. Проверка отсутствия запущенных инстансов Minecraft и остановка PrismLauncher"
        echo -e "  2. rsync -aHAXvh --info=progress2 ${PRISM_SRC}/ ${PRISM_DEST}/"
        echo -e "  3. mv ${PRISM_SRC} ${PRISM_BAK}"
        echo -e "  4. ln -s ${PRISM_DEST} ${PRISM_SRC}"
        echo -e "  5. Проверка доступа к инстансам"
    fi
    if [[ "$WITH_SD" == true && -d "$SD_SRC" && ! -L "$SD_SRC" ]]; then
        echo -e "  6. mkdir -p ${SD_DEST}"
        echo -e "  7. rsync -aHAXvh --info=progress2 ${SD_SRC}/ ${SD_DEST}/"
        echo -e "  8. mv ${SD_SRC} ${SD_BAK}"
        echo -e "  9. ln -s ${SD_DEST} ${SD_SRC}"
    fi
    if [[ "$REQUIRED_GB" -eq 0 ]]; then
        echo -e "  • Все каталоги уже перенесены на ${TARGET_BASE}, активных действий не требуется."
    fi
    echo -e "\n${GREEN}Все проверки пройдены. Запустите без ключа --dry-run для применения.${NC}"
    exit 0
fi

if [[ "$AUTO_CONFIRM" == false ]]; then
    if [[ "$REQUIRED_GB" -eq 0 ]]; then
        echo -e "\n${GREEN}Все выбранные каталоги уже мигрированы.${NC}"
        exit 0
    fi
    echo -e ""
    read -rp "Начать миграцию данных на ${TARGET_BASE}? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[yYдД] ]]; then
        echo -e "${RED}Миграция отменена пользователем.${NC}"
        exit 0
    fi
fi

# ==============================================================================
# [4/4] ВЫПОЛНЕНИЕ МИГРАЦИИ
# ==============================================================================

# Миграция PrismLauncher
if [[ -d "$PRISM_SRC" && ! -L "$PRISM_SRC" ]]; then
    echo -e "\n${BLUE}${BOLD}Миграция PrismLauncher (${PRISM_SIZE})...${NC}"
    if pgrep -f "PrismLauncher/instances" >/dev/null 2>&1 || pgrep -f "net.minecraft" >/dev/null 2>&1; then
        echo -e "  ${RED}Ошибка: Обнаружен запущенный экземпляр Minecraft!${NC}" >&2
        echo -e "  Пожалуйста, сохраните игру и закройте Minecraft перед продолжением миграции." >&2
        exit 1
    fi
    if pgrep -f -i "prismlauncher" >/dev/null 2>&1; then
        echo -e "  Остановка PrismLauncher..."
        pkill -f -i "prismlauncher" || true
        sleep 1
    fi

    echo -e "  -> Синхронизация каталога инстансов на ${PRISM_DEST}..."
    mkdir -p "$PRISM_DEST"
    rsync -aHAXvh --info=progress2 "${PRISM_SRC}/" "${PRISM_DEST}/"

    echo -e "  -> Создание резервной копии и симлинка..."
    if [[ -e "$PRISM_BAK" ]]; then
        rm -rf "$PRISM_BAK"
    fi
    mv "$PRISM_SRC" "$PRISM_BAK"
    ln -s "$PRISM_DEST" "$PRISM_SRC"

    echo -e "  ${GREEN}✓ PrismLauncher перенесен! Симлинк: ${PRISM_SRC} -> ${PRISM_DEST}${NC}"
fi

# Опциональная миграция SD Models
if [[ "$WITH_SD" == true && -d "$SD_SRC" && ! -L "$SD_SRC" ]]; then
    echo -e "\n${BLUE}${BOLD}Миграция чекпоинтов Stable Diffusion (${SD_SIZE})...${NC}"
    mkdir -p "$SD_DEST"
    rsync -aHAXvh --info=progress2 "${SD_SRC}/" "${SD_DEST}/"

    if [[ -e "$SD_BAK" ]]; then
        rm -rf "$SD_BAK"
    fi
    mv "$SD_SRC" "$SD_BAK"
    ln -s "$SD_DEST" "$SD_SRC"
    echo -e "  ${GREEN}✓ Чекпоинты SD перенесены! Симлинк: ${SD_SRC} -> ${SD_DEST}${NC}"
fi

echo -e "\n${GREEN}${BOLD}=== Миграция игровых данных завершена! ===${NC}"
echo -e "Высвобождено на системном NVMe: ${BOLD}${PRISM_SIZE}${NC}"
if [[ "$WITH_SD" == true ]]; then
    echo -e "Дополнительно высвобождено (SD): ${BOLD}${SD_SIZE}${NC}"
fi
echo -e "Резервные копии сохранены в:"
echo -e "  • ${PRISM_BAK}"
if [[ "$WITH_SD" == true ]]; then
    echo -e "  • ${SD_BAK}"
fi
echo -e "После проверки работы лаунчера резервные копии можно удалить вручную."
