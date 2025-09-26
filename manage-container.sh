#!/bin/bash

CONTAINER_NAME="app-webui-debian-container"
SERVICE_NAME="app-webui-container.service"

case "$1" in
    start)
        echo "Запуск контейнера..."
        sudo systemctl start "$SERVICE_NAME"
        ;;
    stop)
        echo "Остановка контейнера..."
        sudo systemctl stop "$SERVICE_NAME"
        ;;
    restart)
        echo "Перезапуск контейнера..."
        sudo systemctl restart "$SERVICE_NAME"
        ;;
    status)
        echo "Статус контейнера:"
        sudo systemctl status "$SERVICE_NAME"
        ;;
    logs)
        echo "Логи контейнера:"
        sudo journalctl -u "$SERVICE_NAME" -f
        ;;
    login)
        echo "Вход в контейнер..."
        sudo machinectl login "$CONTAINER_NAME"
        ;;
    shell)
        echo "Вход в shell контейнера..."
        sudo machinectl shell "$CONTAINER_NAME"
        ;;
    *)
        echo "Использование: $0 {start|stop|restart|status|logs|login|shell}"
        exit 1
        ;;
esac
