#!/bin/bash

# Улучшенный скрипт установки systemd-nspawn и зависимостей для Debian/Ubuntu
# Версия 2.1

set -euo pipefail  # Более строгий режим обработки ошибок

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m' # No Color

# Конфигурация
readonly REQUIRED_PACKAGES=(
    "systemd-container"
    "debootstrap" 
    "qemu-user-static"
    "binfmt-support"
)

readonly OPTIONAL_PACKAGES=(
    "systemd-bootchart"
    "systemd-coredump"
    "busybox"
    "apt-utils"
    "systemd-timesyncd"
)

readonly RECOMMENDED_PACKAGES=(
    "curl"
    "wget"
    "vim"
    "less"
    "locales"
)

# Логирование
readonly LOG_FILE="/tmp/systemd-nspawn-install-$(date +%Y%m%d-%H%M%S).log"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_VERSION="2.1"

# Функции логирования
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    if [[ "$LOG_FILE" != "/dev/null" ]]; then
        echo -e "${timestamp} [${level}] $message" >> "$LOG_FILE"
    fi
    echo -e "${timestamp} [${level}] $message" >&2
}

info() { log "INFO" "${BLUE}${1}${NC}"; }
success() { log "SUCCESS" "${GREEN}${1}${NC}"; }
warning() { log "WARNING" "${YELLOW}${1}${NC}"; }
error() { log "ERROR" "${RED}${1}${NC}"; }
debug() { log "DEBUG" "${CYAN}${1}${NC}"; }

# Функция очистки при выходе
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        warning "Установка прервана с кодом $exit_code. Проверьте лог: $LOG_FILE"
    else
        debug "Очистка ресурсов..."
    fi
    
    # Убиваем фоновые процессы
    jobs -p | xargs -r kill -9 2>/dev/null || true
}

trap cleanup EXIT INT TERM

# Проверка наличия необходимых команд
check_required_commands() {
    local commands=("bash" "sudo" "apt-get" "dpkg" "systemctl")
    local missing_commands=()
    
    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        error "Отсутствуют необходимые команды: ${missing_commands[*]}"
        exit 1
    fi
}

# Проверка совместимости системы
check_compatibility() {
    info "Проверка совместимости системы..."
    
    # Проверка дистрибутива
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        info "Дистрибутив: $NAME Версия: $VERSION" ID: $ID
        
        if [[ ! "$ID" =~ ^(debian|ubuntu)$ ]]; then
            warning "Скрипт тестировался на Debian/Ubuntu, но продолжает работу на ${NAME} с ID:${ID}..."
        fi
    else
        warning "Не удалось определить дистрибутив"
    fi

    # Проверка версии systemd
    local systemd_version
    if systemd_version=$(systemctl --version 2>/dev/null | awk 'NR==1 {print $2}'); then
        if [[ $systemd_version -lt 230 ]]; then
            warning "Обнаружена старая версия systemd ($systemd_version). Рекомендуется версия 230+"
        else
            success "Версия systemd: $systemd_version"
        fi
    else
        error "Systemd не обнаружен или не работает"
        exit 1
    fi

    # Проверка архитектуры
    local arch
    arch=$(uname -m)
    info "Архитектура системы: $arch"
    
    # Проверка свободного места
    local free_space_mb
    free_space_mb=$(df /var/lib --output=avail | awk 'NR==2 {print $1/1024}')
    if [[ $(echo "$free_space_mb < 1024" | bc -l 2>/dev/null || echo "1") -eq 1 ]]; then
        warning "Мало свободного места в /var/lib: ${free_space_mb%.*}MB (рекомендуется минимум 1GB)"
    else
        success "Свободное место в /var/lib: ${free_space_mb%.*}MB"
    fi
    
    # Проверка памяти
    local mem_total
    mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    if [[ $mem_total -lt 1048576 ]]; then  # 1GB в KB
        warning "Мало оперативной памяти: $((mem_total/1024))MB (рекомендуется 1GB+)"
    fi
}

