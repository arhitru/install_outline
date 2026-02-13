#!/bin/sh
# Outline scripted, xjasonlyu/tun2socks based installer for OpenWRT.
# https://github.com/1andrevich/outline-install-wrt
# https://raw.githubusercontent.com/itdoginfo/ansible-openwrt-hirkn/master/getdomains-install.sh

# ============================================================================
# Конфигурация
# ============================================================================
route_vpn () {
    cat << EOF > /etc/hotplug.d/iface/30-vpnroute
#!/bin/sh

sleep 10
ip route add table vpn default dev tun1
EOF

    cp /etc/hotplug.d/iface/30-vpnroute /etc/hotplug.d/net/30-vpnroute
}

add_mark() {
    grep -q "99 vpn" /etc/iproute2/rt_tables || echo '99 vpn' >> /etc/iproute2/rt_tables
    
    if ! uci show network | grep -q mark0x1; then
        printf "\033[32;1mConfigure mark rule\033[0m\n"
        uci add network rule
        uci set network.@rule[-1].name='mark0x1'
        uci set network.@rule[-1].mark='0x1'
        uci set network.@rule[-1].priority='100'
        uci set network.@rule[-1].lookup='vpn'
        uci commit
    fi
}

remove_forwarding() {
    if [ ! -z "$forward_id" ]; then
        while uci -q delete firewall.@forwarding[$forward_id]; do :; done
    fi
}

# Check for existing config /etc/config/firewall then add entry
# Проверяет наличие конфигурации в /etc/config/firewall и добавляет запись
add_zone() {
    if  uci show firewall | grep -q "@zone.*name='$TUNNEL'"; then
        log_info "Zone already exist"
    else
        log_info "Create zone"

        # Delete exists zone
        zone_tun_id=$(uci show firewall | grep -E '@zone.*tun0' | awk -F '[][{}]' '{print $2}' | head -n 1)
        if [ "$zone_tun_id" == 0 ] || [ "$zone_tun_id" == 1 ]; then
            log_warn "tun0 zone has an identifier of 0 or 1. That's not ok. Fix your firewall. lan and wan zones should have identifiers 0 and 1."
            exit 1
        fi
        if [ ! -z "$zone_tun_id" ]; then
            while uci -q delete firewall.@zone[$zone_tun_id]; do :; done
        fi

        uci add firewall zone
        uci set firewall.@zone[-1].name="$TUNNEL"
        uci set firewall.@zone[-1].device='tun1'
        uci set firewall.@zone[-1].forward='REJECT'
        uci set firewall.@zone[-1].output='ACCEPT'
        uci set firewall.@zone[-1].input='REJECT'
        uci set firewall.@zone[-1].masq='1'
        uci set firewall.@zone[-1].mtu_fix='1'
        uci set firewall.@zone[-1].family='ipv4'
        uci commit firewall
    fi
    
    if  uci show firewall | grep -q "@forwarding.*name='$TUNNEL-lan'"; then
        log_info "Forwarding already configured"
    else
        log_info "Configured forwarding"
        # Delete exists forwarding
        forward_id=$(uci show firewall | grep -E "@forwarding.*dest='tun2socks'" | awk -F '[][{}]' '{print $2}' | head -n 1)
        remove_forwarding

        uci add firewall forwarding
        uci set firewall.@forwarding[-1]=forwarding
        uci set firewall.@forwarding[-1].name="$TUNNEL-lan"
        uci set firewall.@forwarding[-1].dest="$TUNNEL"
        uci set firewall.@forwarding[-1].src='lan'
        uci set firewall.@forwarding[-1].family='ipv4'
        uci commit firewall
    fi
}

install_pkg(){
    # Check for kmod-tun 
    # Проверяет наличие kmod-tun
    if opkg list-installed | grep -q kmod-tun; then
        log_info "kmod-tun already installed"
    else
        log_info "Installed kmod-tun"
        opkg install kmod-tun
    fi

    # Check for ip-full
    # Проверяет наличие ip-full
    if opkg list-installed | grep -q ip-full; then
        printf "\033[32;1mip-full already installed\033[0m\n"
    else
        echo "Installed ip-full"
        opkg install ip-full
    fi
}

