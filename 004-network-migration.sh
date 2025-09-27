#!/bin/bash
# ================================================
# Важное замечание: 
# Несмотря на все улучшения, переключение сетевых демонов по SSH остается рискованной операцией. 
# Настоятельно рекомендуется иметь альтернативный способ доступа к устройству.
# ================================================

set -e

echo "================================================================"
echo "ВНИМАНИЕ: ПЕРЕД ЗАПУСКОМ СКРИПТА"
echo "1. Подключитесь к Wi-Fi сети"
echo "2. Замените 'your_wifi_password_here' в функции setup_wifi_password()"
echo "3. Убедитесь, что есть физический доступ к устройству"
echo ""
echo "Нажмите ctrl + c для завершения."
echo "Если всё настроено, подождите. Миграция продолжится дальше."
echo "================================================================"
sleep 3

# Глобальные переменные для состояния
previous_network_manager="inactive"
previous_dhcpcd="inactive"
CAN_ROLLBACK=1  # Флаг, что откат возможен

# Определяем команду в зависимости от прав
if [[ $EUID -eq 0 ]]; then
    SUDO=""
    LOG_FILE="/var/log/network-migration.log"
else
    SUDO="sudo"
    LOG_FILE="/tmp/network-migration.log"
fi

# Функция для логирования
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

