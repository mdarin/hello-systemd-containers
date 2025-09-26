#!/bin/bash

# Скрипт для установки пустого пароля root
# Использование: sudo ./set-empty-password.sh /путь/к/контейнеру

set -e

CONTAINER_PATH="$1"

if [ $# -ne 1 ]; then
    echo "Использование: $0 /путь/к/контейнеру"
    echo "Пример: $0 /var/lib/machines/my-debian-container"
    exit 1
fi

if [ ! -d "$CONTAINER_PATH" ]; then
    echo "Ошибка: Директория контейнера не существует"
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    echo "Ошибка: Требуются права root"
    exit 1
fi

echo "Установка пустого пароля для root в контейнере: $CONTAINER_PATH"

# Разблокируем учетную запись root (устанавливаем пустой пароль)
systemd-nspawn -D "$CONTAINER_PATH" usermod -p "" root

echo "Пустой пароль успешно установлен!"
