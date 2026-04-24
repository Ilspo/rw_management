#!/bin/bash

# Цвета для красивого вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Проверка на root-права
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Ошибка: Пожалуйста, запустите скрипт с правами root (sudo)${NC}"
  exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}       Анализ дискового пространства    ${NC}"
echo -e "${GREEN}========================================${NC}\n"

# 1. Общее состояние диска
echo -e "${YELLOW}[*] Общее использование диска (/):${NC}"
df -h /
echo ""

# 2. Поиск самых тяжелых директорий в корне
echo -e "${YELLOW}[*] Топ-10 самых тяжелых директорий в корне (идет подсчет...):${NC}"
du -sh /* 2>/dev/null | sort -hr | head -n 10
echo ""

# 3. Поиск больших логов
echo -e "${YELLOW}[*] Топ-5 самых больших файлов логов в /var/log:${NC}"
find /var/log -type f -exec du -Sh {} + 2>/dev/null | sort -rh | head -n 5
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}       Предложения по очистке           ${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Функция для запроса подтверждения
prompt_clean() {
    while true; do
        read -p "$1 [y/N]: " response
        case "$response" in
            [yY][eE][sS]|[yY]) return 0 ;;
            [nN][oO]|[nN]|"") return 1 ;;
            *) echo "Пожалуйста, введите y (да) или n (нет)." ;;
        esac
    done
}

# --- ШАГ 1: Логи systemd (journalctl) ---
if prompt_clean "1. Очистить старые логи systemd (оставить только за последние 3 дня)?"; then
    echo -e "Очистка логов..."
    journalctl --vacuum-time=3d
    echo -e "${GREEN}✓ Логи очищены.${NC}\n"
else
    echo -e "Пропущено.\n"
fi

# --- ШАГ 2: Пакетный менеджер APT (для Debian/Ubuntu) ---
if command -v apt-get &> /dev/null; then
    if prompt_clean "2. Очистить кэш APT и удалить неиспользуемые зависимости (apt autoremove/clean)?"; then
        echo -e "Очистка APT..."
        apt-get clean
        apt-get autoremove -y
        echo -e "${GREEN}✓ Кэш APT очищен.${NC}\n"
    else
        echo -e "Пропущено.\n"
    fi
fi

# --- ШАГ 3: Docker Prune ---
if command -v docker &> /dev/null; then
    echo -e "${YELLOW}На сервере установлен Docker.${NC}"
    if prompt_clean "3. Выполнить 'docker system prune -a --volumes'? (ВНИМАНИЕ: Удалит все остановленные контейнеры, неиспользуемые сети, образы без тегов и тома!)"; then
        echo -e "Очистка Docker..."
        docker system prune -a --volumes -f
        echo -e "${GREEN}✓ Мусор Docker удален.${NC}\n"
    else
        echo -e "Пропущено.\n"
    fi
fi

# --- ШАГ 4: Временные файлы (/tmp) ---
if prompt_clean "4. Очистить содержимое временной директории /tmp?"; then
    echo -e "Очистка /tmp..."
    rm -rf /tmp/*
    echo -e "${GREEN}✓ Директория /tmp очищена.${NC}\n"
else
    echo -e "Пропущено.\n"
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}       Готово! Состояние после очистки  ${NC}"
echo -e "${GREEN}========================================${NC}\n"
df -h /
