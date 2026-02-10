#!/bin/sh
# Outline scripted, xjasonlyu/tun2socks based installer for OpenWRT.
# https://github.com/1andrevich/outline-install-wrt
echo 'Starting Outline OpenWRT install script'
#TUNNEL=tun2socks

remove_forwarding() {
    if [ ! -z "$forward_id" ]; then
        while uci -q delete firewall.@forwarding[$forward_id]; do :; done
    fi
}

# Check for existing config /etc/config/firewall then add entry
# Проверяет наличие конфигурации в /etc/config/firewall и добавляет запись
add_zone() {
    if  uci show firewall | grep -q "@zone.*name='$TUNNEL'"; then
        printf "\033[32;1mZone already exist\033[0m\n"
    else
        printf "\033[32;1mCreate zone\033[0m\n"

        # Delete exists zone
        zone_tun_id=$(uci show firewall | grep -E '@zone.*tun0' | awk -F '[][{}]' '{print $2}' | head -n 1)
        if [ "$zone_tun_id" == 0 ] || [ "$zone_tun_id" == 1 ]; then
            printf "\033[32;1mtun0 zone has an identifier of 0 or 1. That's not ok. Fix your firewall. lan and wan zones should have identifiers 0 and 1. \033[0m\n"
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
        printf "\033[32;1mForwarding already configured\033[0m\n"
    else
        printf "\033[32;1mConfigured forwarding\033[0m\n"
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

# Check for kmod-tun 
# Проверяет наличие kmod-tun
if opkg list-installed | grep -q kmod-tun; then
    printf "\033[32;1mkmod-tun already installed\033[0m\n"
else
    echo "Installed kmod-tun"
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

# Check for existing config /etc/config/firewall then add entry
# Проверяет наличие конфигурации в /etc/config/firewall и добавляет запись
add_zone

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
