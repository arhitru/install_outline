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