#!/usr/bin/env bash
# ==============================================================================
# 03-migrate-ollama.sh - Миграция моделей Ollama (19.0 ГБ) на вторичный SSD (/mnt/ssd)
# ==============================================================================
# Переносит каталог ~/.ollama на быстрый SATA SSD (/mnt/ssd/ollama)
# Реализует двухуровневое перенаправление:
#   1. Файловый симлинк: ~/.ollama -> /mnt/ssd/ollama
#   2. Переменная окружения: OLLAMA_MODELS=/mnt/ssd/ollama/models
#      (в systemd юните ~/.config/systemd/user/ollama.service и в обертке ~/.local/bin/ollama)
#
# Ключи:
#   -n, --dry-run        : Режим симуляции (проверяет место, статус сервиса, показывает команды)
#   -y, --yes, --force   : Применить миграцию без интерактивных подтверждений
#   --rollback           : Откат миграции из резервной копии ~/.ollama.bak
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

SOURCE_DIR="/home/spike/.ollama"
TARGET_BASE="/mnt/ssd"
TARGET_DIR="/mnt/ssd/ollama"
BACKUP_DIR="/home/spike/.ollama.bak"
SERVICE_FILE="/home/spike/.config/systemd/user/ollama.service"
WRAPPER_FILE="/home/spike/.local/bin/ollama"

DRY_RUN=false
AUTO_CONFIRM=false
DO_ROLLBACK=false

