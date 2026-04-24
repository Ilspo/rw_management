#!/bin/bash

# Цвета для красивого вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Проверка на root-права
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Ошибка: Пожалуйста, запустите скрипт с правами root (sudo)${NC}"
  exit 1
fi

echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}    Глубокий анализ дискового пространства          ${NC}"
echo -e "${GREEN}====================================================${NC}\n"

# 1. Общее состояние
echo -e "${YELLOW}[*] Общее использование диска (/):${NC}"
df -h /
echo ""

# 2. Поиск самых тяжелых директорий в корне
echo -e "${YELLOW}[*] Топ-10 самых тяжелых папок в корневой системе:${NC}"
echo -e "${CYAN}Подсказка: Обычно больше всего весит /var (логи и данные) или /usr (программы).${NC}"
du -sh /* 2>/dev/null | sort -hr | head -n 10
echo ""

# 3. Детальный анализ /var/lib (там живут Docker, containerd и БД)
echo -e "${YELLOW}[*] Топ-10 тяжелых папок в /var/lib (Данные сервисов):${NC}"
echo -e "${CYAN}Подсказка: Если здесь лидируют базы данных (mysql/prometheus), их нельзя чистить скриптом, нужно менять их настройки (retention). Если лидирует docker/containerd — чистка поможет.${NC}"
du -sh /var/lib/* 2>/dev/null | sort -hr | head -n 10
echo ""

# 4. Поиск больших логов
echo -e "${YELLOW}[*] Топ-5 самых больших файлов логов в /var/log:${NC}"
find /var/log -type f -exec du -Sh {} + 2>/dev/null | sort -rh | head -n 5
echo ""

echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}    Интерактивная очистка (с пояснениями)           ${NC}"
echo -e "${GREEN}====================================================${NC}\n"

# Функция для запроса подтверждения
prompt_clean() {
    while true; do
        read -p "$(echo -e ${YELLOW}"$1 [y/N]: "${NC})" response
        case "$response" in
            [yY][eE][sS]|[yY]) return 0 ;;
            [nN][oO]|[nN]|"") return 1 ;;
            *) echo "Пожалуйста, введите y (да) или n (нет)." ;;
        esac
    done
}

# --- ШАГ 1: Логи systemd (journalctl) ---
echo -e "${CYAN}ℹ️  ШАГ 1: Системные логи (journald)${NC}"
echo "Пояснение: Служба systemd записывает логи работы всех программ на сервере."
echo "Со временем эти журналы могут разрастись до нескольких гигабайт."
echo "Действие: Удаление логов старше 3 дней. Это абсолютно безопасно."
if prompt_clean "? Выполнить очистку старых логов systemd?"; then
    echo -e "Очистка логов..."
    journalctl --vacuum-time=3d
    echo -e "${GREEN}✓ Логи очищены.${NC}\n"
else
    echo -e "Пропущено.\n"
fi

# --- ШАГ 2: Пакетный менеджер APT ---
if command -v apt-get &> /dev/null; then
    echo -e "${CYAN}ℹ️  ШАГ 2: Кэш пакетов APT${NC}"
    echo "Пояснение: При установке программ Linux сохраняет их установочные файлы (.deb)."
    echo "Также остаются 'сироты' — зависимости удаленных программ, которые больше не нужны."
    echo "Действие: Очистка кэша и удаление неиспользуемых зависимостей. Безопасно."
    if prompt_clean "? Очистить кэш APT и старые пакеты?"; then
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
    echo -e "${CYAN}ℹ️  ШАГ 3: Глобальная очистка Docker${NC}"
    echo "Пояснение: Docker не удаляет старые образы и остановленные контейнеры сам."
    echo "Они копятся мертвым грузом в /var/lib/docker."
    echo -e "${RED}ВНИМАНИЕ: Команда удалит ВСЕ остановленные контейнеры, неиспользуемые сети и тома без контейнеров!${NC}"
    if prompt_clean "? Выполнить полную очистку Docker (docker system prune -a --volumes)?"; then
        echo -e "Очистка Docker..."
        docker system prune -a --volumes -f
        echo -e "${GREEN}✓ Мусор Docker удален.${NC}\n"
    else
        echo -e "Пропущено.\n"
    fi
fi

# --- ШАГ 4: Кэш Containerd ---
if [ -d "/var/lib/containerd" ]; then
    echo -e "${CYAN}ℹ️  ШАГ 4: Кэш среды containerd${NC}"
    echo "Пояснение: Containerd — это движок, работающий под Docker. В /var/lib/containerd"
    echo "часто застревают кэши слоев, которые не удаляются обычным docker prune."
    echo -e "${RED}ВНИМАНИЕ: Это потребует кратковременной остановки Docker. Ваши сайты/сервисы на пару секунд 'моргнут'.${NC}"
    if prompt_clean "? Остановить Docker и жестко очистить кэш containerd?"; then
        echo -e "Перезапуск Docker и очистка кэша containerd..."
        systemctl stop docker
        rm -rf /var/lib/containerd/*
        systemctl start docker
        echo -e "${GREEN}✓ Кэш containerd сброшен.${NC}\n"
    else
        echo -e "Пропущено.\n"
    fi
fi

# --- ШАГ 5: Временные файлы (/tmp) ---
echo -e "${CYAN}ℹ️  ШАГ 5: Временная папка /tmp${NC}"
echo "Пояснение: Здесь программы хранят временные файлы. Обычно папка чистится при перезагрузке,"
echo "но на серверах с высоким аптаймом она может забиться."
echo "Действие: Удаление содержимого /tmp. В редких случаях может сбросить текущие сессии некоторых программ."
if prompt_clean "? Очистить временную директорию /tmp?"; then
    echo -e "Очистка /tmp..."
    rm -rf /tmp/*
    echo -e "${GREEN}✓ Директория /tmp очищена.${NC}\n"
else
    echo -e "Пропущено.\n"
fi

echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}    Готово! Состояние после очистки                 ${NC}"
echo -e "${GREEN}====================================================${NC}\n"
df -h /
