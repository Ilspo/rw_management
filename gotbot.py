#!/bin/bash

# --- Конфигурация ---
KEYWORDS="xray remnawave remnanode 3x-ui marzban vless"
CONF_XRAY="/etc/xray/config.json"
CONF_REMNANODE="/etc/remnanode/config.yml"
CONF_WAVE="/opt/remnawave/docker-compose.yml"

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Проверка Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Ошибка: Docker не установлен!${NC}"
    exit 1
fi

# Функция поиска контейнеров
get_containers() {
    local filter=""
    for k in $KEYWORDS; do filter="$filter|$k"; done
    filter=${filter:1} # убираем первый символ |
    docker ps -a --format "{{.Names}} ({{.Status}})" | grep -Ei "$filter"
}

# Функция поиска по логам
global_search() {
    echo -ne "${YELLOW}Введите IP или UUID для поиска: ${NC}"
    read query
    if [ -z "$query" ]; then return; fi
    
    echo -e "${CYAN}Поиск по всем VPN-контейнерам...${NC}"
    local containers=$(docker ps --format "{{.Names}}" | grep -Ei "$(echo $KEYWORDS | tr ' ' '|')")
    
    for c in $containers; do
        results=$(docker logs --tail 1000 "$c" 2>&1 | grep -i "$query")
        if [ ! -z "$results" ]; then
            echo -e "${GREEN}>>> Найдено в $c:${NC}"
            echo "$results" | tail -n 5
            echo "-------------------"
        fi
    done
    echo -e "${YELLOW}Нажмите Enter...${NC}"
    read
}

# Меню управления конкретным контейнером
manage_container() {
    local name=$1
    while true; do
        clear
        echo -e "${CYAN}=== Управление: $name ===${NC}"
        status=$(docker inspect -f '{{.State.Status}}' "$name")
        echo -e "Статус: ${YELLOW}$status${NC}"
        echo "--------------------------"
        echo "1) Логи (Live)"
        echo "2) Перезапуск"
        echo "3) Остановить"
        echo "4) Запустить"
        echo "5) Редактировать конфиг"
        echo "0) Назад"
        echo -ne "${GREEN}Выбор: ${NC}"
        read act

        case $act in
            1) 
                echo -ne "${YELLOW}Фильтр (IP/UUID) или Enter: ${NC}"; read f
                docker logs -f --tail 100 "$name" 2>&1 | grep --color=always -i "$f"
                ;;
            2) docker restart "$name" ;;
            3) docker stop "$name" ;;
            4) docker start "$name" ;;
            5) 
                # Пытаемся угадать путь
                path=$CONF_XRAY
                [[ "$name" == *"remnanode"* ]] && path=$CONF_REMNANODE
                [[ "$name" == *"remnawave"* ]] && path=$CONF_WAVE
                nano "$path"
                ;;
            0) break ;;
        esac
    done
}

# Главный цикл
while true; do
    clear
    echo -e "${CYAN}=== GotBot VPN CLI (Bash Edition) ===${NC}"
    
    # Получаем список в массив
    IFS=$'\n' read -rd '' -a container_list <<< "$(get_containers)"
    
    if [ ${#container_list[@]} -eq 0 ]; then
        echo -e "${RED}VPN контейнеры не найдены!${NC}"
    else
        for i in "${!container_list[@]}"; do
            color=$RED
            [[ "${container_list[$i]}" == *"Up"* ]] && color=$GREEN
            printf "${CYAN}%2d)${NC} %s\n" "$((i+1))" "${color}${container_list[$i]}${NC}"
        done
    fi

    echo "-------------------------------------"
    echo -e "${YELLOW}s)${NC} Глобальный поиск по логам"
    echo -e "${YELLOW}q)${NC} Выход"
    echo "-------------------------------------"
    echo -ne "${GREEN}Выберите номер: ${NC}"
    read choice

    if [[ "$choice" == "q" ]]; then
        exit 0
    elif [[ "$choice" == "s" ]]; then
        global_search
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -le "${#container_list[@]}" ]; then
        # Вычленяем имя из строки "name (status)"
        c_name=$(echo "${container_list[$((choice-1))]}" | awk '{print $1}')
        manage_container "$c_name"
    fi
done
