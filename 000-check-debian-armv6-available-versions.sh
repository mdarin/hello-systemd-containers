#!/bin/bash
# check-available-versions.sh

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m' # No Color

echo -e "Проверка доступных версий Debian для ${YELLOW}armel${NC}..."

# Проверяем доступные дистрибутивы
echo "Доступные дистрибутивы:"
curl -s http://deb.debian.org/debian/dists/ | grep "href=\"[A-Za-z]" | sed 's/.*href="\([^"]*\).*/\1/' | grep -v "\.\.\|experimental"
echo -e "─────────────────────────────────────────────────────────────────────"
# Проверяем доступность armel архитектуры
for distro in bookworm bullseye buster stable; do
    if curl -s --head http://deb.debian.org/debian/dists/$distro/main/binary-armel/ | head -n 1 | grep -q "200"; then
        echo -e "✓ ${GREEN}$distro${NC} доступен для armel"
    else
        echo -e "✗ ${RED}$distro${NC} недоступен для armel"
    fi
done
