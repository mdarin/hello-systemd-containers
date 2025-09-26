#!/bin/bash

CONTAINER_PATH="/var/lib/machines/app-webui-debian-container"

echo "Дополнительная настройка контейнера..."

# Настраиваем локаль
sudo systemd-nspawn -D "$CONTAINER_PATH" apt install -y locales
sudo systemd-nspawn -D "$CONTAINER_PATH" sed -i 's/^# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sudo systemd-nspawn -D "$CONTAINER_PATH" locale-gen

# Настраиваем часовой пояс
sudo systemd-nspawn -D "$CONTAINER_PATH" ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# Устанавливаем дополнительные утилиты (опционально)
sudo systemd-nspawn -D "$CONTAINER_PATH" apt install -y curl wget vim

echo "Дополнительная настройка завершена"
