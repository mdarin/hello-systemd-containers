#!/bin/bash

set -e

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m' # No Color

# Конфигурация
CONTAINER_NAME="app-webui-debian-container"
CONTAINER_PATH="/var/lib/machines/$CONTAINER_NAME"
CACHE_PATH="/var/cache/apt/archives/partial"
#CONTAINER_NAME="${1:-debian-container}" # TODO: использовать это для общего случая
CONTAINER_DIR="/var/lib/machines/$CONTAINER_NAME"
DISTRO="${2:-bookworm}"
ARCH="${3:-}"  # armel, armhf, amd64, etc
MIRROR="http://deb.debian.org/debian/"

# Функция для генерации случайного имени
generate_container_name() {
    local prefix="${1:-debian}"
    echo "${prefix}-$(date +%s | tail -c 4)"
}

# Если имя не указано, генерируем случайное
if [[ -z "$1" ]]; then
    CONTAINER_NAME=$(generate_container_name)
    CONTAINER_DIR="/var/lib/machines/$CONTAINER_NAME"
    echo "Имя контейнера не указано, используем: $CONTAINER_NAME"
fi

# Проверяем, не существует ли контейнер
if [[ -d "$CONTAINER_DIR" ]]; then
    echo "Ошибка: Контейнер '$CONTAINER_NAME' уже существует в $CONTAINER_DIR"
    exit 1
fi

# Проверяем, не совпадает ли имя с hostname хоста
HOST_HOSTNAME=$(hostname)
if [[ "$CONTAINER_NAME" == "$HOST_HOSTNAME" ]]; then
    echo "Предупреждение: Имя контейнера совпадает с hostname хоста"
    read -p "Продолжить? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo -e "${MAGENTA}Создание Debian контейнера для ARMv6l (Raspberry Pi 1/Zero)...${NC}"
echo