dnsmasqfull() {
    if opkg list-installed | grep -q dnsmasq-full; then
        printf "\033[32;1mdnsmasq-full already installed\033[0m\n"
    else
        printf "\033[32;1mInstalled dnsmasq-full\033[0m\n"
        cd /tmp/ && opkg download dnsmasq-full
        opkg remove dnsmasq && opkg install dnsmasq-full --cache /tmp/

        [ -f /etc/config/dhcp-opkg ] && cp /etc/config/dhcp /etc/config/dhcp-old && mv /etc/config/dhcp-opkg /etc/config/dhcp
    fi
}

dnsmasqconfdir() {
    if [ -n "$VERSION_ID" ] && [ "$VERSION_ID" -ge 24 ] 2>/dev/null; then
        if uci get dhcp.@dnsmasq[0].confdir | grep -q /tmp/dnsmasq.d; then
            printf "\033[32;1mconfdir already set\033[0m\n"
        else
            printf "\033[32;1mSetting confdir\033[0m\n"
            uci set dhcp.@dnsmasq[0].confdir='/tmp/dnsmasq.d'
            uci commit dhcp
        fi
    fi
}

add_set() {
    if uci show firewall | grep -q "@ipset.*name='vpn_domains'"; then
        printf "\033[32;1mSet already exist\033[0m\n"
    else
        printf "\033[32;1mCreate set\033[0m\n"
        uci add firewall ipset
        uci set firewall.@ipset[-1].name='vpn_domains'
        uci set firewall.@ipset[-1].match='dst_net'
        uci commit
    fi
    if uci show firewall | grep -q "@rule.*name='mark_domains'"; then
        printf "\033[32;1mRule for set already exist\033[0m\n"
    else
        printf "\033[32;1mCreate rule set\033[0m\n"
        uci add firewall rule
        uci set firewall.@rule[-1]=rule
        uci set firewall.@rule[-1].name='mark_domains'
        uci set firewall.@rule[-1].src='lan'
        uci set firewall.@rule[-1].dest='*'
        uci set firewall.@rule[-1].proto='all'
        uci set firewall.@rule[-1].ipset='vpn_domains'
        uci set firewall.@rule[-1].set_mark='0x1'
        uci set firewall.@rule[-1].target='MARK'
        uci set firewall.@rule[-1].family='ipv4'
        uci commit
    fi
}

add_dns_resolver() {
    DISK=$(df -m / | awk 'NR==2{ print $2 }')
    if [[ "$DISK" -lt 32 ]]; then 
        printf "\033[31;1mYour router a disk have less than 32MB. It is not recommended to install DNSCrypt, it takes 10MB\033[0m\n"
    fi


    if [ "$DNS_RESOLVER" == 'DNSCRYPT' ]; then
        if opkg list-installed | grep -q dnscrypt-proxy2; then
            printf "\033[32;1mDNSCrypt2 already installed\033[0m\n"
        else
            printf "\033[32;1mInstalled dnscrypt-proxy2\033[0m\n"
            opkg install dnscrypt-proxy2
            if grep -q "# server_names" /etc/dnscrypt-proxy2/dnscrypt-proxy.toml; then
                sed -i "s/^# server_names =.*/server_names = [\'google\', \'cloudflare\', \'scaleway-fr\', \'yandex\']/g" /etc/dnscrypt-proxy2/dnscrypt-proxy.toml
            fi

            printf "\033[32;1mDNSCrypt restart\033[0m\n"
            service dnscrypt-proxy restart
            printf "\033[32;1mDNSCrypt needs to load the relays list. Please wait\033[0m\n"
            sleep 30

            if [ -f /etc/dnscrypt-proxy2/relays.md ]; then
                uci set dhcp.@dnsmasq[0].noresolv="1"
                uci -q delete dhcp.@dnsmasq[0].server
                uci add_list dhcp.@dnsmasq[0].server="127.0.0.53#53"
                uci add_list dhcp.@dnsmasq[0].server='/use-application-dns.net/'
                uci commit dhcp
                
                printf "\033[32;1mDnsmasq restart\033[0m\n"

                /etc/init.d/dnsmasq restart
            else
                printf "\033[31;1mDNSCrypt not download list on /etc/dnscrypt-proxy2. Repeat install DNSCrypt by script.\033[0m\n"
            fi
    fi

    fi

    if [ "$DNS_RESOLVER" == 'STUBBY' ]; then
        printf "\033[32;1mConfigure Stubby\033[0m\n"

        if opkg list-installed | grep -q stubby; then
            printf "\033[32;1mStubby already installed\033[0m\n"
        else
            printf "\033[32;1mInstalled stubby\033[0m\n"
            opkg install stubby

            printf "\033[32;1mConfigure Dnsmasq for Stubby\033[0m\n"
            uci set dhcp.@dnsmasq[0].noresolv="1"
            uci -q delete dhcp.@dnsmasq[0].server
            uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#5453"
            uci add_list dhcp.@dnsmasq[0].server='/use-application-dns.net/'
            uci commit dhcp

            printf "\033[32;1mDnsmasq restart\033[0m\n"

            /etc/init.d/dnsmasq restart
        fi
    fi
}

