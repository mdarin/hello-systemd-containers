#!/bin/bash

# TODO: Prototype!

# Однострочные команды для быстрого использования
# Простая проверка и включение
# [ $(cat /proc/sys/net/ipv4/ip_forward) -eq 0 ] && echo 1 > /proc/sys/net/ipv4/ip_forward && echo "Enabled" || echo "Already enabled"

# Проверка и включение IP форвардинга
echo "=== Checking IP Forwarding ==="
IP_FORWARD_FILE="/proc/sys/net/ipv4/ip_forward"

if [ -f "$IP_FORWARD_FILE" ]; then
    CURRENT_VALUE=$(cat "$IP_FORWARD_FILE")
    if [ "$CURRENT_VALUE" -eq 0 ]; then
        echo "Enabling IP forwarding..."
        echo 1 > "$IP_FORWARD_FILE"
        echo "✓ IP forwarding enabled"
    else
        echo "✓ IP forwarding already enabled"
    fi
else
    echo "✗ Cannot access $IP_FORWARD_FILE"
    exit 1
fi

# Очищаем старые правила
iptables -F
iptables -t nat -F

# Настраиваем интерфейс на хосте
ip link set ve-app-webuXtIV up
ip addr add 10.0.0.1/24 dev ve-app-webuXtIV 2>/dev/null || echo "IP already exists"

# NAT для выхода в интернет
iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o wlan0 -j MASQUERADE

# Разрешаем форвардинг
iptables -A FORWARD -i ve-app-webuXtIV -o wlan0 -j ACCEPT
iptables -A FORWARD -i wlan0 -o ve-app-webuXtIV -j ACCEPT

# Проброс порта 8080 из локальной сети к контейнеру
iptables -t nat -A PREROUTING -i wlan0 -p tcp --dport 8080 -j DNAT --to-destination 10.0.0.2:59095
iptables -A FORWARD -p tcp -d 10.0.0.2 --dport 80 -j ACCEPT

# Проброс других портов при необходимости
# iptables -t nat -A PREROUTING -i wlan0 -p tcp --dport 8081 -j DNAT --to-destination 10.0.0.2:8081
# iptables -A FORWARD -p tcp -d 10.0.0.2 --dport 8081 -j ACCEPT

# Проверяем iptables
sudo iptables -t nat -L -n
echo 
sudo iptables -L -n

echo "Network setup completed for existing interfaces"
echo "Host interface: ve-app-webuXtIV (10.0.0.1)"
echo "Container interface: host0 (10.0.0.2)"