# Проверка прав и запрос пароля
check_privileges() {
    if [[ $EUID -eq 0 ]]; then
        info "Скрипт запущен от root."
        # if ! user_confirmation "Продолжить от root?"; then
        #     exit 1
        # fi
        return
    fi

    # Проверка прав sudo
    if ! sudo -n true 2>/dev/null; then
        info "Требуются права sudo. Введите пароль:"
        if ! sudo -v; then
            error "Не удалось получить права sudo"
            exit 1
        fi
    fi
    
    # Поддержание sudo сессии в фоне
    {
        while true; do
            sudo -n true
            sleep 50
            kill -0 "$$" 2>/dev/null || exit
        done
    } 2>/dev/null &
}

# Функция подтверждения пользователя
user_confirmation() {
    local message="${1:-Продолжить?}"
    local response
    local timeout=30
    
    if [[ "${NONINTERACTIVE:-false}" == "true" ]]; then
        info "Неинтерактивный режим: автоматическое подтверждение"
        return 0
    fi
    
    read -r -t $timeout -p "$message [y/N] " response || {
        warning "Таймаут подтверждения. Продолжаю автоматически..."
        return 0
    }
    
    case "${response,,}" in
        y|yes|д|да) 
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Улучшенная проверка установки пакета
check_package() {
    local package="$1"
    if dpkg -l "$package" 2>/dev/null | grep -q "^ii"; then
        return 0
    elif dpkg -l "$package" 2>/dev/null | grep -q "^hi"; then
        warning "Пакет $package установлен, но требует настройки"
        return 0
    else
        return 1
    fi
}

# Получение размера пакета с кэшированием
declare -A PACKAGE_SIZES
get_package_size() {
    local package="$1"
    
    if [[ -n "${PACKAGE_SIZES[$package]:-}" ]]; then
        echo "${PACKAGE_SIZES[$package]}"
        return
    fi
    
    local size
    size=$(apt-cache show "$package" 2>/dev/null | awk '/^Size:/ {print $2; exit}' || echo "0")
    PACKAGE_SIZES["$package"]=$size
    echo "$size"
}

# Форматирование размера
format_size() {
    local bytes=$1
    if [[ $bytes -gt 1073741824 ]]; then
        echo "$(echo "scale=2; $bytes/1073741824" | bc) GB"
    elif [[ $bytes -gt 1048576 ]]; then
        echo "$(echo "scale=2; $bytes/1048576" | bc) MB"
    elif [[ $bytes -gt 1024 ]]; then
        echo "$(echo "scale=2; $bytes/1024" | bc) KB"
    else
        echo "${bytes} B"
    fi
}

# Прогресс-бар для длительных операций
show_progress() {
    local pid=$1
    local message="${2:-Работаю...}"
    local spin=('⣷' '⣯' '⣟' '⡿' '⢿' '⣻' '⣽' '⣾')
    local i=0
    
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 8 ))
        printf "\r${CYAN}%s${NC} %s" "${spin[$i]}" "$message"
        sleep 0.1
    done
    printf "\r${GREEN}✓${NC} %s\n" "$message"
}

