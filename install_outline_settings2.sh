#!/bin/bash

install_outline_settings() {
    if [ ! -f "$OUTLINE_CONFIG_FILE" ]; then
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
        log_question "Enter Outline (Shadowsocks) Config (format ss://base64coded@HOST:PORT/?outline=1): "
        read OUTLINECONF
        export  OUTLINECONF=$OUTLINECONF

        log_question "Configure DNSCrypt2 or Stubby? It does matter if your ISP is spoofing DNS requests"
        log_question "Select:"
        log_question "1) No [Default]"
        log_question "2) DNSCrypt2 (10.7M)"
        log_question "3) Stubby (36K)"

        while true; do
        read -r -p '' DNS_RESOLVER
            case $DNS_RESOLVER in 

            1) 
                log_info "Skiped"
                break
                ;;

            2)
                log_info "DNSCRYPT"
                export DNS_RESOLVER="DNSCRYPT"
                break
                ;;

            3) 
                log_info "STUBBY"
                export DNS_RESOLVER="STUBBY"
                break
                ;;

            *)
                log_warn "Choose from the following options"
                ;;
            esac
        done

        log_question "Choose you country"
        log_question "Select:"
        log_question "1) Russia inside. You are inside Russia"
        log_question "2) Russia outside. You are outside of Russia, but you need access to Russian resources"
        log_question "3) Ukraine. uablacklist.net list"
        log_question "4) Skip script creation"

        while true; do
        read -r -p '' COUNTRY
            case $COUNTRY in 

            1) 
                log_info "Russia inside. You are inside Russia"
                export COUNTRY="russia_inside"
                break
                ;;

            2)
                log_info "Russia outside. You are outside of Russia, but you need access to Russian resources"
                export COUNTRY="russia_outside"
                break
                ;;

            3) 
                log_info "Ukraine. uablacklist.net list"
                export COUNTRY="ukraine"
                break
                ;;

            4) 
                log_warn "Skiped"
                export COUNTRY=0
                break
                ;;

            *)
                log_warn "Choose from the following options"
                ;;
            esac
        done
        # Ask user to use Outline as default gateway
        # Задает вопрос пользователю о том, следует ли использовать Outline в качестве шлюза по умолчанию
        log_question "Use Outline as default gateway? [y/N]: "
        read DEFAULT_GATEWAY
        if [ "$DEFAULT_GATEWAY" = "y" ] || [ "$DEFAULT_GATEWAY" = "Y" ]; then
            export OUTLINE_DEFAULT_GATEWAY=$DEFAULT_GATEWAY
        fi
        log_info "Файл конфигурации Outline"
        cat > "$OUTLINE_CONFIG_FILE" << EOF
# ============================================================================
# Конфигурация outline_vpn
# ============================================================================

TUNNEL="tun2socks"
OUTLINECONF=$OUTLINECONF
DNS_RESOLVER=$DNS_RESOLVER
COUNTRY=$COUNTRY
OUTLINE_DEFAULT_GATEWAY=$DEFAULT_GATEWAY
VERSION_ID=$VERSION_ID

# Список обязательных пакетов
REQUIRED_PACKAGES="
curl
nano
kmod-tun
ip-full
"

# Пакеты для замены
REPLACE_PACKAGES="
dnsmasq:dnsmasq-full
"

# Таймаут для операций (секунды)
OPKG_TIMEOUT=300

# Количество попыток при ошибке
RETRY_COUNT=3

# Режим отладки (0/1)
DEBUG=0
EOF
        log_info "Создан файл конфигурации по умолчанию: $OUTLINE_CONFIG_FILE"
    fi
}