#!/bin/bash
# check-available-versions.sh

echo "Проверка доступных версий Debian для armel..."

# Проверяем доступные дистрибутивы
echo "Доступные дистрибутивы:"
curl -s http://deb.debian.org/debian/dists/ | grep "href=\"[A-Za-z]" | sed 's/.*href="\([^"]*\).*/\1/' | grep -v "\.\.\|experimental"
echo "=========================================="
# Проверяем доступность armel архитектуры
for distro in bookworm bullseye buster stable; do
    if curl -s --head http://deb.debian.org/debian/dists/$distro/main/binary-armel/ | head -n 1 | grep -q "200"; then
        echo "✓ $distro доступен для armel"
    else
        echo "✗ $distro недоступен для armel"
    fi
done
