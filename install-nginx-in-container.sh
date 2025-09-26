#!/bin/bash
set -e

CONTAINER_NAME="app-webui-debian-container"
CONTAINER_PATH="/var/lib/machines/$CONTAINER_NAME"

echo "Запуск контейнера для установки nginx..."

# Сначала проверяем что контейнер существует
if [ ! -d "$CONTAINER_PATH" ]; then
    echo "Ошибка: контейнер $CONTAINER_PATH не существует"
    exit 1
fi

# Удаляем конфликтующие symlinks если они есть
if [ -L "$CONTAINER_PATH/dev/console" ]; then
    echo "Удаляем конфликтующий symlink /dev/console..."
    sudo rm -f "$CONTAINER_PATH/dev/console"
fi

# Запускаем установку внутри контейнера без --boot и с отключением console
    # --console=pipe \
sudo systemd-nspawn \
    -D "$CONTAINER_PATH" \
    --resolv-conf=copy-host \
    /usr/bin/bash /install-nginx.sh

echo "**Nginx успешно установлен в контейнере**"
echo " "
echo "📦 **Размер контейнера:** $(sudo du -sh $CONTAINER_PATH | cut -f1)"
echo " "
echo "🌐 **Nginx доступен на порту:** 59095"
echo "🔗 **URL для проверки:** http://localhost:59095"
echo " "
echo "🐳 **Контейнер готов к работе!**"
