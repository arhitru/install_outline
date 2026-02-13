#!/bin/bash

set -e  # Прерывать выполнение при ошибке

# ============================================================================
# Конфигурация
# ============================================================================
SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(dirname "$0")
LOG_DIR="/root"
LOG_FILE="${LOG_DIR}/install_outline_vpn.log"
PID_FILE="/var/run/${SCRIPT_NAME}.pid"
LOCK_FILE="/var/lock/${SCRIPT_NAME}.lock"
CONFIG_FILE="/root/outline.conf"
RETRY_COUNT=5

# Режим выполнения (auto/interactive)
if [ "$1" = "--auto" ] || [ "$1" = "-a" ]; then
    AUTO_MODE=1
    export AUTO_MODE
else
    AUTO_MODE=0
    export AUTO_MODE
fi

if [ ! -f "/root/logging_functions.sh" ]; then
    cd /root && wget https://raw.githubusercontent.com/arhitru/fuctions_bash/refs/heads/main/logging_functions.sh >> $LOG_FILE 2>&1 && chmod +x /root/logging_functions.sh
fi
if [ ! -f "/root/install_outline_settings.sh" ]; then
    cd /root && wget https://raw.githubusercontent.com/arhitru/fuctions_bash/refs/heads/main/install_outline_settings.sh >> $LOG_FILE 2>&1 && chmod +x /root/install_outline_settings.sh
fi
if [ ! -f "/root/install_outline_settings.sh" ]; then
    cd /root && wget https://raw.githubusercontent.com/arhitru/install_outline/main/install_outline_for_getdomains.sh -O /root/install_outline.sh >> $LOG_FILE 2>&1 && chmod +x /root/install_outline_for_getdomains.sh
fi

. /root/logging_functions.sh
. /root/install_outline_settings.sh
install_outline_settings

cd /root
wget https://raw.githubusercontent.com/arhitru/install_outline/main/install_outline_for_getdomains.sh -O /root/install_outline.sh
chmod +x /root/install_outline_for_getdomains.sh
/root/install_outline_for_getdomains.sh

log_info 'Restarting Network....'
# Step 13: Restart network
# Этап 13: Перезагружает сеть
/etc/init.d/network restart