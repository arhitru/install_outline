#!/bin/sh

main(){
    SCRIPT_NAME=$(basename "$0")
    SCRIPT_DIR=$(dirname "$0")
    LOG_DIR="/root"
    LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}.log"
    PID_FILE="/var/run/${SCRIPT_NAME}.pid"
    LOCK_FILE="/var/lock/${SCRIPT_NAME}.lock"
    OUTLINE_CONFIG_FILE="/root/outline.conf"
    RETRY_COUNT=5

    # Режим выполнения (auto/interactive)
    if [ "$1" = "--auto" ] || [ "$1" = "-a" ]; then
        AUTO_MODE=1
    else
        AUTO_MODE=0
        # Определяем режим выполнения (интерактивный или автоматический)
        if [ ! -t 0 ]; then
            AUTO_MODE=1
        fi
    fi
    export AUTO_MODE

    # ============================================================================
    # Импорт функций логирования
    # ============================================================================
    if [ ! -f "/root/logging_functions.sh" ]; then
        cd /root && wget https://raw.githubusercontent.com/arhitru/fuctions_bash/refs/heads/main/logging_functions.sh >> $LOG_FILE 2>&1 && chmod +x /root/logging_functions.sh
    fi
    . /root/logging_functions.sh

    # Инициализируем логирование
    init_logging

    # Проверяем что система загрузилась
    log_info "Проверка системы:"
    uptime >> $LOG_FILE 2>&1
    ifconfig >> $LOG_FILE 2>&1

    # Ждем запуска сети
    log_info "Ожидание сети..."
    for i in $(seq 1 30); do
        if ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
            log_success "Сеть доступна"
            break
        fi
        sleep 1
    done

    if [ ! -f "/root/install_outline_settings.sh" ]; then
        cd /root && wget https://raw.githubusercontent.com/arhitru/install_outline/refs/heads/main/install_outline_settings.sh >> $LOG_FILE 2>&1 && chmod +x /root/install_outline_settings.sh
    fi

    . /root/install_outline_settings.sh
    install_outline_settings
    . $OUTLINE_CONFIG_FILE

}

# Запуск основной функции
main "$@"
