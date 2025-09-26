Настройка DNS-имен для контейнеров — это ключ к удобству.

Avahi (mDNS) — Самый простой для локальной сети (Zeroconf)
Это метод "нулевой конфигурации". Контейнеры автоматически объявят о себе в сети, и к ним можно будет обращаться по имени .local.
Это минималистичный и элегантный подход. Можно полностью отказаться от настройки DHCP-сервера, если использовать только Avahi. В этом случае контейнеры будут получать IP-адреса по **link-local адресации (APIPA)**, а Avahi будет отвечать за преобразование имен.

Установите Avahi внутри КАЖДОГО контейнера:

bash

# Войдите в контейнер

sudo machinectl login my-container-1

# Для контейнеров на Debian/Ubuntu

apt update && apt install -y avahi-daemon avahi-utils

# Для контейнеров на Alpine

# apk add avahi avahi-tools

# Выйдите из контейнера

exit
Задайте уникальное имя хоста для каждого контейнера:

Это самое важное. Имя хоста внутри контейнера и будет его DNS-именем.

bash

# Войдите в контейнер

sudo machinectl login my-container-1

# Установите hostname (например, 'app-server')

hostnamectl set-hostname app-server

# Или отредактируйте файл

echo "app-server" > /etc/hostname

# Перезагрузите контейнер или сервис avahi

systemctl restart avahi-daemon
exit
Повторите для других контейнеров, задав уникальные имена: db-server, web-server и т.д.

Проверьте работу:
Теперь с хоста (Raspberry Pi) и с любого другого устройства в вашей локальной сети вы можете пинговать контейнеры по имени:

bash
ping app-server.local
ping db-server.local
Преимущество: Работает across всей локальной сети без дополнительной настройки на клиентах (работает на macOS, Windows, Linux).

Как это работает (схема)
Адресация: Каждый контейнер самостоятельно назначает себе случайный IP-адрес из диапазона 169.254.0.0/16 (это стандартный механизм IPv4 Link-Local Addressing).

Имена: Avahi (mDNS) работает поверх этого, сопоставляя заданное имя хоста (например, app-server) с этим случайным IP-адресом и объявляя его в сеть как app-server.local.

Роль хоста: Хост (Raspberry Pi) просто предоставляет сетевой мост br0. Ему не нужен статический IP в этой подсети и не нужно запускать DHCP-сервер.

Преимущества:

Максимально простая настройка на хосте.

Не нужно следить за пулами IP-адресов и арендами.

Zero-configuration — работает "из коробки".

Недостатки:

IP-адреса контейнеров будут меняться при каждой перезагрузке.

Только имена .local. Невозможно задать кастомные DNS-имена (например, db.example).

Нет централизованного управления адресацией.

Пошаговая инструкция: Только Avahi
Шаг 1: Настройка моста br0 на хосте (БЕЗ IP-адреса и DHCP)
Нам нужно создать "немой" мост, который просто соединит интерфейсы, но не будет участвовать в сети сам.

Отредактируйте /etc/dhcpcd.conf:

bash
sudo nano /etc/dhcpcd.conf
Добавьте следующие строки. Ключевой момент — мы не назначаем мосту br0 IP-адрес.

bash

# Запрещаем dhcpcd управлять физическими интерфейсами, чтобы они стали частью моста

denyinterfaces eth0 wlan0

# Разрешаем управлять мостом, но НЕ задаем ему static ip_address

interface br0

# Вот и всё! Никакого 'static ip_address=...'

Сохраните файл и перезапустите dhcpcd:

bash
sudo systemctl restart dhcpcd
Убедитесь, что мост создан, но у него нет IPv4-адреса:

bash
ip addr show br0
Вывод должен быть примерно таким:

bash
4: br0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether aa:bb:cc:dd:ee:ff brd ff:ff:ff:ff:ff:ff
    inet6 fe80::aabb:ccff:fedd:eeff/64 scope link # Это только link-local IPv6, это нормально
       valid_lft forever preferred_lft forever
