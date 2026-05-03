#!/bin/bash

# Цвета для оформления
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

WORKDIR="/opt/remnawave"
BACKUP_DIR="$WORKDIR/backups"
mkdir -p "$BACKUP_DIR"

echo -e "${YELLOW}=== Remnawave Management Script ===${NC}"

# Функция для синхронизации .env
sync_env() {
    local source_env=$1
    local target_env="$WORKDIR/.env"
    
    if [ ! -f "$source_env" ]; then
        echo -e "${RED}[!] Файл .env в бэкапе не найден. Пропускаю обновление ключей.${NC}"
        return
    fi

    echo -e "${YELLOW}[INFO] Синхронизация ключей .env...${NC}"
    
    # Список критических полей, которые нужно перенести из бэкапа
    local keys=("APP_SECRET" "JWT_SECRET" "POSTGRES_PASSWORD" "POSTGRES_USER" "POSTGRES_DB")

    for key in "${keys[@]}"; do
        local value=$(grep "^$key=" "$source_env" | cut -d'=' -f2-)
        if [ -n "$value" ]; then
            # Удаляем старую строку и добавляем новую из бэкапа
            sed -i "/^$key=/d" "$target_env"
            echo "$key=$value" >> "$target_env"
            echo -e "${GREEN}[+] Поле $key обновлено${NC}"
        fi
    done
}

# --- МЕНЮ БЭКАПА ---
do_backup() {
    echo -e "\n${YELLOW}Что включить в бэкап?${NC}"
    echo "1) Только базу данных (.sql)"
    echo "2) Полный бэкап (БД + .env + конфиги)"
    read -p "Выберите вариант: " b_type

    TIMESTAMP=$(date +%Y-%m-%d_%H-%M)
    
    case $b_type in
        1)
            FILE="$BACKUP_DIR/db_only_$TIMESTAMP.sql"
            docker exec -t remnawave-db pg_dumpall -c -U postgres > "$FILE"
            echo -e "${GREEN}[SUCCESS] Дамп базы создан: $FILE${NC}"
            ;;
        2)
            FILE="$BACKUP_DIR/full_backup_$TIMESTAMP.tar.gz"
            # Сначала делаем дамп во временный файл
            docker exec -t remnawave-db pg_dumpall -c -U postgres > "$WORKDIR/dump_temp.sql"
            # Пакуем всё важное
            tar -czf "$FILE" -C "$WORKDIR" .env docker-compose.yml caddy/ dump_temp.sql
            rm "$WORKDIR/dump_temp.sql"
            echo -e "${GREEN}[SUCCESS] Полный архив создан: $FILE${NC}"
            ;;
        *) echo -e "${RED}Отмена.${NC}" ;;
    esac
}

# --- МЕНЮ ВОССТАНОВЛЕНИЯ ---
do_restore() {
    echo -e "\n${YELLOW}Доступные бэкапы в $BACKUP_DIR:${NC}"
    ls -1 "$BACKUP_DIR"
    read -p "Введите имя файла для восстановления: " r_file
    
    local filepath="$BACKUP_DIR/$r_file"

    if [ ! -f "$filepath" ]; then
        echo -e "${RED}[!] Файл не найден!${NC}"
        return
    fi

    # Если это SQL файл (только база)
    if [[ "$r_file" == *.sql ]]; then
        echo -e "${YELLOW}[INFO] Восстановление только БД...${NC}"
        cat "$filepath" | docker exec -i remnawave-db psql -U postgres
        echo -e "${GREEN}[SUCCESS] База восстановлена.${NC}"

    # Если это архив (полный бэкап)
    elif [[ "$r_file" == *.tar.gz ]]; then
        echo -e "${YELLOW}[INFO] Распаковка архива...${NC}"
        mkdir -p "$WORKDIR/temp_restore"
        tar -xzf "$filepath" -C "$WORKDIR/temp_restore"

        # 1. Умная работа с .env
        if [ -f "$WORKDIR/.env" ]; then
            sync_env "$WORKDIR/temp_restore/.env"
        else
            cp "$WORKDIR/temp_restore/.env" "$WORKDIR/.env"
            echo -e "${GREEN}[+] Файл .env создан с нуля${NC}"
        fi

        # 2. Восстановление БД
        docker compose up -d remnawave-db
        sleep 3 # Ждем старта базы
        cat "$WORKDIR/temp_restore/dump_temp.sql" | docker exec -i remnawave-db psql -U postgres
        
        # 3. Восстановление конфигов (по желанию можно добавить Caddy)
        # cp -r "$WORKDIR/temp_restore/caddy" "$WORKDIR/"

        rm -rf "$WORKDIR/temp_restore"
        echo -e "${GREEN}[SUCCESS] Полное восстановление завершено.${NC}"
        docker compose up -d
    fi
}

# --- ГЛАВНОЕ МЕНЮ ---
echo "1) Сделать бэкап"
echo "2) Восстановить из бэкапа"
echo "3) Выход"
read -p "Выберите действие: " action

case $action in
    1) do_backup ;;
    2) do_restore ;;
    3) exit 0 ;;
    *) echo "Неверный выбор" ;;
esac
