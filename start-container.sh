#!/bin/bash
# start-container.sh

CONTAINER_NAME="app-webui-debian-container"
CONTAINER_PATH="/var/lib/machines/$CONTAINER_NAME"

echo "🚀 Запуск контейнера с пробросом порта 80 → 59095"

sudo systemd-nspawn \
    -D "$CONTAINER_PATH" \
    --boot \
    --network-interface=wlan0 \
    --private-network \
    --port tcp:8080:59095

# echo "✅ Контейнер запущен"
# echo "🌐 Web-сервер доступен: http://localhost:80"

# Проверка работы
# bash
# # После запуска проверьте
# sudo machinectl list
# sudo ss -tlnp | grep 80
# curl http://localhost:80