usage() {
    cat << 'EOF'
Использование: ./03-migrate-ollama.sh [ОПЦИИ]

Опции:
  -n, --dry-run        Режим симуляции (без изменений в файловой системе и сервисах)
  -y, --yes, --force   Выполнить миграцию без запроса подтверждения
  --rollback           Откатить миграцию, восстановив ~/.ollama из ~/.ollama.bak
  -h, --help           Показать эту справку и выйти

Примеры:
  ./03-migrate-ollama.sh --dry-run
  ./03-migrate-ollama.sh -y
  ./03-migrate-ollama.sh --rollback
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

echo -e "${CYAN}${BOLD}=== Скрипт миграции каталога моделей Ollama на /mnt/ssd ===${NC}"

# ==============================================================================
# ПРОЦЕДУРА ОТКАТА (ROLLBACK)
# ==============================================================================
if [[ "$DO_ROLLBACK" == true ]]; then
    echo -e "${YELLOW}${BOLD}Инициирован процесс отката миграции (Rollback)...${NC}"
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        echo -e "${RED}Ошибка: Резервная копия ${BACKUP_DIR} не найдена! Невозможно выполнить откат.${NC}" >&2
        exit 1
    fi

    echo -e "  -> Остановка ollama.service..."
    systemctl --user stop ollama.service || true

    echo -e "  -> Удаление симлинка ${SOURCE_DIR}..."
    if [[ -L "$SOURCE_DIR" ]]; then
        rm -f "$SOURCE_DIR"
    fi

    echo -e "  -> Восстановление каталога из резервной копии ${BACKUP_DIR}..."
    mv "$BACKUP_DIR" "$SOURCE_DIR"

    # Восстановление конфигурации сервиса
    if [[ -f "${SERVICE_FILE}.bak" ]]; then
        echo -e "  -> Восстановление исходного ${SERVICE_FILE}..."
        cp -f "${SERVICE_FILE}.bak" "$SERVICE_FILE"
    elif [[ -f "$SERVICE_FILE" ]]; then
        sed -i '/Environment="OLLAMA_MODELS=/d' "$SERVICE_FILE"
    fi

    # Восстановление обертки
    if [[ -f "${WRAPPER_FILE}.bak" ]]; then
        echo -e "  -> Восстановление исходного ${WRAPPER_FILE}..."
        cp -f "${WRAPPER_FILE}.bak" "$WRAPPER_FILE"
    elif [[ -f "$WRAPPER_FILE" ]]; then
        sed -i '/export OLLAMA_MODELS=/d' "$WRAPPER_FILE"
    fi

    echo -e "  -> Перезапуск systemd и ollama.service..."
    systemctl --user daemon-reload
    systemctl --user start ollama.service

    echo -e "${GREEN}${BOLD}✓ Откат успешно завершен! Модели возвращены в исходное состояние.${NC}"
    exit 0
fi

# ==============================================================================
# ПРЕДВАРИТЕЛЬНЫЕ ПРОВЕРКИ (PRE-FLIGHT CHECKS)
# ==============================================================================
echo -e "${BLUE}${BOLD}[1/5] Предварительные проверки (Pre-flight checks)...${NC}"

# 1. Проверка монтирования /mnt/ssd
if ! findmnt "$TARGET_BASE" >/dev/null 2>&1; then
    echo -e "${RED}Ошибка: Накопитель ${TARGET_BASE} не смонтирован!${NC}" >&2
    exit 1
fi
echo -e "  ✓ Точка монтирования ${TARGET_BASE} активна."

# 2. Проверка исходного каталога ~/.ollama
if [[ -L "$SOURCE_DIR" ]]; then
    TARGET_OF_LINK="$(readlink -f "$SOURCE_DIR")"
    if [[ "$TARGET_OF_LINK" == "$TARGET_DIR" ]]; then
        echo -e "  ${GREEN}✓ Каталог ${SOURCE_DIR} уже является симлинком на ${TARGET_DIR}! Миграция уже выполнена.${NC}"
        ollama list || true
        exit 0
    else
        echo -e "  ${YELLOW}Предупреждение: ${SOURCE_DIR} уже является симлинком на ${TARGET_OF_LINK}.${NC}"
    fi
elif [[ ! -d "$SOURCE_DIR" ]]; then
    echo -e "${RED}Ошибка: Каталог ${SOURCE_DIR} не существует!${NC}" >&2
    exit 1
fi

SOURCE_SIZE="$(du -sh "$SOURCE_DIR" | awk '{print $1}')"
echo -e "  ✓ Исходный каталог ${SOURCE_DIR} найден (размер: ${BOLD}${SOURCE_SIZE}${NC})."

# 3. Проверка свободного места на /mnt/ssd (требуется >= 25 ГБ)
AVAIL_KB=$(df -P "$TARGET_BASE" | awk 'NR==2 {print $4}')
AVAIL_GB=$(( AVAIL_KB / 1024 / 1024 ))
echo -e "  ✓ Доступно на ${TARGET_BASE}: ${BOLD}${AVAIL_GB} ГБ${NC}"

if [[ "$AVAIL_GB" -lt 25 ]]; then
    echo -e "${RED}Ошибка: Недостаточно свободного места на ${TARGET_BASE} (${AVAIL_GB} ГБ, требуется минимум 25 ГБ).${NC}" >&2
    exit 1
fi

# 4. Проверка статуса сервиса Ollama
SERVICE_WAS_ACTIVE=false
if systemctl --user is-active ollama.service >/dev/null 2>&1; then
    SERVICE_WAS_ACTIVE=true
    echo -e "  ✓ Сервис ollama.service активен и будет остановлен перед синхронизацией."
else
    echo -e "  ✓ Сервис ollama.service в данный момент остановлен."
fi

# ==============================================================================
# ПОДТВЕРЖДЕНИЕ
# ==============================================================================
if [[ "$DRY_RUN" == true ]]; then
    echo -e "\n${YELLOW}${BOLD}[РЕЖИМ СИМУЛЯЦИИ (--dry-run)]${NC}"
    echo -e "Будут выполнены следующие действия:"
    echo -e "  1. systemctl --user stop ollama.service"
    echo -e "  2. mkdir -p ${TARGET_DIR}"
    echo -e "  3. rsync -aHAXvh --info=progress2 ${SOURCE_DIR}/ ${TARGET_DIR}/"
    echo -e "  4. mv ${SOURCE_DIR} ${BACKUP_DIR}"
    echo -e "  5. ln -s ${TARGET_DIR} ${SOURCE_DIR}"
    echo -e "  6. Добавление Environment=\"OLLAMA_MODELS=${TARGET_DIR}/models\" в ${SERVICE_FILE}"
    echo -e "  7. Добавление export OLLAMA_MODELS=\"${TARGET_DIR}/models\" в ${WRAPPER_FILE}"
    echo -e "  8. systemctl --user daemon-reload && systemctl --user start ollama.service"
    echo -e "  9. Тестовая верификация через 'ollama list'"
    echo -e "\n${GREEN}Все предварительные проверки пройдены успешно. Запустите без ключа --dry-run для применения.${NC}"
    exit 0
fi

if [[ "$AUTO_CONFIRM" == false ]]; then
    echo -e ""
    read -rp "Начать миграцию ${SOURCE_SIZE} моделей Ollama на ${TARGET_DIR}? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[yYдД] ]]; then
        echo -e "${RED}Миграция отменена пользователем.${NC}"
        exit 0
    fi
fi

# ==============================================================================
# ВЫПОЛНЕНИЕ МИГРАЦИИ
# ==============================================================================
echo -e "\n${BLUE}${BOLD}[2/5] Остановка сервиса Ollama...${NC}"
if [[ "$SERVICE_WAS_ACTIVE" == true ]]; then
    systemctl --user stop ollama.service
    sleep 1
fi
pkill -f "ollama serve" || true
echo -e "  ${GREEN}✓ Сервис Ollama остановлен.${NC}"

echo -e "\n${BLUE}${BOLD}[3/5] Синхронизация данных на /mnt/ssd...${NC}"
mkdir -p "$TARGET_DIR"

# Копирование с сохранением прав, расширенных атрибутов и прогрессом
rsync -aHAXvh --info=progress2 "${SOURCE_DIR}/" "${TARGET_DIR}/"
echo -e "  ${GREEN}✓ Данные успешно синхронизированы в ${TARGET_DIR}.${NC}"

echo -e "\n${BLUE}${BOLD}[4/5] Переключение ссылок и настройка окружения...${NC}"

# Атомарное перемещение оригинала в бэкап и создание симлинка
if [[ -e "$BACKUP_DIR" ]]; then
    rm -rf "$BACKUP_DIR"
fi
mv "$SOURCE_DIR" "$BACKUP_DIR"
ln -s "$TARGET_DIR" "$SOURCE_DIR"
echo -e "  ${GREEN}✓ Создан симлинк: ${SOURCE_DIR} -> ${TARGET_DIR}${NC}"
echo -e "  ${CYAN}✓ Исходный каталог временно сохранен в ${BACKUP_DIR}${NC}"

# Настройка systemd-сервиса (слой 2)
if [[ -f "$SERVICE_FILE" ]]; then
    cp -f "$SERVICE_FILE" "${SERVICE_FILE}.bak"
    if ! grep -q "OLLAMA_MODELS" "$SERVICE_FILE"; then
        sed -i '/\[Service\]/a Environment="OLLAMA_MODELS='"$TARGET_DIR"'/models"' "$SERVICE_FILE"
        echo -e "  ${GREEN}✓ OLLAMA_MODELS добавлен в ${SERVICE_FILE}.${NC}"
    fi
fi

# Настройка скрипта-обертки
if [[ -f "$WRAPPER_FILE" ]]; then
    cp -f "$WRAPPER_FILE" "${WRAPPER_FILE}.bak"
    if ! grep -q "OLLAMA_MODELS" "$WRAPPER_FILE"; then
        sed -i '/export OLLAMA_KV_CACHE_TYPE/a export OLLAMA_MODELS="'"$TARGET_DIR"'/models"' "$WRAPPER_FILE"
        echo -e "  ${GREEN}✓ export OLLAMA_MODELS добавлен в ${WRAPPER_FILE}.${NC}"
    fi
fi

# ==============================================================================
# ВЕРИФИКАЦИЯ
# ==============================================================================
echo -e "\n${BLUE}${BOLD}[5/5] Перезапуск и верификация сервиса...${NC}"
systemctl --user daemon-reload
systemctl --user start ollama.service

echo -e "  -> Ожидание готовности сервиса и сокета Ollama (до 10 сек)..."
OLLAMA_READY=false
for _ in {1..10}; do
    if systemctl --user is-active ollama.service >/dev/null 2>&1 && ollama list >/dev/null 2>&1; then
        OLLAMA_READY=true
        break
    fi
    sleep 1
done

if [[ "$OLLAMA_READY" == false ]]; then
    if ! systemctl --user is-active ollama.service >/dev/null 2>&1; then
        echo -e "${RED}Ошибка: ollama.service не запустился после миграции!${NC}" >&2
    else
        echo -e "${RED}Ошибка: Сервис ollama.service активен, но сокет API не отвечает вовремя!${NC}" >&2
    fi
    echo -e "${YELLOW}Выполняется автоматический откат...${NC}"
    "$0" --rollback
    exit 1
fi

echo -e "  ${GREEN}✓ ollama.service успешно запущен и сокет готов к работе.${NC}"
echo -e "  Проверка доступных моделей:"
ollama list

echo -e "\n${GREEN}${BOLD}=== Миграция Ollama успешно завершена! ===${NC}"
echo -e "Высвобождено на системном накопителе NVMe: ${BOLD}${SOURCE_SIZE}${NC}"
echo -e "Резервная копия сохранена в: ${BOLD}${BACKUP_DIR}${NC}"
echo -e "После окончательной проверки удалите резервную копию командой:"
echo -e "  ${CYAN}rm -rf ${BACKUP_DIR}${NC}"
