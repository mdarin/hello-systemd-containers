#!/bin/bash

# Включаем IP форвардинг
echo 1 > /proc/sys/net/ipv4/ip_forward

# Очищаем старые правила
iptables -t nat -F
iptables -F

# Настраиваем NAT для выхода в интернет
iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o wlan0 -j MASQUERADE

# Разрешаем форвардинг
iptables -A FORWARD -i veth-host -j ACCEPT
iptables -A FORWARD -o veth-host -j ACCEPT

# Проброс порта 8080 к контейнеру
iptables -t nat -A PREROUTING -i wlan0 -p tcp --dport 8080 -j DNAT --to-destination 10.0.0.2:80
iptables -A FORWARD -p tcp -d 10.0.0.2 --dport 80 -j ACCEPT

# Для доступа к другим портам добавьте аналогичные правила
# iptables -t nat -A PREROUTING -i wlan0 -p tcp --dport 8081 -j DNAT --to-destination 10.0.0.2:8081
iptables -t nat -A PREROUTING -i wlan0 -p tcp --dport 8081 -j DNAT --to-destination 10.0.0.2:59095

echo "NAT and port forwarding configured"