add_packages() {
    for package in curl nano; do
        if opkg list-installed | grep -q "^$package "; then
            printf "\033[32;1m$package already installed\033[0m\n"
        else
            printf "\033[32;1mInstalling $package...\033[0m\n"
            opkg install "$package"
            
            if "$package" --version >/dev/null 2>&1; then
                printf "\033[32;1m$package was successfully installed and available\033[0m\n"
            else
                printf "\033[31;1mError: failed to install $package\033[0m\n"
                exit 1
            fi
        fi
    done
}

add_getdomains() {
    if [ "$COUNTRY" == 'russia_inside' ]; then
        EOF_DOMAINS=DOMAINS=https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Russia/inside-dnsmasq-nfset.lst
    elif [ "$COUNTRY" == 'russia_outside' ]; then
        EOF_DOMAINS=DOMAINS=https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Russia/outside-dnsmasq-nfset.lst
    elif [ "$COUNTRY" == 'ukraine' ]; then
        EOF_DOMAINS=DOMAINS=https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Ukraine/inside-dnsmasq-nfset.lst
    fi

    if [ "$COUNTRY" != '0' ]; then
        printf "\033[32;1mCreate script /etc/init.d/getdomains\033[0m\n"

cat << EOF > /etc/init.d/getdomains
#!/bin/sh /etc/rc.common

START=99

start () {
    $EOF_DOMAINS
EOF
cat << 'EOF' >> /etc/init.d/getdomains
    count=0
    while true; do
        if curl -m 3 github.com; then
            curl -f $DOMAINS --output /tmp/dnsmasq.d/domains.lst
            break
        else
            echo "GitHub is not available. Check the internet availability [$count]"
            count=$((count+1))
        fi
    done

    if dnsmasq --conf-file=/tmp/dnsmasq.d/domains.lst --test 2>&1 | grep -q "syntax check OK"; then
        /etc/init.d/dnsmasq restart
    fi
}
EOF

        chmod +x /etc/init.d/getdomains
        /etc/init.d/getdomains enable

        if crontab -l | grep -q /etc/init.d/getdomains; then
            printf "\033[32;1mCrontab already configured\033[0m\n"

        else
            crontab -l | { cat; echo "0 */8 * * * /etc/init.d/getdomains start"; } | crontab -
            printf "\033[32;1mIgnore this error. This is normal for a new installation\033[0m\n"
            /etc/init.d/cron restart
        fi

        printf "\033[32;1mStart script\033[0m\n"

        /etc/init.d/getdomains start
    fi
}

