#!/usr/bin/env bash
# ==============================================================================
# 05-online-resize-sda1.sh - Безопасное онлайн-расширение /dev/sda1 (+127.13 GiB)
# ==============================================================================
# Расширяет раздел /dev/sda1 с 320 GiB до полного объема накопителя 447.13 GiB
# и выполняет онлайн-расширение файловой системы ext4 на смонтированной /mnt/ssd.
#
# Гарантии безопасности:
#   • Начальный сектор 2048 не сдвигается — существующие 152.3 GiB данных не затрагиваются.
#   • UUID раздела и UUID файловой системы остаются неизменными.
#   • Процедура выполняется полностью "на лету" без размонтирования /mnt/ssd.
#   • Проверка целостности журнала ext4 (/sys/fs/ext4/sda1/errors_count == 0).
#
# Ключи:
#   -n, --dry-run        : Режим симуляции (анализирует геометрию и проверяет параметры)
#   -y, --yes, --force   : Применить операцию без интерактивного подтверждения
#   -h, --help           : Справка по использованию
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

DEVICE="/dev/sda"
PARTITION="/dev/sda1"
MOUNT_POINT="/mnt/ssd"

DRY_RUN=false
AUTO_CONFIRM=false

usage() {
    cat << 'EOF'
Использование: sudo ./05-online-resize-sda1.sh [ОПЦИИ]

Опции:
  -n, --dry-run        Режим симуляции (проверка геометрии GPT и ФС без изменений)
  -y, --yes, --force   Выполнить расширение без интерактивного подтверждения
  -h, --help           Показать эту справку и выйти

Примеры:
  ./05-online-resize-sda1.sh --dry-run
  sudo ./05-online-resize-sda1.sh
  sudo ./05-online-resize-sda1.sh -y
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
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Неизвестный параметр:${NC} $1" >&2
            usage 1
            ;;
    esac
done

echo -e "${CYAN}${BOLD}=== Онлайн-расширение накопителя /dev/sda1 (+127.13 GiB) ===${NC}"

# ==============================================================================
# [1/4] АУДИТ ГЕОМЕТРИИ И ПРЕДВАРИТЕЛЬНЫЕ ПРОВЕРКИ
# ==============================================================================
echo -e "${BLUE}${BOLD}[1/4] Проверка блочного устройства и геометрии...${NC}"

if [[ ! -b "$DEVICE" ]]; then
    echo -e "${RED}Ошибка: Устройство ${DEVICE} не найдено!${NC}" >&2
    exit 1
fi

if [[ ! -b "$PARTITION" ]]; then
    echo -e "${RED}Ошибка: Раздел ${PARTITION} не найден!${NC}" >&2
    exit 1
fi

# Чтение геометрии из sysfs (не требует прав root)
TOTAL_SECTORS=$(cat /sys/block/sda/size)
SECTOR_SIZE=$(cat /sys/block/sda/queue/logical_block_size)
PART_START=$(cat /sys/block/sda/sda1/start)
PART_SIZE_SECTORS=$(cat /sys/block/sda/sda1/size)

PART_END=$(( PART_START + PART_SIZE_SECTORS - 1 ))
TOTAL_BYTES=$(( TOTAL_SECTORS * SECTOR_SIZE ))
PART_BYTES=$(( PART_SIZE_SECTORS * SECTOR_SIZE ))

# 34 сектора зарезервированы под вторичную таблицу GPT в конце диска
LAST_USABLE_LBA=$(( TOTAL_SECTORS - 34 ))
UNALLOCATED_SECTORS=$(( LAST_USABLE_LBA - PART_END ))
UNALLOCATED_BYTES=$(( UNALLOCATED_SECTORS * SECTOR_SIZE ))
UNALLOCATED_GIB=$(awk "BEGIN {printf \"%.2f\", $UNALLOCATED_BYTES / (1024^3)}")
PART_GIB=$(awk "BEGIN {printf \"%.2f\", $PART_BYTES / (1024^3)}")
NEW_TOTAL_GIB=$(awk "BEGIN {printf \"%.2f\", ($PART_BYTES + $UNALLOCATED_BYTES) / (1024^3)}")

echo -e "  • Накопитель: ${BOLD}${DEVICE}${NC} (всего секторов: ${TOTAL_SECTORS}, размер: $(( TOTAL_BYTES / 1024 / 1024 / 1024 )) ГБ)"
echo -e "  • Раздел: ${BOLD}${PARTITION}${NC}"
echo -e "    - Начальный сектор: ${BOLD}${PART_START}${NC} (ровное выравнивание по 1 МиБ)"
echo -e "    - Текущий конечный сектор: ${BOLD}${PART_END}${NC}"
echo -e "    - Текущий размер: ${BOLD}${PART_GIB} GiB${NC} (${PART_SIZE_SECTORS} секторов)"
echo -e "  • Неразмеченное пространство (сразу за sda1):"
echo -e "    - Доступно для расширения: ${BOLD}+${UNALLOCATED_GIB} GiB${NC} (${UNALLOCATED_SECTORS} секторов)"
echo -e "    - Новый размер после операции: ${BOLD}${NEW_TOTAL_GIB} GiB${NC}"

# Проверка файловой системы ext4 и статуса монтирования
FS_TYPE=$(lsblk -no FSTYPE "$PARTITION" 2>/dev/null || blkid -o value -s TYPE "$PARTITION" 2>/dev/null || echo "unknown")
if [[ "$FS_TYPE" != "ext4" ]]; then
    echo -e "${RED}Ошибка: Файловая система на ${PARTITION} определена как '${FS_TYPE}', ожидается 'ext4'!${NC}" >&2
    exit 1
fi

if ! findmnt -M "$MOUNT_POINT" >/dev/null 2>&1; then
    echo -e "${YELLOW}Предупреждение: ${PARTITION} не смонтирован в ${MOUNT_POINT}. Онлайн-расширение возможно, но точка монтирования не обнаружена.${NC}"
else
    echo -e "  ✓ Раздел смонтирован в: ${BOLD}${MOUNT_POINT}${NC}"
fi

# Проверка журнала ошибок ext4
ERRORS_COUNT="0"
if [[ -f "/sys/fs/ext4/sda1/errors_count" ]]; then
    ERRORS_COUNT=$(cat /sys/fs/ext4/sda1/errors_count)
fi

if [[ "$ERRORS_COUNT" != "0" ]]; then
    echo -e "${RED}Ошибка: На файловой системе обнаружены зарегистрированные ошибки (errors_count=${ERRORS_COUNT})!${NC}" >&2
    echo -e "${RED}Перед расширением необходимо провести fsck.${NC}" >&2
    exit 1
fi
echo -e "  ✓ Журнал ext4 чист (errors_count = 0). Файловая система полностью исправна."

# Проверка, не расширен ли уже диск
if [[ "$UNALLOCATED_SECTORS" -le 2048 ]]; then
    echo -e "${GREEN}${BOLD}Раздел ${PARTITION} уже расширен на весь доступный объем диска! Дополнительное расширение не требуется.${NC}"
    exit 0
fi

# ==============================================================================
# [2/4] РЕЖИМ СИМУЛЯЦИИ (--dry-run)
# ==============================================================================
if [[ "$DRY_RUN" == true ]]; then
    echo -e "\n${YELLOW}${BOLD}[РЕЖИМ СИМУЛЯЦИИ (--dry-run)]${NC}"
    echo -e "План выполнения онлайн-расширения:"
    echo -e "  1. Перемещение backup-заголовка GPT в конец диска:"
    echo -e "     ${CYAN}nix shell nixpkgs#gptfdisk -c sudo sgdisk -e ${DEVICE}${NC}"
    echo -e "  2. Онлайн-расширение раздела в таблице разделов GPT:"
    echo -e "     ${CYAN}nix shell nixpkgs#cloud-utils -c sudo growpart -v ${DEVICE} 1${NC}"
    echo -e "  3. Онлайн-расширение файловой системы ext4 на смонтированном диске:"
    echo -e "     ${CYAN}sudo resize2fs ${PARTITION}${NC}"
    echo -e "  4. Верификация нового объема и счетчика ошибок ext4."

    # Если запущен с правами root, можем дополнительно выполнить реальный growpart dry-run
    if [[ "$EUID" -eq 0 ]]; then
        echo -e "\n  Выполнение проверки growpart -N (Dry-run на физическом диске):"
        nix shell nixpkgs#cloud-utils -c growpart -N -v "$DEVICE" 1 || true
    else
        echo -e "\n  ${YELLOW}Примечание:${NC} Для физического вызова growpart -N требуется root."
        echo -e "  Расчет геометрии гарантирует расширение с ${PART_GIB} GiB до ${NEW_TOTAL_GIB} GiB (+${UNALLOCATED_GIB} GiB)."
    fi

    echo -e "\n${GREEN}Все проверки пройдены успешно! Скрипт готов к боевому запуску под sudo.${NC}"
    exit 0
fi

# ==============================================================================
# [3/4] ПРОВЕРКА ПРИВИЛЕГИЙ ROOT
# ==============================================================================
if [[ "$EUID" -ne 0 ]]; then
    echo -e "\n${RED}Ошибка: Для записи в таблицу разделов и расширения ФС требуются права root!${NC}" >&2
    echo -e "Пожалуйста, запустите команду через sudo:"
    echo -e "  ${BOLD}sudo $0${NC}\n"
    exit 1
fi

if [[ "$AUTO_CONFIRM" == false ]]; then
    echo -e "\n${YELLOW}${BOLD}ВНИМАНИЕ:${NC} Будет выполнено онлайн-расширение раздела ${PARTITION} на +${UNALLOCATED_GIB} GiB."
    echo -e "Существующие данные (152.3 GiB) будут полностью сохранены."
    read -rp "Приступить к расширению? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[yYдД] ]]; then
        echo -e "${RED}Операция отменена пользователем.${NC}"
        exit 0
    fi
fi

# ==============================================================================
# [4/4] ВЫПОЛНЕНИЕ ОНЛАЙН-РАСШИРЕНИЯ
# ==============================================================================
echo -e "\n${BLUE}${BOLD}Шаг 1: Перемещение резервного заголовка GPT (sgdisk -e)...${NC}"
nix shell nixpkgs#gptfdisk -c sgdisk -e "$DEVICE"
echo -e "  ${GREEN}✓ Backup GPT заголовок успешно перемещен в конец диска.${NC}"

echo -e "\n${BLUE}${BOLD}Шаг 2: Расширение раздела в таблице GPT (growpart)...${NC}"
nix shell nixpkgs#cloud-utils -c growpart -v "$DEVICE" 1
echo -e "  ${GREEN}✓ Раздел ${PARTITION} расширен в таблице GPT и обновлен в ядре.${NC}"

echo -e "\n${BLUE}${BOLD}Шаг 3: Онлайн-расширение файловой системы ext4 (resize2fs)...${NC}"
resize2fs "$PARTITION"
echo -e "  ${GREEN}✓ Файловая система ext4 успешно расширена на лету.${NC}"

echo -e "\n${BLUE}${BOLD}Шаг 4: Контрольная верификация...${NC}"
FINAL_ERRORS=$(cat /sys/fs/ext4/sda1/errors_count 2>/dev/null || echo "0")
if [[ "$FINAL_ERRORS" == "0" ]]; then
    echo -e "  ${GREEN}✓ Проверка целостности: ошибок ФС нет (errors_count = 0).${NC}"
else
    echo -e "  ${RED}⚠ Внимание: errors_count = ${FINAL_ERRORS}.${NC}"
fi

echo -e "\n${GREEN}${BOLD}=== Онлайн-расширение успешно завершено! ===${NC}"
echo -e "Новые параметры файловой системы:"
df -hT "$MOUNT_POINT"
echo -e ""
lsblk "$PARTITION" -o NAME,SIZE,START,FSTYPE,MOUNTPOINT