# Установка пакетов с улучшенным выводом
install_packages() {
    local packages=("$@")
    local to_install=()
    local total_size=0
    local download_size=0

    info "Анализ пакетов для установки..."
    
    for package in "${packages[@]}"; do
        if check_package "$package"; then
            success "✓ $package уже установлен"
        else
            if apt-cache show "$package" &>/dev/null; then
                to_install+=("$package")
                local size
                size=$(get_package_size "$package")
                total_size=$((total_size + size))
                download_size=$((download_size + size))
            else
                warning "Пакет $package не найден в репозиториях"
            fi
        fi
    done

    if [[ ${#to_install[@]} -eq 0 ]]; then
        success "Все необходимые пакеты уже установлены!"
        return 0
    fi

    local total_size_formatted
    total_size_formatted=$(format_size $total_size)
    info "Будет установлено ${#to_install[@]} пакетов, размер: $total_size_formatted"
    
    if ! user_confirmation "Продолжить установку?"; then
        exit 0
    fi

    # Обновление репозиториев
    info "Обновление списка пакетов..."
    sudo apt update 2>&1 | tee -a "$LOG_FILE" &
    show_progress $! "Обновление списка пакетов"
    wait $!

    if [[ $? -ne 0 ]]; then
        error "Не удалось обновить список пакетов"
        return 1
    fi

    # Установка пакетов
    info "Установка пакетов..."
    export DEBIAN_FRONTEND=noninteractive
    sudo apt install -y --no-install-recommends "${to_install[@]}" 2>&1 | tee -a "$LOG_FILE" &
    show_progress $! "Установка пакетов"
    wait $!

    if [[ $? -eq 0 ]]; then
        success "Пакеты успешно установлены"
    else
        error "Ошибка установки пакетов"
        return 1
    fi

    # Проверка установки
    local failed_packages=()
    for package in "${to_install[@]}"; do
        if check_package "$package"; then
            success "✓ $package успешно установлен"
        else
            error "Не удалось установить $package"
            failed_packages+=("$package")
        fi
    done

    if [[ ${#failed_packages[@]} -gt 0 ]]; then
        error "Не удалось установить пакеты: ${failed_packages[*]}"
        return 1
    fi
}

# Расширенная проверка systemd-nspawn
check_systemd_nspawn() {
    info "Расширенная проверка systemd-nspawn..."

    # Проверка бинарного файла
    local nspawn_path
    if nspawn_path=$(command -v systemd-nspawn); then
        success "systemd-nspawn найден: $nspawn_path"
    else
        error "systemd-nspawn не найден в PATH"
        return 1
    fi

    # Проверка версии и возможностей
    local version_info
    if version_info=$(systemd-nspawn --version 2>/dev/null); then
        success "Версия systemd-nspawn:"
        echo "$version_info" | head -3 | sed 's/^/  /'
    else
        warning "Не удалось получить версию systemd-nspawn"
    fi

    # Проверка основных функций
    info "Тестирование базовой функциональности..."
    if systemd-nspawn  --no-pager --help | grep -q "CONTAINER"; then
        success "✓ Базовые функции работают"
    else
        error "✗ Проблемы с функциональностью systemd-nspawn"
        return 1
    fi

    # Проверка поддержки сетевых функций
    if systemd-nspawn  --no-pager --help | grep -q "network"; then
        success "✓ Сетевая поддержка доступна"
    else
        warning "⚠ Сетевая поддержка ограничена"
    fi
    
    # Проверка machinectl
    if command -v machinectl >/dev/null; then
        success "✓ machinectl доступен"
    else
        warning "✗ machinectl не найден"
    fi
}

# Проверка дополнительных возможностей
check_additional_features() {
    info "Проверка дополнительных возможностей..."

    # Проверка QEMU
    local qemu_archs=("arm" "aarch64" "x86_64" "i386")
    for arch in "${qemu_archs[@]}"; do
        if command -v "qemu-${arch}-static" >/dev/null; then
            success "✓ qemu-${arch}-static доступен"
        fi
    done

    # Проверка binfmt поддержки
    if [[ -d /proc/sys/fs/binfmt_misc ]] && compgen -G "/proc/sys/fs/binfmt_misc/*" > /dev/null; then
        success "✓ binfmt поддержка активна"
        if [[ -f /proc/sys/fs/binfmt_misc/status ]]; then
            local status=$(cat /proc/sys/fs/binfmt_misc/status)
            info "  Статус binfmt: $status"
        fi
    else
        warning "✗ binfmt поддержка не активна"
    fi

    # Проверка доступных образов
    info "Доступные образы Debian для systemd-nspawn:"
    if command -v debootstrap >/dev/null; then
        debootstrap --version | head -1
    fi
}

# Создание тестового контейнера (опционально)
create_test_container() {
    if user_confirmation "Создать тестовый контейнер для проверки?"; then
        local test_dir="/var/lib/machines/test-container-$(date +%s)"
        info "Создание тестового контейнера в $test_dir..."
        
        sudo mkdir -p "$test_dir"
        
        # Используем минимальную базовую систему
        if sudo debootstrap --variant=minbase --include=systemd,systemd-sysv bullseye "$test_dir" http://deb.debian.org/debian/; then
            success "Тестовый контейнер создан успешно"
            info "Команды для работы:"
            echo "  Запуск: sudo systemd-nspawn -D $test_dir"
            echo "  Просмотр: sudo machinectl list"
            echo "  Удаление: sudo rm -rf $test_dir"
        else
            warning "Не удалось создать тестовый контейнер"
        fi
    fi
}

# Проверка здоровья системы после установки
check_system_health() {
    info "Проверка здоровья системы..."
    
    # Проверка загрузки systemd сервисов
    if systemctl is-active systemd-journald >/dev/null; then
        success "✓ systemd-journald активен"
    else
        warning "✗ systemd-journald не активен"
    fi
    
    # Проверка доступности cgroups
    if mount | grep -q cgroup; then
        success "✓ cgroups доступны"
    else
        warning "✗ cgroups не доступны"
    fi
}

# Вывод сводки установки
show_summary() {
    success "Установка завершена успешно!"
    echo
    echo -e "${GREEN}════════════ СВОДКА УСТАНОВКИ ════════════${NC}"
    echo
    echo -e "${CYAN}Основные команды:${NC}"
    echo -e "  ${MAGENTA}systemd-nspawn${NC} -D /путь/к/контейнеру"
    echo -e "  ${MAGENTA}machinectl${NC} list" 
    echo -e "  ${MAGENTA}debootstrap${NC} --arch=armel bullseye /путь"
    echo
    echo -e "${CYAN}Полезные ссылки:${NC}"
    echo -e "  ${BLUE}Документация:${NC} https://freedesktop.org/systemd/man/systemd-nspawn.html"
    echo -e "  ${BLUE}Debian guide:${NC} https://wiki.debian.org/SystemdNspawn"
    echo
    echo -e "${YELLOW}Лог-файл:${NC} $LOG_FILE"
}

# Вывод справки
show_help() {
    cat << EOF
Установка systemd-nspawn и зависимостей - версия $SCRIPT_VERSION

Использование: $SCRIPT_NAME [ОПЦИИ]

Опции:
  -h, --help          Показать эту справку
  -v, --version       Показать версию
  --minimal           Минимальная установка (только обязательные пакеты)
  --full              Полная установка (включая дополнительные пакеты)
  --recommended       Установка рекомендованных пакетов
  --non-interactive   Неинтерактивный режим (автоматическое подтверждение)
  --no-log            Не создавать лог-файл
  --test-container    Создать тестовый контейнер после установки

Примеры:
  $SCRIPT_NAME --minimal          # Минимальная установка
  $SCRIPT_NAME --full             # Полная установка с тестированием
  $SCRIPT_NAME --non-interactive  # Автоматическая установка

Переменные окружения:
  NONINTERACTIVE=1   # Неинтерактивный режим
  LOG_LEVEL=debug    # Уровень детализации (debug, info, warning, error)
EOF
}

# Основная функция
main() {
    local packages=("${REQUIRED_PACKAGES[@]}")
    local create_test=false
    
    # Разбор аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                echo "Версия: $SCRIPT_VERSION"
                exit 0
                ;;
            --minimal)
                packages=("${REQUIRED_PACKAGES[@]}")
                ;;
            --full)
                packages=("${REQUIRED_PACKAGES[@]}" "${OPTIONAL_PACKAGES[@]}")
                create_test=true
                ;;
            --recommended)
                packages=("${REQUIRED_PACKAGES[@]}" "${RECOMMENDED_PACKAGES[@]}")
                ;;
            --non-interactive)
                export NONINTERACTIVE=true
                ;;
            --no-log)
                LOG_FILE="/dev/null"
                ;;
            --test-container)
                create_test=true
                ;;
            *)
                error "Неизвестный аргумент: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done

    info "Начало установки systemd-nspawn (версия $SCRIPT_VERSION)"
    info "Лог-файл: $LOG_FILE"
    info "Директория скрипта: $SCRIPT_DIR"

    check_required_commands
    check_compatibility
    check_privileges
    install_packages "${packages[@]}"
    check_systemd_nspawn
    check_additional_features
    check_system_health
    
    if [[ "$create_test" == true ]]; then
        create_test_container
    fi

    show_summary
}

# Запуск основной функции только если скрипт выполняется напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
