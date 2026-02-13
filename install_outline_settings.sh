#!/bin/bash

config_settings() {
    # ============================================================================
    # Конфигурация
    # ============================================================================

    SCRIPT_NAME=$(basename "$0")
    SCRIPT_DIR=$(dirname "$0")
    LOG_DIR="/root"
    LOG_FILE="${LOG_DIR}/install_outline_vpn.log"
    CONFIG_FILE="/root/outline.conf"

    if [ ! -f "/root/logging_functions.sh" ]; then
        cd /root && wget https://raw.githubusercontent.com/arhitru/fuctions_bash/refs/heads/main/logging_functions.sh >> $LOG_FILE 2>&1 && chmod +x /root/logging_functions.sh
    fi

    . /root/logging_functions.sh
    . $CONFIG_FILE
}

install_outline_settings() {
    if [! -f "$CONFIG_FILE" ]; then
        export TUNNEL="tun2socks"
        # Проверка версии OpenWrt
        if [ -f /etc/os-release ]; then
            # shellcheck source=/etc/os-release
            . /etc/os-release
            log_info "Версия OpenWrt: $OPENWRT_RELEASE"
            
            VERSION=$(grep 'VERSION=' /etc/os-release | cut -d'"' -f2)
            VERSION_ID=$(echo "$VERSION" | awk -F. '{print $1}')
            export VERSION_ID
            
            # Проверка совместимости
            if [ "$VERSION_ID" -lt 19 ]; then
                log_warn "Версия OpenWrt ($VERSION_ID) может быть несовместима"
            fi
        else
            VERSION_ID=0
            log_warn "Не удалось определить версию OpenWrt"
        fi

        # Считывает пользовательскую переменную для конфигурации Outline (Shadowsocks)
        read -p "Enter Outline (Shadowsocks) Config (format ss://base64coded@HOST:PORT/?outline=1): " OUTLINECONF
        export  OUTLINECONF=$OUTLINECONF
        printf "\033[33mConfigure DNSCrypt2 or Stubby? It does matter if your ISP is spoofing DNS requests\033[0m\n"
        echo "Select:"
        echo "1) No [Default]"
        echo "2) DNSCrypt2 (10.7M)"
        echo "3) Stubby (36K)"

        while true; do
        read -r -p '' DNS_RESOLVER
            case $DNS_RESOLVER in 

            1) 
                echo "Skiped"
                break
                ;;

            2)
                export DNS_RESOLVER="DNSCRYPT"
                break
                ;;

            3) 
                export DNS_RESOLVER="STUBBY"
                break
                ;;

            *)
                echo "Choose from the following options"
                ;;
            esac
        done

        printf "\033[33mChoose you country\033[0m\n"
        echo "Select:"
        echo "1) Russia inside. You are inside Russia"
        echo "2) Russia outside. You are outside of Russia, but you need access to Russian resources"
        echo "3) Ukraine. uablacklist.net list"
        echo "4) Skip script creation"

        while true; do
        read -r -p '' COUNTRY
            case $COUNTRY in 

            1) 
                export COUNTRY="russia_inside"
                break
                ;;

            2)
                export COUNTRY="russia_outside"
                break
                ;;

            3) 
                export COUNTRY="ukraine"
                break
                ;;

            4) 
                echo "Skiped"
                export COUNTRY=0
                break
                ;;

            *)
                echo "Choose from the following options"
                ;;
            esac
        done
        # Ask user to use Outline as default gateway
        # Задает вопрос пользователю о том, следует ли использовать Outline в качестве шлюза по умолчанию
        if [ "$DEFAULT_GATEWAY" = "y" ] || [ "$DEFAULT_GATEWAY" = "Y" ]; then
            export OUTLINE_DEFAULT_GATEWAY=$DEFAULT_GATEWAY
        fi
        log_info "Файл конфигурации Outline"
        cat > "$CONFIG_FILE" << 'EOF'
# ============================================================================
# Конфигурация outline_vpn
# ============================================================================

TUNNEL="tun2socks"
OUTLINECONF=$OUTLINECONF
DNS_RESOLVER=$DNS_RESOLVER
COUNTRY=$COUNTRY
OUTLINE_DEFAULT_GATEWAY=$DEFAULT_GATEWAY
VERSION_ID=$VERSION_ID

EOF
        log_info "Создан файл конфигурации по умолчанию: $CONFIG_FILE"
    fi
}

# Проверка: файл запущен напрямую или импортирован
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Прямой запуск - выполняем тесты или демо
    config_settings
    install_outline_settings
else
    # Импортирован через source - только определяем функции
    return 0 2>/dev/null
fi