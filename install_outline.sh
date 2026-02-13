set -e  # Прерывать выполнение при ошибке

# ============================================================================
# Конфигурация
# ============================================================================
SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(dirname "$0")
LOG_DIR="/root"
LOG_FILE="${LOG_DIR}/install_outline_vpn_$(date +%Y%m%d_%H%M%S).log"
PID_FILE="/var/run/${SCRIPT_NAME}.pid"
LOCK_FILE="/var/lock/${SCRIPT_NAME}.lock"
CONFIG_FILE="${SCRIPT_DIR}/outline.conf"
RETRY_COUNT=5

# Режим выполнения (auto/interactive)
if [ "$1" = "--auto" ] || [ "$1" = "-a" ]; then
    AUTO_MODE=1
    export AUTO_MODE
else
    AUTO_MODE=0
    export AUTO_MODE
fi

# ============================================================================
# Функции логирования
# ============================================================================
init_logging() {
    # Создаем директорию для логов если её нет
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
    fi
    
    # Перенаправляем весь вывод в лог-файл и в syslog
    exec 3>&1 4>&2
    exec 1> >(tee -a "$LOG_FILE" | logger -t "$SCRIPT_NAME" -p user.info)
    exec 2> >(tee -a "$LOG_FILE" | logger -t "$SCRIPT_NAME" -p user.err)
    
    echo "================================================================================"
    echo "=== Начало установки: $(date) ==="
    echo "=== Режим выполнения: $([ $AUTO_MODE -eq 1 ] && echo "AUTO" || echo "INTERACTIVE") ==="
    echo "=== Лог-файл: $LOG_FILE ==="
    echo "================================================================================"
}

log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1"
    printf "\033[32;1m[INFO] %s\033[0m\n" "$1" >&3 2>/dev/null || true
}

log_warn() {
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $1"
    printf "\033[33;1m[WARN] %s\033[0m\n" "$1" >&3 2>/dev/null || true
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1"
    printf "\033[31;1m[ERROR] %s\033[0m\n" "$1" >&3 2>/dev/null || true
}

log_success() {
    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $1"
    printf "\033[34;1m[SUCCESS] %s\033[0m\n" "$1" >&3 2>/dev/null || true
}

log_debug() {
    if [ "$DEBUG" = "1" ]; then
        echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - $1"
        printf "\033[36;1m[DEBUG] %s\033[0m\n" "$1" >&3 2>/dev/null || true
    fi
}

# ============================================================================
# Функции управления выполнением
# ============================================================================
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "Этот скрипт должен выполняться от root"
        exit 1
    fi
}

check_single_instance() {
    if [ -f "$LOCK_FILE" ]; then
        if kill -0 "$(cat "$LOCK_FILE")" 2>/dev/null; then
            log_error "Скрипт уже запущен (PID: $(cat "$LOCK_FILE"))"
            exit 1
        else
            log_warn "Обнаружен устаревший lock-файл, удаляем"
            rm -f "$LOCK_FILE"
        fi
    fi
    
    echo $$ > "$LOCK_FILE"
    trap 'rm -f "$LOCK_FILE" "$PID_FILE"; log_info "Скрипт завершен"; exec 1>&3 2>&4' EXIT
    echo $$ > "$PID_FILE"
}

load_config() {
    . "$CONFIG_FILE"
}
# ============================================================================
# Функции проверки системы
# ============================================================================
check_system() {
    log_info "=== Проверка системы ==="
    
    # Проверка модели устройства
    if [ -f /tmp/sysinfo/model ]; then
        MODEL=$(cat /tmp/sysinfo/model)
        log_info "Модель устройства: $MODEL"
    else
        MODEL="Unknown"
        log_warn "Не удалось определить модель устройства"
    fi
    
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
    
    # Проверка свободного места
    check_disk_space
    
    # Проверка интернета
    check_internet
    
    # Проверка синхронизации времени
    check_time_sync
}

check_disk_space() {
    local free_space
    free_space=$(df /overlay | awk 'NR==2 {print $4}')
    local free_space_mb=$((free_space / 1024))
    
    log_info "Свободное место на overlay: ${free_space_mb}MB"
    
    if [ "$free_space_mb" -lt 10 ]; then
        log_error "Недостаточно свободного места (<10MB). Требуется минимум 20MB"
        exit 1
    elif [ "$free_space_mb" -lt 20 ]; then
        log_warn "Мало свободного места (<20MB). Установка может не завершиться успешно"
        if [ $AUTO_MODE -eq 0 ]; then
            echo -n "Продолжить? (y/N): " >&3
            read -r answer
            if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
                exit 1
            fi
        fi
    fi
}

check_internet() {
    log_info "Проверка подключения к интернету..."
    
    local test_hosts="openwrt.org google.com cloudflare.com"
    local connected=0
    
    for host in $test_hosts; do
        if ping -c 1 -W 3 "$host" >/dev/null 2>&1; then
            log_info "Подключение к $host успешно"
            connected=1
            break
        fi
    done
    
    if [ $connected -eq 0 ]; then
        log_error "Нет подключения к интернету"
        return 1
    fi
    
    return 0
}