Шаг 2: Настройка контейнеров на получение Link-Local адреса
Теперь нужно настроить сеть внутри контейнеров на самоназначение адреса.

Для каждого контейнера создайте конфигурационный файл .nspawn, чтобы привязать его к мосту br0:

bash
sudo nano /etc/systemd/nspawn/my-container-1.nspawn
Добавьте конфигурацию:

ini
[Exec]
Boot=yes

[Network]
Zone=br0

# Ключевая настройка: говорим systemd получить Link-Local адрес

LinkLocal=yes
Сохраните и закройте файл.

Войдите в контейнер и настройте systemd-networkd:

bash
sudo machinectl login my-container-1
Создайте или отредактируйте конфигурационный файл сети:

bash
sudo nano /etc/systemd/network/80-link-local.network
Добавьте следующее содержимое. Это заставляет интерфейс использовать только link-local адресацию.

ini
[Match]
Name=host0 # Или другое имя виртуального интерфейса

[Network]

# Включаем Link-Local адресацию (IPv4LL)

LinkLocalAddressing=ipv4

# Отключаем DHCP (он нам не нужен и будет мешать)

DHCP=no

# Можно также отключить IPv6, если не используется

IPv6AcceptRA=no
Сохраните файл.

Перезагрузите контейнер:

bash
exit
sudo machinectl reboot my-container-1
Проверьте, что контейнер получил Link-Local адрес:

bash
sudo machinectl login my-container-1
ip addr show
Вы должны увидеть, что у интерфейса (например, host0) есть IPv4-адрес из диапазона 169.254.X.X:

bash
2: host0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc...
    link/ether...
    inet 169.254.123.45/16 brd 169.254.255.255 scope link host0
       valid_lft forever preferred_lft forever
Шаг 3: Установка и настройка Avahi внутри контейнеров (Ключевой шаг!)
Поскольку IP-адреса теперь случайны, роль Avahi становится критически важной.

Установите Avahi в контейнере:

bash
sudo apt update && sudo apt install -y avahi-daemon avahi-utils
Настройте уникальное имя хоста (Это ОЧЕНЬ важно!):

bash
sudo hostnamectl set-hostname app-server
echo "app-server" | sudo tee /etc/hostname

# Также добавьте запись в /etc/hosts для избежания предупреждений

echo "127.0.1.1 app-server" | sudo tee -a /etc/hosts
Запустите Avahi:

bash
sudo systemctl enable avahi-daemon
sudo systemctl start avahi-daemon
exit
Повторите эти шаги для всех контейнеров, давая им уникальные имена (db-server, web-server).

Шаг 4: Проверка работы
С хоста (Raspberry Pi) проверьте, что вы можете пинговать контейнеры по .local-именам:

bash

# Avahi должен разрешить имя, несмотря на случайный IP

ping app-server.local

# Можно узнать, какой IP адрес был назначен

avahi-resolve -n app-server.local

# Пример вывода: app-server.local 169.254.87.132

Из одного контейнера в другой тоже можно обращаться по имени:

bash
sudo machinectl login app-server
ping db-server.local
С любого другого устройства в вашей локальной сети (ноутбука, телефона) имена контейнеров также будут доступны:

bash
ping app-server.local
Важные замечания
Первое подключение: При первом пинге .local-имени может быть небольшая задержка (1-2 секунды), пока работает mDNS-разрешение.

Стабильность IP: Не используйте IP-адреса напрямую для настройки приложений. Они меняются. Всегда используйте .local-имена.

Доступ в интернет: Если контейнерам нужен выход в интернет, вам все равно потребуется настроить на хосте IP Forwarding и NAT, как описывалось в предыдущих инструкциях. Avahi решает только проблему имен, но не маршрутизации.

Этот подход — идеальный пример философии Zero-Configuration Networking (Zeroconf) и отлично подходит для быстрого развертывания и экспериментов на Raspberry Pi.