create_basic_network_config() {
   log "Создаем базовую конфигурацию Wi-Fi сети для systemd-networkd..."
    
    # TODO: ПЕРЕД ЗАПУСКОМ СКРИПТА ОБЯЗАТЕЛЬНО!
    # 1. Убедитесь, что подключены к Wi-Fi сети
    # 2. Замените "your_wifi_password_here" в функции setup_wifi_password() на реальный пароль
    # 3. Сохраните изменения в скрипте
    
    # Проверяем, что wlan0 существует
    if ! ip link show wlan0 >/dev/null 2>&1; then
        error_exit "Интерфейс wlan0 не найден. Проверьте Wi-Fi адаптер."
    fi

    # Получаем SSID Wi-Fi сети
    local wifi_ssid=$(iwgetid -r 2>/dev/null)
    if [[ -z "$wifi_ssid" ]]; then
        error_exit "Не удалось определить SSID Wi-Fi сети. Подключитесь к Wi-Fi сначала."
    fi

    # Получаем SSID Wi-Fi сети
    local wifi_ssid=$(iwgetid -r 2>/dev/null)
    if [[ -z "$wifi_ssid" ]]; then
        error_exit "Не удалось определить SSID Wi-Fi сети. Подключитесь к Wi-Fi сначала."
    fi

    # Определяем текущие сетевые настройки wlan0
    local current_ip=$(ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    local current_gw=$(ip route | grep default | awk '{print $3}')
    local current_dns=$(grep nameserver /etc/resolv.conf | awk '{print $2}' | head -1)
    
    if [[ -z "$current_dns" ]]; then
        current_dns="8.8.8.8"
    fi
    
    log "Текущее Wi-Fi подключение: SSID=$wifi_ssid, IP=$current_ip, Gateway=$current_gw"
    
    # Создаем конфигурацию для wlan0 с DHCP
    $SUDO tee /etc/systemd/network/20-wlan0.network > /dev/null << EOF
[Match]
Name=wlan0

[Network]
DHCP=yes
IPv6AcceptRA=no
# или публичные
# DNS=8.8.8.8
# DNS=8.8.4.4
# или используйте DNS вашего провайдера/роутера
DNS=192.168.1.1    # local gw dns
DNS=208.67.222.123 # opendns
EOF

    # Создаем конфигурацию для Wi-Fi соединения
    $SUDO tee /etc/wpa_supplicant/wpa_supplicant-wlan0.conf > /dev/null << EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=RU

network={
    ssid="$wifi_ssid"
    key_mgmt=WPA-PSK
    scan_ssid=1
}
EOF

    # Устанавливаем правильные права на файл конфигурации
    $SUDO chmod 600 /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
    
    # Создаем сервис для wpa_supplicant (исправленная версия)
    $SUDO tee /etc/systemd/system/wpa_supplicant@wlan0.service > /dev/null << EOF
[Unit]
Description=WPA supplicant for wlan0
After=network.target
Wants=network.target
Before=systemd-networkd.service

[Service]
Type=simple
ExecStart=/sbin/wpa_supplicant -c /etc/wpa_supplicant/wpa_supplicant-wlan0.conf -i wlan0 -D nl80211,wext
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Получаем и настраиваем пароль Wi-Fi
    setup_wifi_password "$wifi_ssid"
    
    # Включаем и запускаем wpa_supplicant
    $SUDO systemctl enable wpa_supplicant@wlan0.service
    if ! $SUDO systemctl start wpa_supplicant@wlan0.service; then
        error_exit "Не удалось запустить wpa_supplicant"
    fi
    
    log "Базовая конфигурация Wi-Fi сети создана"
    log "SSID: $wifi_ssid"
}

setup_wifi_password() {
    local wifi_ssid=$1
    local wifi_password=""
    
    log "Настройка пароля Wi-Fi для сети: $wifi_ssid"
    
    # TODO: ЗАДАЙТЕ ПАРОЛЬ WI-FI ПЕРЕД ЗАПУСКОМ СКРИПТА!
    # Замените "your_wifi_password_here" на реальный пароль от вашей Wi-Fi сети
    wifi_password="qwertyuioplkjhgfdsa"
    
    # Проверяем, что пароль был изменен
    if [[ "$wifi_password" == "your_wifi_password_here" ]]; then
        error_exit "Пароль Wi-Fi не настроен! Замените 'your_wifi_password_here' на реальный пароль в функции setup_wifi_password()"
    fi
    
    if [[ -z "$wifi_password" ]]; then
        error_exit "Пароль Wi-Fi не введен"
    fi
    
    # Безопасное добавление пароля через wpa_passphrase
    local temp_conf=$(mktemp)
    echo "network={" > "$temp_conf"
    echo "    ssid=\"$wifi_ssid\"" >> "$temp_conf"
    echo "    psk=\"$wifi_password\"" >> "$temp_conf"
    echo "}" >> "$temp_conf"
    
    # Генерируем хэшированный пароль
    local hashed_psk=$(wpa_passphrase "$wifi_ssid" "$wifi_password" | grep -E '^\s*psk=' | head -1 | cut -d= -f2)
    
    # Очищаем временный файл
    rm -f "$temp_conf"
    
    if [[ -z "$hashed_psk" ]]; then
        error_exit "Не удалось сгенерировать хэш пароля Wi-Fi"
    fi
    
    # Обновляем конфигурацию wpa_supplicant
    $SUDO sed -i "/ssid=.*/a \    psk=$hashed_psk" /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
    
    log "Пароль Wi-Fi успешно настроен"
}

# функция проверки Wi-Fi подключения
check_wifi_connection() {
    local max_attempts=30
    local attempt=1
    
    log "Ожидание Wi-Fi подключения..."
    
    while [ $attempt -le $max_attempts ]; do
        # Проверяем состояние соединения
        if iw dev wlan0 link 2>/dev/null | grep -q "Connected"; then
            local ip_address=$(ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
            if [[ -n "$ip_address" ]]; then
                log "Wi-Fi подключение установлено. IP: $ip_address"
                return 0
            fi
        fi
        
        if [ $((attempt % 5)) -eq 0 ]; then
            log "Попытка $attempt/$max_attempts: Ожидание Wi-Fi подключения..."
        fi
        
        attempt=$((attempt + 1))
        sleep 2
    done
    
    error_exit "Не удалось установить Wi-Fi подключение за $max_attempts попыток"
}

# Функция проверки состояния systemd-networkd
check_systemd_networkd_status() {
    local status_output
    status_output=$($SUDO systemctl status systemd-networkd.service 2>&1)
    
    # Анализируем вывод systemctl status
    if echo "$status_output" | grep -q "Loaded:.*loaded.*systemd-networkd.service"; then
        # Служба существует в systemd
        if echo "$status_output" | grep -q "Active:.*active.*running"; then
            echo "active"
        elif echo "$status_output" | grep -q "Active:.*inactive.*dead"; then
            echo "installed_inactive"
        else
            echo "installed_unknown"
        fi
    else
        # Служба не найдена в systemd
        echo "not_installed"
    fi
}

# Функция установки systemd-networkd
install_systemd_networkd() {
    log "Устанавливаем systemd-networkd..."
    
    # Определяем менеджер пакетов
    if command -v apt >/dev/null 2>&1; then
        # Debian/Ubuntu/Raspberry Pi OS
        $SUDO apt update
        if ! $SUDO apt install -y systemd-networkd; then
            error_exit "Не удалось установить systemd-networkd через apt"
        fi
    elif command -v dnf >/dev/null 2>&1; then
        # Fedora/CentOS 8+
        $SUDO dnf install -y systemd-networkd
    elif command -v yum >/dev/null 2>&1; then
        # CentOS 7
        $SUDO yum install -y systemd-networkd
    elif command -v pacman >/dev/null 2>&1; then
        # Arch Linux
        $SUDO pacman -Sy --noconfirm systemd
    else
        error_exit "Не удалось определить менеджер пакетов"
    fi
    
    # Проверяем, что установка прошла успешно
    local install_status=$(check_systemd_networkd_status)
    if [[ "$install_status" == "not_installed" ]]; then
        error_exit "Установка systemd-networkd завершилась неудачно"
    fi
    
    log "systemd-networkd успешно установлен (статус: $install_status)"
}

# Функция аварийного завершения с откатом
error_exit() {
    log "ERROR: $1"
    log "Выполняем откат изменений..."
    revert_changes
    exit 1
}

# Функция безопасной проверки статуса службы
get_service_status() {
    local service=$1
    $SUDO systemctl is-active "$service" 2>/dev/null || echo "inactive"
}

# Функция отката изменений
revert_changes() {
    if [[ $CAN_ROLLBACK -eq 0 ]]; then
        log "Откат невозможен - не было изменений или точка невозврата пройдена"
        return 1
    fi
    
    log "Восстанавливаем предыдущую сетевую конфигурацию..."
    
    # Останавливаем systemd-networkd если он был запущен
    if $SUDO systemctl is-active systemd-networkd >/dev/null 2>&1; then
        $SUDO systemctl stop systemd-networkd
        $SUDO systemctl disable systemd-networkd
    fi
    
    # Восстанавливаем предыдущие демоны только если они были активны
    if [[ "$previous_network_manager" == "active" ]]; then
        log "Восстанавливаем NetworkManager..."
        $SUDO systemctl enable NetworkManager
        if ! $SUDO systemctl start NetworkManager; then
            log "WARNING: Не удалось запустить NetworkManager"
        fi
    fi
    
    if [[ "$previous_dhcpcd" == "active" ]]; then
        log "Восстанавливаем dhcpcd..."
        $SUDO systemctl enable dhcpcd
        if ! $SUDO systemctl start dhcpcd; then
            log "WARNING: Не удалось запустить dhcpcd"
        fi
    fi

    # Откатываем DNS
    revert_dns_config
    
    # Даем время на восстановление
    sleep 5
    log "Откат завершен. Проверьте подключение..."
}

# Функция проверки сетевого подключения
check_network_connection() {
    local max_attempts=15
    local attempt=1
    
    log "Проверяем сетевое подключение..."
    
    # Пытаемся определить шлюз по умолчанию
    local gateway=$($SUDO ip route show default | awk '/default/ {print $3}')
    if [[ -z "$gateway" ]]; then
        gateway="8.8.8.8"
    fi
    
    while [ $attempt -le $max_attempts ]; do
        log "Попытка $attempt/$max_attempts: пингую $gateway"
        
        if ping -c 1 -W 2 "$gateway" >/dev/null 2>&1; then
            log "Сетевое подключение активно"
            return 0
        fi
        
        attempt=$((attempt + 1))
        sleep 3
    done
    
    return 1
}

check_internet_connection() {
    local max_attempts=15
    local attempt=1
    
    log "Проверяем Интернет с использованием DNS..."
    
    # Пытаемся определить шлюз по умолчанию
    local gateway="google.com"
 
    while [ $attempt -le $max_attempts ]; do
        log "Попытка $attempt/$max_attempts: пингую $gateway"
        
        if ping -c 1 -W 2 "$gateway" >/dev/null 2>&1; then
            log "Интернет работает с использованием DNS"
            return 0
        fi
        
        attempt=$((attempt + 1))
        sleep 3
    done
    
    return 1
}


# Функция проверки, что мы не останемся без сети
check_rollback_possibility() {
    if [[ "$previous_network_manager" == "inactive" && "$previous_dhcpcd" == "inactive" ]]; then
        log "WARNING: Ни один сетевой демон не был активен. Откат может быть невозможен!"
        read -p "Продолжить? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Отмена пользователем"
            exit 0
        fi
        CAN_ROLLBACK=0
    fi
}

#
# Вариант со статическими /etc/resolv.conf работает, а настройки интерфейса с вты
#
setup_dns_resolving() {
    log "Настраиваем DNS resolving..."
    
    # Удаляем симлинк если существует
    if [ -L "/etc/resolv.conf" ]; then
        $SUDO rm -f /etc/resolv.conf
    fi
    
    # Создаем resolv.conf
    $SUDO bash -c 'cat > /etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
options edns0
search .
EOF'
    
    # Устанавливаем правильные права
    $SUDO chmod 644 /etc/resolv.conf
    
    log "DNS resolving настроен"
}

revert_dns_config() {
    log "Восстанавливаем оригинальную конфигурацию DNS..."
    
    # Удаляем созданный нами файл, если он существует
    if [ -f "/etc/resolv.conf" ]; then
        $SUDO rm -f /etc/resolv.conf
        log "Удален созданный resolv.conf"
    fi
    
    # Восстанавливаем симлинк на systemd-resolved
    if [ ! -L "/etc/resolv.conf" ]; then
        $SUDO ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
        log "Восстановлен симлинк: /etc/resolv.conf -> /run/systemd/resolve/stub-resolv.conf"
    fi
    
    # Проверяем, что симлинк создан правильно
    if [ -L "/etc/resolv.conf" ]; then
        local target=$(readlink -f /etc/resolv.conf)
        log "Проверка: resolv.conf теперь указывает на $target"
    else
        log "WARNING: Не удалось восстановить симлинк resolv.conf"
    fi
    
    # Перезапускаем systemd-resolved если он установлен
    if systemctl list-unit-files | grep -q systemd-resolved.service; then
        $SUDO systemctl restart systemd-resolved 2>/dev/null || true
        log "Перезапущен systemd-resolved"
    fi
    
    log "Конфигурация DNS восстановлена"
}

# Основная логика скрипта
main() {
    # Проверяем права
    if [[ $EUID -eq 0 ]]; then
        log "Запуск с правами root"
    else
        log "Запуск с правами пользователя (будет использоваться sudo)"
        # Проверяем, что sudo доступен
        if ! command -v sudo >/dev/null 2>&1; then
            echo "sudo не установлен. Запустите скрипт от root или установите sudo."
            exit 1
        fi
        # Проверяем, что пользователь имеет права sudo
        if ! $SUDO -n true 2>/dev/null; then
            echo "Требуются права sudo. Запустите скрипт с sudo или добавьте пользователя в sudoers."
            exit 1
        fi
    fi
    
    log "Начало миграции на systemd-networkd"
    
    # Проверяем текущее состояние демонов
    log "Проверяем текущие сетевые демоны..."
    previous_network_manager=$(get_service_status NetworkManager)
    previous_dhcpcd=$(get_service_status dhcpcd)
    
    log "Текущее состояние: NetworkManager: $previous_network_manager, dhcpcd: $previous_dhcpcd"
    
    # Проверяем возможность отката
    check_rollback_possibility
    
    # Проверяем состояние systemd-networkd через systemctl status
    log "Проверяем состояние systemd-networkd..."
    local networkd_status=$(check_systemd_networkd_status)
    
    case "$networkd_status" in
        "active")
            log "systemd-networkd уже установлен и активен"
            ;;
        "installed_inactive")
            log "systemd-networkd установлен, но не активен"
            ;;
        "installed_unknown")
            log "systemd-networkd установлен, но в неизвестном состоянии"
            ;;
        "not_installed")
            log "systemd-networkd не установлен, начинаем установку..."
            install_systemd_networkd
            # После установки проверяем статус еще раз
            networkd_status=$(check_systemd_networkd_status)
            log "Статус systemd-networkd после установки: $networkd_status"
            ;;
        *)
            log "Неизвестный статус systemd-networkd: $networkd_status"
            error_exit "Не удалось определить состояние systemd-networkd"
            ;;
    esac

    # СОЗДАЕМ БАЗОВУЮ КОНФИГУРАЦИЮ WI-FI ПЕРЕД ОСТАНОВКОЙ ДЕМОНОВ
    log "Создаем базовую конфигурацию Wi-Fi..."
    create_basic_network_config
    
    # ПРОВЕРЯЕМ WI-FI ПОДКЛЮЧЕНИЕ ПЕРЕД ПРОДОЛЖЕНИЕМ
    if ! check_wifi_connection; then
        error_exit "Не удалось установить Wi-Fi подключение перед переходом на systemd-networkd"
    fi
    
    # Создаем резервные копии конфигураций
    log "Создаем резервные копии конфигураций..."
    if [[ -d /etc/systemd/network ]]; then
        $SUDO cp -r /etc/systemd/network /etc/systemd/network.backup
        log "Резервная копия создана: /etc/systemd/network.backup"
    else
        $SUDO mkdir -p /etc/systemd/network
        log "Создана директория: /etc/systemd/network"
    fi
    
    log "Останавливаем текущие демоны..."
    
    if [[ "$previous_network_manager" == "active" ]]; then
        log "Останавливаем NetworkManager..."
        $SUDO systemctl stop NetworkManager
        $SUDO systemctl disable NetworkManager
    fi
    
    if [[ "$previous_dhcpcd" == "active" ]]; then
        log "Останавливаем dhcpcd..."
        $SUDO systemctl stop dhcpcd
        $SUDO systemctl disable dhcpcd
    fi
    
    # Короткая пауза
    sleep 2
    
    # Включаем и запускаем systemd-networkd (если он еще не активен)
    if [[ "$networkd_status" != "active" ]]; then
        log "Запускаем systemd-networkd..."
        $SUDO systemctl enable systemd-networkd
        if ! $SUDO systemctl start systemd-networkd; then
            error_exit "Не удалось запустить systemd-networkd"
        fi
        
        # Ждем инициализации с проверками
        for i in {1..10}; do
            if $SUDO systemctl is-active systemd-networkd >/dev/null 2>&1; then
                log "systemd-networkd успешно запущен"
                break
            fi
            sleep 1
            if [ $i -eq 10 ]; then
                error_exit "systemd-networkd не запустился после 10 секунд ожидания"
            fi
        done
    else
        log "systemd-networkd уже активен, перезапускаем для применения настроек..."
        $SUDO systemctl restart systemd-networkd
    fi
    
    # Даем время на применение конфигурации сети
    sleep 3
    
    # Проверяем сетевое подключение
    if ! check_network_connection; then
        error_exit "Сетевое подключение потеряно после переключения на systemd-networkd"
    fi

    setup_dns_resolving

    # Проверяем работу интернет с dns
    if ! check_internet_connection; then
        error_exit "Сетевое подключение потеряно после настройки dns /etc/resolv.conf"
    fi
    
    log "Миграция успешно завершена!"
    
    # Финальные проверки
    log "Текущие сетевые интерфейсы:"
    $SUDO ip addr show
    
    log "Активные сетевые демоны:"
    $SUDO systemctl status systemd-networkd --no-pager -l
    
    echo "================================================================"
    echo "ВНИМАНИЕ: Управление сетью теперь осуществляется через systemd-networkd"
    echo "Конфигурационные файлы находятся в /etc/systemd/network/"
    echo "Резервные копии сохранены в /etc/systemd/network.backup/"
    echo "================================================================"
    
    # Отключаем возможность отката после успешного завершения
    CAN_ROLLBACK=0
}

# Обработка сигналов для аварийного завершения
trap 'error_exit "Скрипт прерван пользователем"' INT TERM

# Запуск основной функции
main

exit 0
