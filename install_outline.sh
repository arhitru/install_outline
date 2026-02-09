cd /tmp
wget https://raw.githubusercontent.com/arhitru/install_outline/main/install_outline_for_getdomains.sh -O install_outline.sh
chmod +x install_outline_for_getdomains.sh
./install_outline_for_getdomains.sh

echo 'Restarting Network....'
# Step 13: Restart network
# Этап 13: Перезагружает сеть
/etc/init.d/network restart