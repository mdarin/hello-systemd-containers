#!/bin/bash

#
#  ДЛЯ ПУСТОГО ПАРОЛЯ ROOT ИСПОЛЬЗОВАТЬ set-empty-root-password-in-container.sh
#

# Универсальный скрипт для установки пароля root
# Использование: sudo ./set-root-password-universal.sh /путь/к/контейнеру "пароль"

set -e

CONTAINER_PATH="${1:-/var/lib/machines/my-debian-container}"
NEW_PASSWORD="$2"

if [ -z "$NEW_PASSWORD" ]; then
    echo "Использование: $0 [путь/к/контейнеру] \"пароль\""
    echo "Пример: $0 /var/lib/machines/my-debian-container \"mysecurepassword123\""
    echo "Пример (путь по умолчанию): $0 \"mysecurepassword123\""
    exit 1
fi

# Если передано только 2 аргумента, но первый не существует как директория,
# предполагаем что это пароль, а путь по умолчанию
if [ $# -eq 2 ] && [ ! -d "$1" ]; then
    NEW_PASSWORD="$1"
    CONTAINER_PATH="/var/lib/machines/my-debian-container"
fi

if [ ! -d "$CONTAINER_PATH" ]; then
    echo "Ошибка: Директория контейнера '$CONTAINER_PATH' не существует"
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    echo "Ошибка: Скрипт должен запускаться с правами root (sudo)"
    exit 1
fi

echo "Контейнер: $CONTAINER_PATH"
echo "Установка пароля для root..."

# Проверяем, какой метод доступен в контейнере
if systemd-nspawn -D "$CONTAINER_PATH" --pipe which chpasswd >/dev/null 2>&1; then
    echo "Используем chpasswd..."
    echo "root:${NEW_PASSWORD}" | systemd-nspawn -D "$CONTAINER_PATH" --pipe chpasswd
else
    echo "Используем passwd с stdin..."
    echo -e "${NEW_PASSWORD}\n${NEW_PASSWORD}" | systemd-nspawn -D "$CONTAINER_PATH" passwd
fi

echo "✅ Пароль успешно установлен!"
