#!/usr/bin/env bash

set -euo pipefail

VERSION="2.1"

# ========= CONFIG =========
EDITOR=${EDITOR:-nano}
TMP="/tmp/remna-cli"
mkdir -p "$TMP"

# ========= COLORS =========
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

# ========= UTILS =========
log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err() { echo -e "${RED}[x]${NC} $1"; }

pause() { read -rp "Press Enter..."; }

# ========= DEPENDENCIES =========
install_deps() {
    local deps=(docker jq dialog)
    for d in "${deps[@]}"; do
        if ! command -v "$d" &>/dev/null; then
            warn "$d not found, installing..."
            apt-get update -y >/dev/null
            apt-get install -y "$d" >/dev/null
        fi
    done
}

# ========= DETECT =========
detect() {
    XRAY=($(docker ps --format "{{.Names}}" | grep -Ei 'xray|remnanode|node' || true))
    PANEL=($(docker ps --format "{{.Names}}" | grep -Ei 'remnawave|panel' || true))

    [[ ${#XRAY[@]} -eq 0 ]] && warn "Xray container not found"
}

pick_container() {
    local list=("$@")
    printf "%s\n" "${list[@]}" | dialog --menu "Select container" 20 60 10 2>&1 >/dev/tty
}

# ========= LOGS =========
logs_live() {
    detect
    local c
    c=$(pick_container "${XRAY[@]}" "${PANEL[@]}")
    clear
    log "Streaming logs: $c"
    docker logs -f "$c"
}

logs_search() {
    detect
    read -rp "Enter IP / UUID: " q
    log "Searching..."

    for c in "${XRAY[@]}" "${PANEL[@]}"; do
        echo -e "${BLUE}=== $c ===${NC}"
        docker logs "$c" 2>&1 | grep -i --color=always "$q" || true
    done

    pause
}

# ========= PARSER =========
collect_logs() {
    local file="$TMP/xray.log"
    : > "$file"

    for c in "${XRAY[@]}"; do
        docker logs "$c" 2>&1 >> "$file"
    done

    echo "$file"
}

top_ips() {
    detect
    local file
    file=$(collect_logs)

    log "Top IPs:"
    grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' "$file" \
        | sort | uniq -c | sort -nr | head -20

    pause
}

top_users() {
    detect
    local file
    file=$(collect_logs)

    log "Top UUID:"
    grep -Eo '[a-f0-9-]{36}' "$file" \
        | sort | uniq -c | sort -nr | head -20

    pause
}

# ========= ABUSE =========
abuse_detect() {
    detect
    local file
    file=$(collect_logs)

    log "Detecting multi-IP users..."

    awk '
    {
        for(i=1;i<=NF;i++){
            if($i ~ /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/) ip=$i
            if($i ~ /[a-f0-9-]{36}/) uuid=$i
        }
        if(ip && uuid) print uuid, ip
    }' "$file" \
    | sort | uniq \
    | awk '{map[$1]++} END {
        for (u in map)
            if (map[u] > 3)
                print "ABUSE:", u, "IPs:", map[u]
    }'

    pause
}

# ========= USER TRACE =========
user_trace() {
    detect
    read -rp "Enter UUID/IP: " u

    for c in "${XRAY[@]}" "${PANEL[@]}"; do
        echo -e "${BLUE}=== $c ===${NC}"
        docker logs "$c" | grep --color=always "$u" || true
    done

    pause
}

# ========= DOCKER =========
docker_control() {
    local c action

    c=$(docker ps -a --format "{{.Names}}" | dialog --menu "Container" 20 60 10 2>&1 >/dev/tty)

    action=$(dialog --menu "Action" 15 50 5 \
        1 "Start" \
        2 "Stop" \
        3 "Restart" 2>&1 >/dev/tty)

    case $action in
        1) docker start "$c" ;;
        2) docker stop "$c" ;;
        3) docker restart "$c" ;;
    esac

    log "Done"
    sleep 1
}

# ========= CONFIG =========
edit_config() {
    local file

    file=$(find / -type f \( -name "*.json" -o -name "*.yml" \) 2>/dev/null \
        | grep -Ei 'xray|remna' \
        | head -n 20 \
        | dialog --menu "Config files" 20 70 10 2>&1 >/dev/tty)

    clear
    $EDITOR "$file"
}

# ========= STATUS =========
status() {
    clear
    echo -e "${YELLOW}REMNA CLI v$VERSION${NC}"
    docker ps -a
    pause
}

# ========= MAIN =========
main_menu() {
    while true; do
        CHOICE=$(dialog --clear --menu "REMNA CLI v$VERSION" 20 60 12 \
            1 "Containers status" \
            2 "Live logs" \
            3 "Search logs (IP/UUID)" \
            4 "User trace" \
            5 "Top IPs" \
            6 "Top users" \
            7 "Detect abuse" \
            8 "Docker control" \
            9 "Edit configs" \
            0 "Exit" \
            2>&1 >/dev/tty)

        clear

        case $CHOICE in
            1) status ;;
            2) logs_live ;;
            3) logs_search ;;
            4) user_trace ;;
            5) top_ips ;;
            6) top_users ;;
            7) abuse_detect ;;
            8) docker_control ;;
            9) edit_config ;;
            0) clear; exit ;;
        esac
    done
}

# ========= ENTRY =========
install_deps
main_menu
