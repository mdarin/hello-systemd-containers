#!/bin/bash

# Цвета
BLUE='\033[0;94m'
LIGHT_BLUE='\033[1;97m'
DARK_GRAY='\033[0;90m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Глобальные переменные
ALL_STEPS=()
CURRENT_STEP=0

# Функции вывода
add_step() { ALL_STEPS+=("STEP:$1"); }
add_info() { ALL_STEPS+=("INFO:$1"); }
add_cmd() { ALL_STEPS+=("CMD:$1"); }
mark_success() { ALL_STEPS+=("SUCCESS:${1#CMD:}"); }
mark_error() { ALL_STEPS+=("ERROR:${1#CMD:}"); }

# Перерисовка экрана
redraw() {
    clear
    for step in "${ALL_STEPS[@]}"; do
        local type="${step%%:*}"
        local text="${step#*:}"
        
        case $type in
            "STEP") echo -e "${BLUE}$text${NC}" ;;
            "INFO") echo -e "${DARK_GRAY}$text${NC}" ;;
            "CMD") echo -e "${LIGHT_BLUE}▶ $text${NC}" ;;
            "SUCCESS") echo -e "${GREEN}✓ $text${NC}" ;;
            "ERROR") echo -e "${RED}✗ $text${NC}" ;;
        esac
    done
}

# Выполнение команды с сохранением вывода
run_command() {
    local cmd="$1"
    local desc="$2"
    
    add_cmd "$desc"
    redraw
    
    # Выполняем команду и захватываем вывод
    local output
    output=$(eval "$cmd" 2>&1)
    local exit_code=$?
    
    # Удаляем команду из списка и добавляем результат
    unset 'ALL_STEPS[${#ALL_STEPS[@]}-1]'
    if [ $exit_code -eq 0 ]; then
        mark_success "CMD:$desc"
    else
        mark_error "CMD:$desc"
    fi
    
    redraw
    
    # Показываем вывод команды (последние 10 строк)
    if [ -n "$output" ]; then
        echo -e "${DARK_GRAY}--- Вывод команды ---${NC}"
        echo "$output" | tail -n 10 | while read -r line; do
            echo -e "${DARK_GRAY}$line${NC}"
        done
        echo -e "${DARK_GRAY}-------------------${NC}"
        ALL_STEPS+=("INFO:Вывод команды '$desc'")
    fi
    
    redraw
    return $exit_code
}

# Пример использования
main() {
    add_step "Начинаем настройку Wi-Fi для работы с мостом..."
    redraw
    sleep 1
    
    add_info "Оригинальный статус wpa_supplicant: active"
    redraw
    sleep 1
    
    add_step "Останавливаем wpa_supplicant..."
    redraw
    sleep 1
    
    run_command "
        for i in {1..12}; do
            echo 'Processing item \$i - это длинная строка вывода команды'
            sleep 0.1
        done
    " "Запускаем sudo apt update"
    
    run_command "echo 'Быстрая команда'" "Проверяем конфигурацию"
    run_command "apt update" "Обновляем зависимости"
    
    add_step "Настройка завершена успешно!"
    redraw
}

trap 'clear; echo -e "${RED}Прервано${NC}"; exit 1' INT
main "$@"