check_time_sync() {
    log_info "Проверка синхронизации времени..."
    
    local current_year
    current_year=$(date +%Y)
    
    if [ "$current_year" -lt 2023 ]; then
        log_warn "Время не синхронизировано: $(date)"
        
        if [ $AUTO_MODE -eq 1 ]; then
            log_info "Автоматическая синхронизация времени..."
            for ntp_server in $NTP_SERVERS; do
                if ntpd -n -q -p "$ntp_server" >/dev/null 2>&1; then
                    log_success "Время синхронизировано с $ntp_server"
                    break
                fi
            done
        else
            echo -n "Синхронизировать время? (Y/n): " >&3
            read -r answer
            if [ "$answer" != "n" ] && [ "$answer" != "N" ]; then
                for ntp_server in $NTP_SERVERS; do
                    if ntpd -n -q -p "$ntp_server" >/dev/null 2>&1; then
                        log_success "Время синхронизировано с $ntp_server"
                        break
                    fi
                done
            fi
        fi
    else
        log_info "Время синхронизировано: $(date)"
    fi
}

# ============================================================================
# Функции работы с opkg
# ============================================================================
configure_opkg() {
    log_info "Настройка opkg..."
    
    # Сохранение списков пакетов на extroot
    if grep -q "^lists_dir\s*ext\s*/usr/lib/opkg/lists" /etc/opkg.conf 2>/dev/null; then
        log_info "Конфигурация opkg уже настроена"
    else
        sed -i -r -e "s/^(lists_dir\sext\s).*/\1\/usr\/lib\/opkg\/lists/" /etc/opkg.conf
        log_success "Конфигурация opkg обновлена"
    fi
}

update_opkg() {
    log_info "Обновление списков пакетов..."

    local retry=0
    while [ $retry -lt $RETRY_COUNT ]; do
        if opkg update > /tmp/opkg_update.log 2>&1; then
            log_success "Списки пакетов успешно обновлены"
            cat /tmp/opkg_update.log >> "$LOG_FILE"
            rm -f /tmp/opkg_update.log
            return 0
        else
            retry=$((retry + 1))
            log_warn "Попытка $retry из $RETRY_COUNT не удалась"
            sleep 5
        fi
    done
    
    log_error "Не удалось обновить списки пакетов после $RETRY_COUNT попыток"
    cat /tmp/opkg_update.log >> "$LOG_FILE"
    rm -f /tmp/opkg_update.log
    return 1
}

install_package() {
    local pkg=$1
    local retry=0
    
    if opkg list-installed | grep -q "^$pkg "; then
        log_info "Пакет $pkg уже установлен"
        return 0
    fi
    
    log_info "Установка пакета: $pkg"
    
    while [ $retry -lt $RETRY_COUNT ]; do
        if opkg install "$pkg" > /tmp/opkg_install.log 2>&1; then
            cat /tmp/opkg_install.log >> "$LOG_FILE"
            log_success "Пакет $pkg успешно установлен"
            rm -f /tmp/opkg_install.log
            return 0
        else
            retry=$((retry + 1))
            log_warn "Попытка $retry из $RETRY_COUNT установки $pkg не удалась"
            sleep 5
        fi
    done
    
    log_error "Не удалось установить пакет $pkg после $RETRY_COUNT попыток"
    cat /tmp/opkg_install.log >> "$LOG_FILE"
    rm -f /tmp/opkg_install.log
    
    if [ $AUTO_MODE -eq 0 ]; then
        echo -n "Продолжить выполнение? (y/N): " >&3
        read -r answer
        if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
            exit 1
        fi
    fi
    
    return 1
}

export TUNNEL="tun2socks"
# Считывает пользовательскую переменную для конфигурации Outline (Shadowsocks)
read -p "Enter Outline (Shadowsocks) Config (format ss://base64coded@HOST:PORT/?outline=1): " OUTLINECONF
export  OUTLINECONF=$OUTLINECONF
# Ask user to use Outline as default gateway
# Задает вопрос пользователю о том, следует ли использовать Outline в качестве шлюза по умолчанию
while [ "$DEFAULT_GATEWAY" != "y" ] && [ "$DEFAULT_GATEWAY" != "n" ]; do
    read -p "Use Outline as default gateway? [y/n]: " DEFAULT_GATEWAY
    export OUTLINE_DEFAULT_GATEWAY=$DEFAULT_GATEWAY
done

cd /tmp
wget https://raw.githubusercontent.com/arhitru/install_outline/main/install_outline_for_getdomains.sh -O install_outline.sh
chmod +x install_outline_for_getdomains.sh
./install_outline_for_getdomains.sh

echo 'Restarting Network....'
# Step 13: Restart network
# Этап 13: Перезагружает сеть
/etc/init.d/network restart