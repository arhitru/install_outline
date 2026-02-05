**Настраиваем клиент Outline на OpenWRT за 5 минут с помощью tun2socks**

Собственно сразу к делу, понадобится любая версия OpenWRT (проверялось на 19.07, 21.02, 22.03 и 23.05-rc1) и установленные пакеты kmod-tun и ip-full, а так же настроенный сервер Outline (shadowsocks).

Рекомендую роутер не меньше чем с 128 Мб ОЗУ, будут показаны варианты установки в ПЗУ и ОЗУ.

Использоваться будет пакет xjasonlyu/tun2socks. https://github.com/xjasonlyu/tun2socks

Установка
Скачаем скрипт в ОЗУ и дадим права на запуск:
```bash
cd /tmp
wget https://github.com/arhitru/install_outline/blob/main/install_outline.sh -O install_outline.sh
chmod +x install_outline.sh
```

Далее запускаем скрипт: (вам понадобится около 9 Мб свободной памяти роутера)
```bash
./install_outline.sh
```

Скрипт запросит:
- IP адрес вашего Сервера Outline (shadowsocks)
- Outline (Shadowsocks) конфиг в формате "ss://base64coded@IP:ПОРТ" (копируем и вставляем из Outline Manager)
- Хотите ли вы использовать Outline (shadowsocks) как шлюз по умолчанию (y/n)

Что делает скрипт:
- Проверит наличие пакетов kmod-tun, ip-full
- Cкачает tun2socks для вашего роутера (если пакет есть в репозитории)
- Перенесёт файл в ПЗУ
- Создаст необходимые записи в /etc/config/network и /etc/config/firewall
- Попросит ввести данные для настройки
- Проверит и сохранит текущий маршрут по умолчанию
- Создаст скрипт запуска /etc/init.d/tun2socks и добавит его в автозапуск
- Перезагрузит сеть
- Запустит туннель