#!/bin/bash

# Упрощенная версия скрипта для начала

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Проверка прав
if [[ $EUID -eq 0 ]]; then
    print_warning "Скрипт запущен от root"
else
    print_status "Запуск от обычного пользователя"
fi

# Проверка дистрибутива
if [[ ! -f /etc/debian_version ]]; then
    print_error "Требуется Debian/Ubuntu"
    exit 1
fi

print_status "Обновление пакетов..."
sudo apt update

print_status "Установка systemd-nspawn и зависимостей..."
sudo apt install -y systemd-container debootstrap qemu-user-static binfmt-support

print_status "Проверка установки..."
if which systemd-nspawn >/dev/null 2>&1; then
    print_status "✓ systemd-nspawn установлен: $(which systemd-nspawn)"
    systemd-nspawn --version | head -1
else
    print_error "✗ systemd-nspawn не установлен"
    exit 1
fi

print_status "Установка завершена успешно!"
