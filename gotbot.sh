#!/bin/bash

# ========= CONFIG =========
EDITOR=${EDITOR:-nano}

# ========= COLORS =========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ========= FUNCTIONS =========

detect_containers() {
    XRAY=$(docker ps -a --format "{{.Names}}" | grep -Ei 'xray|remnanode|node' | head -n1)
    PANEL=$(docker ps -a --format "{{.Names}}" | grep -Ei 'remnawave|panel' | head -n1)
    DB=$(docker ps -a --format "{{.Names}}" | grep -Ei 'postgres|db' | head -n1)
}

status() {
    echo -e "${YELLOW}=== CONTAINERS STATUS ===${NC}"
    docker ps -a
}

logs_menu() {
    echo "1) Xray logs"
    echo "2) Panel logs"
    echo "3) All logs"
    read -p "Select: " opt

    case $opt in
        1) docker logs -f $XRAY ;;
        2) docker logs -f $PANEL ;;
        3) docker logs -f $XRAY & docker logs -f $PANEL ;;
    esac
}

search_logs() {
    read -p "Enter IP or UUID: " query
    echo -e "${GREEN}Searching logs...${NC}"

    docker logs $XRAY 2>&1 | grep -i "$query"
    docker logs $PANEL 2>&1 | grep -i "$query"
}

container_control() {
    echo "1) Start"
    echo "2) Stop"
    echo "3) Restart"
    read -p "Action: " act

    read -p "Container name: " cname

    case $act in
        1) docker start $cname ;;
        2) docker stop $cname ;;
        3) docker restart $cname ;;
    esac
}

edit_configs() {
    echo -e "${YELLOW}Searching config files...${NC}"

    FILE=$(find / -type f \( -name "*.json" -o -name "*.yml" \) 2>/dev/null | grep -Ei 'xray|remna|config' | head -n 10)

    echo "$FILE"
    echo "Enter full path:"
    read path

    $EDITOR "$path"
}

user_trace() {
    read -p "Enter UUID or IP: " user

    echo -e "${GREEN}=== XRAY ===${NC}"
    docker logs $XRAY 2>&1 | grep "$user"

    echo -e "${GREEN}=== PANEL ===${NC}"
    docker logs $PANEL 2>&1 | grep "$user"
}

auto_info() {
    echo -e "${GREEN}Detected:${NC}"
    echo "Xray: $XRAY"
    echo "Panel: $PANEL"
    echo "DB: $DB"
}

# ========= MAIN =========

detect_containers

while true; do
    echo ""
    echo -e "${YELLOW}==== XRAY CLI TOOL ==== ${NC}"
    echo "1) Containers status"
    echo "2) Logs"
    echo "3) Search in logs (IP/UUID)"
    echo "4) User trace"
    echo "5) Container control"
    echo "6) Edit configs"
    echo "7) Auto detected info"
    echo "0) Exit"

    read -p "Select: " choice

    case $choice in
        1) status ;;
        2) logs_menu ;;
        3) search_logs ;;
        4) user_trace ;;
        5) container_control ;;
        6) edit_configs ;;
        7) auto_info ;;
        0) exit ;;
    esac
done