# Полная очистка всего что может мешать
clean_all() {
    echo "Выполняем полную очистку..."

    # Удаляем директорию контейнера
    if sudo ls "/var/lib/machines/" | grep -q "$CONTAINER_NAME"; then
        echo -e "Обнаружен контейнер ${YELLOW}$CONTAINER_NAME${NC} через ls, удаляем его..."
        sudo rm -rf "$CONTAINER_PATH"
    fi
    
    # Очищаем кеш apt в хостовой системе
    echo "Очищаем кеш apt..."
    sudo apt clean
    sudo rm -rf /var/cache/apt/archives/partial/*
    sudo rm -rf /var/cache/apt/archives/*.deb
}

# Упрощенная проверка контейнера
# Использование:
# check_container_simple "/path/to/container"
check_container_simple() {
    local container_path="$1"
    
    # Базовые проверки
    if [ ! -d "$container_path" ]; then
        echo "❌ Каталог контейнера не существует"
        return 1
    fi
    
    if [ -z "$(ls -A "$container_path")" ]; then
        echo "❌ Каталог контейнера пуст"
        return 1
    fi
    
    # Проверка ключевых элементов
    local checks=0
    local total_checks=3
    
    [ -f "$container_path/usr/bin/sh" ] && ((checks++))
    [ -d "$container_path/etc" ] && ((checks++))
    [ -d "$container_path/usr" ] && ((checks++))
    
    if [ $checks -eq $total_checks ]; then
        echo "✅ Контейнер корректно создан ($checks/$total_checks проверок)"
        return 0
    elif [ $checks -ge 2 ]; then
        echo "⚠ Контейнер создан, но неполный ($checks/$total_checks проверок)"
        echo "Содержимое каталога:"
        ls -la "$container_path"
        return 0
    else
        echo "❌ Контейнер невалиден ($checks/$total_checks проверок)"
        return 1
    fi
}



# Функция создания контейнера с проверкой
create_container() {
    local version=$1
    
    echo -e "${GREEN}Попытка установки $version...${NC}"
    
    # Дополнительная очистка кеша внутри целевой директории
    if [ -d "$CONTAINER_PATH/var/cache/apt/archives/partial" ]; then
        sudo rm -rf "$CONTAINER_PATH/var/cache/apt/archives/partial/*"
    fi
    
    # TODO: ----begin
    # # Параметры debootstrap
    # DEBOOTSTRAP_OPTS=(
    #     "--hostname=$CONTAINER_NAME"
    #     "--variant=minbase"
    #     "--include=systemd,systemd-sysv,dbus"
    # )

    # # Добавляем архитектуру если указана
    # if [[ -n "$ARCH" ]]; then
    #     DEBOOTSTRAP_OPTS+=("--arch=$ARCH")
    # fi

    # # Создаем контейнер
    # sudo debootstrap \
    #     "${DEBOOTSTRAP_OPTS[@]}" \
    #     "$DISTRO" \
    #     "$CONTAINER_DIR" \
    #     "$MIRROR"
    # ----- end

    if sudo debootstrap \
        --arch=armel \
        --variant=minbase \
        --include=systemd,systemd-sysv,dbus,apt-utils,dialog,debian-archive-keyring \
        "$version" \
        "$CONTAINER_PATH" \
        http://deb.debian.org/debian/ 2>&1 | tee /tmp/debootstrap.log; then
        
        # Проверяем что контейнер действительно создан
        check_container_simple "$CONTAINER_PATH"
        local result=$?
    
        return $result
       
    else
        # Анализируем ошибку
        if grep -q "file already exists" /tmp/debootstrap.log; then
            echo "Обнаружены конфликтующие файлы, выполняем очистку..."
            clean_all
        fi
        return 1
    fi
}

echo "Существующие образы"
echo "============================"
sudo ls -h /var/lib/machines
echo "============================"

# Основной код
clean_all

echo "Существующие образы"
echo "============================"
sudo ls -h /var/lib/machines
echo "============================"
echo 

# Создаем чистую директорию
sudo mkdir -p "$CONTAINER_PATH"
sudo mkdir -p "$CONTAINER_PATH/var/cache/apt/archives/partial"
sudo chmod 755 "$CONTAINER_PATH/var/cache/apt/archives/partial"

# Флаг успешной установки
INSTALL_SUCCESS=false

# Пробуем разные версии Debian (в порядке надежности)
# TODO: здесь можно использовать результаты скрипта проверки доступных версий
echo "Создание Debian системы..."
for version in  "bookworm" "stable"; do
    if create_container "$version"; then
        echo -e "✓ ${GREEN}Установлен $version${NC}"
        INSTALL_SUCCESS=true
        break
    else
        echo "✗ $version не удалось установить, пробуем следующую..."
        clean_all
        sleep 2
    fi
done

# Критическая проверка успешности установки
if [ "$INSTALL_SUCCESS" = false ]; then
    echo " "
    echo "❌ КРИТИЧЕСКАЯ ОШИБКА: ни одна версия Debian не смогла установиться"
    echo "Логи последней попытки:"
    cat /tmp/debootstrap.log | tail -20
    echo " "
    echo "Попробуйте выполнить вручную:"
    echo "sudo rm -rf /var/lib/machines/$CONTAINER_NAME"
    echo "sudo rm -rf /var/cache/apt/archives/partial/*"
    echo "sudo apt clean"
    exit 1
fi

echo "✅ Базовый Debian успешно установлен!"

# Копируем скрипт установки nginx
cat > /tmp/install-nginx.sh << 'EOF'
#!/bin/bash
set -e

echo "Настройка Debian контейнера для ARMv6..."
echo "========================================"

# Настройка hostname
# TODO: это надо тоже как-то автоматизировать
CONTAINER_HOSTNAME="app-webui-debian-container" 

# Настройте уникальное имя хоста (Это ОЧЕНЬ важно!)

# echo "Setting hostname to: $CONTAINER_HOSTNAME"
# echo "$CONTAINER_HOSTNAME" | tee /etc/hostname
# echo "127.0.0.1 $CONTAINER_HOSTNAME" | tee -a /etc/hosts
# echo "::1 $CONTAINER_HOSTNAME" | tee -a /etc/hosts
# hostnamectl set-hostname "$CONTAINER_HOSTNAME"

# Обновляем систему
apt update
apt upgrade -y

# Устанавливаем systemd и nginx
apt install -y systemd nginx 

# =========== Пользовательские настройки эта часть изменяется =======
# Здесь устанавливается приложение пользователя.
# Nginx и преветсвтенная страница, это наглядный пример.

# Создаем директории для nginx
mkdir -p /run/nginx
mkdir -p /var/www/html

# Создаем простой index.html
cat > /var/www/html/index.html << 'HTML_EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Welcome to eClock WebUI</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #333; }
    </style>
</head>
<body>
    <h1>Welcome to eClock WebUI</h1>
    <p>Debian ARMv6 + Nginx container is running!</p>
    <p>Architecture: armv6l</p>
</body>
</html>
HTML_EOF

# Упрощенная конфигурация nginx для ARMv6
cat > /etc/nginx/nginx.conf << 'NGINX_EOF'
user www-data;
worker_processes 1;

events {
    worker_connections 128;
}

http {
    sendfile on;
    tcp_nopush on;
    keepalive_timeout 30;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    access_log off;
    error_log /var/log/nginx/error.log;

    server {
        listen 59095;
        server_name localhost;
        root /var/www/html;

        location / {
            index index.html;
            try_files $uri $uri/ =404;
        }
    }
}
NGINX_EOF

# Включаем nginx
systemctl enable nginx

# Создаем скрипт проверки
cat > /usr/local/bin/check-nginx.sh << 'CHECK_EOF'
#!/bin/bash
if systemctl is-active --quiet nginx; then
    exit 0
else
    exit 1
fi
CHECK_EOF

chmod +x /usr/local/bin/check-nginx.sh

# Процедура развёртывания прилжения пользователя здесь звершается.
# ================================================================

# Чистим кеш
apt autoremove -y
apt clean

echo "Установка приложения завершена для ARMv6!"
EOF

echo "Оптимизация размера контейнера..."
sudo rm -rf "$CONTAINER_PATH"/usr/share/doc/*
sudo rm -rf "$CONTAINER_PATH"/usr/share/man/*

echo -e "${MAGENTA}Создание Debian контейнера для ARMv6l (Raspberry Pi 1/Zero) выполнено${NC}"

sudo mv /tmp/install-nginx.sh "$CONTAINER_PATH/install-nginx.sh"
sudo chmod +x "$CONTAINER_PATH/install-nginx.sh"

echo "Скрипт установки подготовлен"
echo "Для завершения выполните: sudo ./install-nginx-in-container.sh"
echo
