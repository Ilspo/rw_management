#!/bin/bash

EDITOR=${EDITOR:-nano}
TMP_DIR="/tmp/remna-cli"
mkdir -p $TMP_DIR

# COLORS
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# GLOBAL ARRAYS
XRAY_CONTAINERS=()
PANEL_CONTAINERS=()

# ========= DETECT =========
detect_all() {
    XRAY_CONTAINERS=($(docker ps -a --format "{{.Names}}" | grep -Ei 'xray|remnanode|node'))
    PANEL_CONTAINERS=($(docker ps -a --format "{{.Names}}" | grep -Ei 'remnawave|panel'))
}

# ========= STATUS =========
status() {
    clear
    echo -e "${YELLOW}=== CONTAINERS ===${NC}"
    docker ps -a
    read -p "Enter to continue..."
}

# ========= LOG STREAM =========
logs_live() {
    detect_all

    CHOICE=$(printf "%s\n" "${XRAY_CONTAINERS[@]}" "${PANEL_CONTAINERS[@]}" | \
    dialog --menu "Select container logs" 20 60 10 2>&1 >/dev/tty)

    clear
    docker logs -f $CHOICE
}

# ========= SEARCH =========
search_logs() {
    read -p "Enter IP / UUID: " q

    echo -e "${GREEN}Searching...${NC}"

    for c in "${XRAY_CONTAINERS[@]}"; do
        docker logs $c 2>&1 | grep -i "$q"
    done

    for c in "${PANEL_CONTAINERS[@]}"; do
        docker logs $c 2>&1 | grep -i "$q"
    done
}

# ========= PARSE XRAY =========
parse_xray_logs() {
    FILE="$TMP_DIR/xray.log"
    > $FILE

    for c in "${XRAY_CONTAINERS[@]}"; do
        docker logs $c 2>&1 >> $FILE
    done

    echo -e "${GREEN}Parsing logs...${NC}"

    cat $FILE | grep -E "tcp|udp" | awk '
    {
        for(i=1;i<=NF;i++){
            if($i ~ /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/) ip=$i
            if($i ~ /[a-f0-9-]{36}/) uuid=$i
        }
        if(ip && uuid) print ip, uuid
    }' | sort | uniq -c | sort -nr | head -20
}

# ========= ABUSE DETECT =========
abuse_detect() {
    FILE="$TMP_DIR/xray.log"

    echo -e "${RED}Detecting abuse...${NC}"

    cat $FILE | awk '
    {
        for(i=1;i<=NF;i++){
            if($i ~ /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/) ip=$i
            if($i ~ /[a-f0-9-]{36}/) uuid=$i
        }
        if(ip && uuid) print uuid, ip
    }' | sort | uniq | awk '
    {
        map[$1]++
    }
    END {
        for (u in map) {
            if (map[u] > 3) {
                print "ABUSE:", u, "IPs:", map[u]
            }
        }
    }'
}

# ========= USER TRACE =========
user_trace() {
    read -p "Enter UUID/IP: " u

    for c in "${XRAY_CONTAINERS[@]}"; do
        echo -e "${GREEN}=== $c ===${NC}"
        docker logs $c 2>&1 | grep "$u"
    done
}

# ========= CONTAINER CONTROL =========
container_control() {
    NAME=$(docker ps -a --format "{{.Names}}" | \
    dialog --menu "Select container" 20 60 10 2>&1 >/dev/tty)

    ACTION=$(dialog --menu "Action" 15 50 5 \
    1 "Start" \
    2 "Stop" \
    3 "Restart" 2>&1 >/dev/tty)

    clear

    case $ACTION in
        1) docker start $NAME ;;
        2) docker stop $NAME ;;
        3) docker restart $NAME ;;
    esac

    echo "Done"
    sleep 1
}

# ========= CONFIG FIND =========
edit_configs() {
    FILE=$(find / -type f \( -name "*.json" -o -name "*.yml" \) \
    2>/dev/null | grep -Ei 'xray|remna|config' | \
    dialog --menu "Select config" 20 70 10 2>&1 >/dev/tty)

    clear
    $EDITOR "$FILE"
}

# ========= MULTI NODE =========
multi_node_logs() {
    echo -e "${YELLOW}Aggregating logs...${NC}"

    for c in "${XRAY_CONTAINERS[@]}"; do
        echo "=== $c ==="
        docker logs --tail 50 $c
    done
}

# ========= MAIN =========
while true; do
    detect_all

    CHOICE=$(dialog --clear --menu "REMNA CLI v2" 20 60 12 \
    1 "Containers status" \
    2 "Live logs" \
    3 "Search logs (IP/UUID)" \
    4 "User trace" \
    5 "Parse Xray logs (top users)" \
    6 "Detect abuse (multi-IP)" \
    7 "Multi-node logs" \
    8 "Container control" \
    9 "Edit configs" \
    0 "Exit" \
    2>&1 >/dev/tty)

    clear

    case $CHOICE in
        1) status ;;
        2) logs_live ;;
        3) search_logs ;;
        4) user_trace ;;
        5) parse_xray_logs ;;
        6) abuse_detect ;;
        7) multi_node_logs ;;
        8) container_control ;;
        9) edit_configs ;;
        0) clear; exit ;;
    esac
done
