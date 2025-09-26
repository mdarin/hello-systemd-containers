#!/bin/bash
# check-armv6-compatibility.sh

echo "Проверка совместимости ARMv6l..."

# Проверяем доступные репозитории для armel
echo "Доступные архитектуры:"
curl -s http://deb.debian.org/debian/dists/stable/main/ | grep "Contents-armel"

# Проверяем наличие пакетов
echo "Проверка пакетов для armel:"
curl -s http://deb.debian.org/debian/dists/stable/main/binary-armel/Packages.gz | gunzip | grep -m 5 "Package: nginx"
