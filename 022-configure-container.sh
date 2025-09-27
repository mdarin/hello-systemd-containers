#!/bin/bash

#
# Добавляйте сюда все необходимые пакеты для работы вашего приложения.
# ВАЖНО! Желательно всё протестировать в ручном режиме после запуска минимального контейнера.
#        И только после того, как всё усешно установитсья и настроется, внесли в скрипт.
#

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m' # No Color

CONTAINER_NAME="app-webui-debian-container"
CONTAINER_PATH="/var/lib/machines/$CONTAINER_NAME"

echo -e "Дополнительная настройка контейнера ${YELLOW}$CONTAINER_NAME${NC}..."
echo

# Настраиваем локаль
sudo systemd-nspawn -D "$CONTAINER_PATH" apt install -y locales
sudo systemd-nspawn -D "$CONTAINER_PATH" sed -i 's/^# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sudo systemd-nspawn -D "$CONTAINER_PATH" locale-gen

# Настраиваем часовой пояс
sudo systemd-nspawn -D "$CONTAINER_PATH" ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# Устанавливаем дополнительные утилиты (опционально)
sudo systemd-nspawn -D "$CONTAINER_PATH" apt install -y curl wget vim nano inetutils-ping

# TODO: Включить systemd-networkd
#WARNING: systemd-networkd is not running, output will be incomplete.
# systemctl enable systemd-networkd
# systemctl start systemd-networkd


# TODO: После настройки сети выполнить 
# networkctl relolad или что-то такое

echo
echo "Дополнительная настройка завершена"
