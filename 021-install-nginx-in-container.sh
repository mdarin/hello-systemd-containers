#!/bin/bash
set -e

CONTAINER_NAME="app-webui-debian-container"
CONTAINER_PATH="/var/lib/machines/$CONTAINER_NAME"

echo "Запуск контейнера для установки nginx..."

# Проверки
[ ! -d "$CONTAINER_PATH" ] && echo "Ошибка: контейнер не существует" && exit 1
[ ! -f "$CONTAINER_PATH/install-nginx.sh" ] && echo "Ошибка: скрипт установки не найден" && exit 1

# Очистка symlinks
sudo rm -f "$CONTAINER_PATH/dev/console" 2>/dev/null || true

# Запускаем установку внутри контейнера без --boot и с отключением console

# Проверяем состояние и запускаем
if sudo machinectl show "$CONTAINER_NAME" 2>/dev/null | grep -q "State=running"; then
    echo "✅ Контейнер запущен, выполняем скрипт..."
    sudo machinectl shell "$CONTAINER_NAME" /usr/bin/bash /install-nginx.sh
else
    echo "🔄 Запускаем контейнер для выполнения скрипта..."
    sudo systemd-nspawn -D "$CONTAINER_PATH" --resolv-conf=copy-host --console=interactive /usr/bin/bash /install-nginx.sh
fi

# Покажем открытые порты
ss -tlnp
echo

echo -e "✅ Nginx успешно установлен в контейнере $CONTAINER_NAME"
echo -e " "
echo -e "📦 Размер контейнера: $(sudo du -sh $CONTAINER_PATH | cut -f1)"
echo -e " "
echo -e "🌐 Nginx доступен на порту: 59095"
echo -e "🔗 URL для проверки: http://localhost:59095"
echo -e " "
echo -e "🐳 Контейнер готов к работе!"