install_tun2socks(){
    # Check for tun2socks then download tun2socks binary from GitHub
    # Проверяет наличие tun2socks и скачивает бинарник tun2socks из GitHub
    if [ ! -f "/tmp/tun2socks" ] && [ ! -f "/usr/bin/tun2socks" ]; then
        ARCH=$(grep "OPENWRT_ARCH" /etc/os-release | awk -F '"' '{print $2}')
        wget https://github.com/1andrevich/outline-install-wrt/releases/latest/download/tun2socks-linux-$ARCH -O /tmp/tun2socks
        # Check wget's exit status
        if [ $? -ne 0 ]; then
            echo "Download failed. No file for your Router's architecture"
            exit 1
        fi
    else
        printf "\033[32;1mtun2socks already installed\033[0m\n"
    fi

    # Check for tun2socks then move binary to /usr/bin
    # Проверяет наличие tun2socks и перемещает бинарник в /usr/bin
    if [ ! -f "/usr/bin/tun2socks" ]; then
        mv /tmp/tun2socks /usr/bin/ 
        echo 'moving tun2socks to /usr/bin'
        chmod +x /usr/bin/tun2socks
    fi
}

add_tunnel(){
    # Check for existing config in /etc/config/network then add entry
    # Проверяет наличие конфигурации в /etc/config/network и добавляет запись
    if ! uci get network.$TUNNEL >/dev/null 2>&1; then
        printf "\033[32;1mConfigure interface\033[0m\n"
        uci add network interface
        uci set network.@interface[-1].name="$TUNNEL"
        uci set network.@interface[-1].device='tun1'
        uci set network.@interface[-1].proto='static'
        uci set network.@interface[-1].ipaddr='172.16.10.1'
        uci set network.@interface[-1].netmask='255.255.255.252'
        uci commit network
    else
        printf "\033[32;1mInterface '$TUNNEL' already exists\033[0m\n"
    fi

    # Read user variable for Outline config
    # Считывает пользовательскую переменную для конфигурации Outline (Shadowsocks)
    # read -p "Enter Outline (Shadowsocks) Config (format ss://base64coded@HOST:PORT/?outline=1): " OUTLINECONF
    # Получение ip из ShadowSocks ссылок
    OUTLINEIP=$(echo "$OUTLINECONF" | grep -oE '@([0-9]{1,3}\.){3}[0-9]{1,3}' | cut -d'@' -f2)

    # Check for default gateway and save it into DEFGW
    # Проверяет наличие шлюза по умолчанию и сохраняет его в переменную DEFGW
    DEFGW=$(ip route | grep default | awk '{print $3}')
    echo 'checked default gateway'

    # Check for default interface and save it into DEFIF
    # Проверяет наличие интерфейса по умолчанию и сохраняет его в переменную DEFIF
    DEFIF=$(ip route | grep default | awk '{print $5}')
    echo 'checked default interface'

    # Create script /etc/init.d/tun2socks
    # Создает скрипт /etc/init.d/tun2socks
    rm /etc/init.d/tun2socks
    if [ ! -f "/etc/init.d/tun2socks" ]; then
    cat <<EOL > /etc/init.d/tun2socks
#!/bin/sh /etc/rc.common
USE_PROCD=1

# starts after network starts
START=99
# stops before networking stops
STOP=89

#PROG=/usr/bin/tun2socks
#IF="tun1"
#OUTLINE_CONFIG="$OUTLINECONF"
#LOGLEVEL="warn"
#BUFFER="64kb"

start_service() {
    procd_open_instance
    procd_set_param user root
    procd_set_param command /usr/bin/tun2socks -device tun1 -tcp-rcvbuf 64kb -tcp-sndbuf 64kb  -proxy "$OUTLINECONF" -loglevel "warn"
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn "${respawn_threshold:-3600}" "${respawn_timeout:-5}" "${respawn_retry:-5}"
    procd_close_instance
    ip route add "$OUTLINEIP" via "$DEFGW" #Adds route to OUTLINE Server
	echo 'route to Outline Server added'
    ip route save default > /tmp/defroute.save  #Saves existing default route
    echo "tun2socks is working!"
}

boot() {
    # This gets run at boot-time.
    start
}

shutdown() {
    # This gets run at shutdown/reboot.
    stop
}

stop_service() {
    service_stop /usr/bin/tun2socks
    ip route restore default < /tmp/defroute.save #Restores saved default route
    ip route del "$OUTLINEIP" via "$DEFGW" #Removes route to OUTLINE Server
    echo "tun2socks has stopped!"
}

reload_service() {
    stop
    sleep 3s
    echo "tun2socks restarted!"
    start
}
EOL
DEFAULT_GATEWAY=$OUTLINE_DEFAULT_GATEWAY
# Ask user to use Outline as default gateway
# Задает вопрос пользователю о том, следует ли использовать Outline в качестве шлюза по умолчанию
# while [ "$DEFAULT_GATEWAY" != "y" ] && [ "$DEFAULT_GATEWAY" != "n" ]; do
#     read -p "Use Outline as default gateway? [y/n]: " DEFAULT_GATEWAY
# done

        if [ "$DEFAULT_GATEWAY" = "y" ]; then
		    cat <<EOL >> /etc/init.d/tun2socks
#Replaces default route for Outline
service_started() {
    # This function checks if the default gateway is Outline, if no changes it
     echo 'Replacing default gateway for Outline...'
     sleep 2s
     if ip link show tun1 | grep -q "UP" ; then
         ip route del default #Deletes existing default route
         ip route add default via 172.16.10.2 dev tun1 #Creates default route through the proxy
     fi
}
start() {
    start_service
    service_started
}
EOL

            # Checks rc.local and adds script to rc.local to check default route on startup
            # Проверяет файл rc.local и добавляет скрипт в rc.local для проверки маршрута по умолчанию при запуске
            if ! grep -q "sleep 10" /etc/rc.local; then
            sed '/exit 0/i\
sleep 10\
#Check if default route is through Outline and change if not\
if ! ip route | grep -q '\''^default via 172.16.10.2 dev tun1'\''; then\
    /etc/init.d/tun2socks start\
fi\
' /etc/rc.local > /tmp/rc.local.tmp && mv /tmp/rc.local.tmp /etc/rc.local
		echo "All traffic would be routed through Outline"
            fi
	    else
		    cat <<EOL >> /etc/init.d/tun2socks
start() {
    start_service
}
EOL
		    echo "No changes to default gateway"
        fi

        echo 'script /etc/init.d/tun2socks created'

        chmod +x /etc/init.d/tun2socks
    fi

    # Create symbolic link
    #  Создает символическую ссылку
    if [ ! -f "/etc/rc.d/S99tun2socks" ]; then
    ln -s /etc/init.d/tun2socks /etc/rc.d/S99tun2socks
    echo '/etc/init.d/tun2socks /etc/rc.d/S99tun2socks symlink created'
    fi

    # Start service
    # Запускает сервис
    /etc/init.d/tun2socks start
    printf "\033[32;1mConfigure route for tun2socks\033[0m\n"
}

# Проверка: файл запущен напрямую или импортирован
# if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Прямой запуск - выполняем тесты или демо
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
        cd /root && wget https://raw.githubusercontent.com/arhitru/install_outline/refs/heads/main/install_outline_settings.sh >> $LOG_FILE 2>&1 && chmod +x /root/install_outline_settings.sh
    fi

    . /root/logging_functions.sh
    . /root/install_outline_settings.sh
    install_outline_settings
    #. $CONFIG_FILE

    log_info 'Starting Outline OpenWRT install script'
    #TUNNEL=tun2socks
    dnsmasqfull
    dnsmasqconfdir
    install_pkg
    add_packages
    add_mark
    install_tun2socks
    add_tunnel
    add_zone
    add_set
    add_dns_resolver
    add_getdomains
    log_info 'Restarting Network....'
    # Restart network
#     /etc/init.d/network restart
# else
#     # Импортирован через source - только определяем функции
#     return 0 2>/dev/null || true
# fi