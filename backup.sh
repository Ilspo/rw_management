#!/bin/bash

# Цвета для оформления
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

WORKDIR="/opt/remnawave"
BACKUP_DIR="$WORKDIR/backups"

echo -e "${YELLOW}=== Remnawave Management Script ===${NC}"

# Проверка наличия директории
if [ ! -d "$WORKDIR" ]; then
    echo -e "${RED}[ERROR] Директория $WORKDIR не найдена! Убедитесь, что панель установлена.${NC}"
    exit 1
fi

cd "$WORKDIR" || exit 1
mkdir -p "$BACKUP_DIR"

# Проверка зависимостей
if ! command -v docker &> /dev/null; then
    echo -e "${RED}[ERROR] Docker не установлен!${NC}"
    exit 1
fi

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
    read -p "Выберите вариант: " b_type < /dev/tty

    TIMESTAMP=$(date +%Y-%m-%d_%H-%M)
    
    case $b_type in
        1)
            FILE="$BACKUP_DIR/db_only_$TIMESTAMP.sql"
            echo -e "${YELLOW}[INFO] Создание дампа БД...${NC}"
            if docker compose exec -T db sh -c 'pg_dumpall -c -U "$POSTGRES_USER"' > "$FILE"; then
                echo -e "${GREEN}[SUCCESS] Дамп базы создан: $FILE${NC}"
            else
                echo -e "${RED}[ERROR] Ошибка при создании дампа!${NC}"
                rm -f "$FILE"
            fi
            ;;
        2)
            FILE="$BACKUP_DIR/full_backup_$TIMESTAMP.tar.gz"
            echo -e "${YELLOW}[INFO] Создание полного бэкапа...${NC}"
            
            # Сначала делаем дамп во временный файл с проверкой успешности
            if docker compose exec -T db sh -c 'pg_dumpall -c -U "$POSTGRES_USER"' > "$WORKDIR/dump_temp.sql"; then
                # Пакуем всё важное (проверяем наличие caddy перед добавлением)
                local TAR_TARGETS=".env docker-compose.yml dump_temp.sql"
                if [ -d "caddy" ]; then TAR_TARGETS="$TAR_TARGETS caddy/"; fi
                
                tar -czf "$FILE" -C "$WORKDIR" $TAR_TARGETS
                rm -f "$WORKDIR/dump_temp.sql"
                echo -e "${GREEN}[SUCCESS] Полный архив создан: $FILE${NC}"
            else
                echo -e "${RED}[ERROR] Ошибка при создании дампа БД. Бэкап прерван!${NC}"
                rm -f "$WORKDIR/dump_temp.sql"
            fi
            ;;
        *) echo -e "${RED}Отмена.${NC}" ;;
    esac
}

# --- МЕНЮ ВОССТАНОВЛЕНИЯ ---
do_restore() {
    echo -e "\n${YELLOW}Доступные бэкапы в $BACKUP_DIR:${NC}"
    
    # Проверяем, есть ли файлы
    if [ -z "$(ls -A "$BACKUP_DIR")" ]; then
        echo -e "${RED}Нет доступных бэкапов в $BACKUP_DIR${NC}"
        return
    fi

    ls -1 "$BACKUP_DIR"
    read -p "Введите имя файла для восстановления: " r_file < /dev/tty
    
    local filepath="$BACKUP_DIR/$r_file"

    if [ ! -f "$filepath" ]; then
        echo -e "${RED}[!] Файл не найден!${NC}"
        return
    fi

    # Если это SQL файл (только база)
    if [[ "$r_file" == *.sql ]]; then
        echo -e "${YELLOW}[INFO] Восстановление только БД...${NC}"
        if docker compose exec -T db sh -c 'psql -U "$POSTGRES_USER"' < "$filepath"; then
            echo -e "${GREEN}[SUCCESS] База восстановлена.${NC}"
        else
            echo -e "${RED}[ERROR] Ошибка при восстановлении базы!${NC}"
        fi

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
        echo -e "${YELLOW}[INFO] Перезапуск контейнера БД...${NC}"
        docker compose up -d db
        echo -e "${YELLOW}[INFO] Ожидание готовности базы (5 сек)...${NC}"
        sleep 5 # Ждем старта базы
        
        echo -e "${YELLOW}[INFO] Импорт дампа БД...${NC}"
        if docker compose exec -T db sh -c 'psql -U "$POSTGRES_USER"' < "$WORKDIR/temp_restore/dump_temp.sql"; then
            echo -e "${GREEN}[SUCCESS] База успешно импортирована.${NC}"
        else
             echo -e "${RED}[ERROR] Ошибка при импорте БД!${NC}"
        fi
        
        # 3. Восстановление конфигов Caddy (если есть)
        if [ -d "$WORKDIR/temp_restore/caddy" ]; then
            cp -r "$WORKDIR/temp_restore/caddy" "$WORKDIR/"
            echo -e "${GREEN}[+] Конфиги Caddy восстановлены${NC}"
        fi

        rm -rf "$WORKDIR/temp_restore"
        echo -e "${GREEN}[SUCCESS] Полное восстановление завершено.${NC}"
        
        echo -e "${YELLOW}[INFO] Запуск всех сервисов...${NC}"
        docker compose up -d
    else
        echo -e "${RED}[!] Неподдерживаемый формат файла.${NC}"
    fi
}

# --- ГЛАВНОЕ МЕНЮ ---
echo "1) Сделать бэкап"
echo "2) Восстановить из бэкапа"
echo "3) Выход"
read -p "Выберите действие: " action < /dev/tty

case $action in
    1) do_backup ;;
    2) do_restore ;;
    3) exit 0 ;;
    *) echo -e "${RED}Неверный выбор${NC}" ;;
esac
