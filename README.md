# Контейнер на pi zero 1

## Инструкция по использованию

TODO: надо нормально оформить и проверить

```sh
# сначала обновляем систему и ставим зависимости

# TODO: важные скрипте
./TODO-update-install-host-soft.sh

# -----------------------------------

# Скрипт, который проверяет зависимости, устанавливает их и проверяет установку systemd-nspawn

# Минимальная установка
./install-systemd-nspawn.sh --minimal

# Полная установка с тестированием
./install-systemd-nspawn.sh --full

# Показать справку
./install-systemd-nspawn.sh --help

# -----------------------------------

# Далее производим миграцию на systemd-networkd
./network-migration.sh

# TODO: после успешной миграции, настраиваем veth и маршрутизацию
./setup-TODO.sh
```

```sh
# Делаем скрипты исполняемыми
chmod +x create-debian-container.sh
chmod +x install-nginx-in-container.sh
chmod +x manage-container.sh
chmod +x configure-container.sh

# Создаем контейнер
sudo ./create-debian-container.sh

# Устанавливаем nginx
sudo ./install-nginx-in-container.sh

# Дополнительная настройка (опционально)
sudo ./configure-container.sh

# Копируем конфигурацию systemd службы
sudo cp app-webui-container.service /etc/systemd/system/

# Перезагружаем systemd
sudo systemctl daemon-reload

# Включаем автозапуск
sudo systemctl enable app-webui-container.service

# Запускаем контейнер
sudo systemctl start app-webui-container.service

# Проверяем статус
sudo systemctl status app-webui-container.service

# Входим в контейнер
sudo ./manage-container.sh login

# Выходим из контейнера, зажав Ctrl и нажав ]]] (три раза ]).
# -----------------------------------------------------------
```

## Базовое управление контейнером

После того как rootfs готова, можно начинать работу.

### Запуск контейнера

Простой запуск с доступом к терминалу:

```bash
# -b: загрузить контейнер (запустить init процесс)
# -D: путь к корневой файловой системе
sudo systemd-nspawn -b -D /var/lib/machines/my-debian-container
```

При первом запуске вас поприветствует стандартный login:.

Логин — root, пароля по умолчанию нет.

Установка пароля root (сделать до первого запуска):

```bash
# Сначала войдем в контейнер без загрузки (только chroot)
sudo systemd-nspawn -D /var/lib/machines/my-debian-container

# внутри контейнера
passwd

# задайте пароль, затем выйдите командой 'exit'
```

Запуск с пробросом сети:
_По умолчанию у контейнера есть только loopback-интерфейс (lo)_. Чтобы дать доступ наружу, используйте --network-veth. Это создаст виртуальную Ethernet-пару между хостом и контейнером.

> [!WARNING]
> Читай HOST-CONTAINER-NETWORKING.md для более детальной настройки
> Для примера есть скрипт setup-existing-container-network.sh

```bash
sudo systemd-nspawn -b -D /var/lib/machines/app-webui-debian-container --network-veth

```

На хосте автоматически поднимется интерфейс ve-контейнер@host0, а в контейнере — host0.

### Остановка контейнера

Изнутри контейнера можно просто выполнить terminate, poweroff, stop.

Снаружи — послать сигнал остановки демону systemd внутри контейнера (это более чистый способ, чем убивать процесс):

```bash
sudo machinectl poweroff my-debian-container
```

### Продвинутая настройка: Управление через machinectl и службы

Настоящая сила systemd-nspawn раскрывается при интеграции с systemd.

"Регистрация" контейнера:
Если ваша rootfs лежит в `/var/lib/machines/` и имеет понятное имя (например, my-debian-container), machinectl _автоматически_ её увидит.

```bash
machinectl list # отобразить все запущенные машины
```

# Выведет список всех обнаруженных образов и запущенных контейнеров

Запуск и остановка:

```bash
sudo machinectl start my-debian-container
sudo machinectl stop my-debian-container
sudo machinectl reboot my-debian-container
```

Логин в запущенный контейнер (аналог docker exec -it):

```bash
sudo machinectl login my-debian-container
```

**Запуск контейнера как службы** (самое полезное для деплоя!)

Вы можете настроить контейнер так, чтобы он запускался автоматически при загрузке хоста, как обычная служба.

Создайте файл сервиса: `/etc/systemd/system/my-container.service`

Добавьте в него содержимое:

```ini
[Unit]
Description=My Awesome Container

[Service]
ExecStart=/usr/bin/systemd-nspawn --quiet --keep-unit --boot --link-journal=try-guest --directory=/var/lib/machines/my-debian-container

# --network-veth можно добавить и здесь

ExecStop=/usr/bin/machinectl poweroff my-debian-container
KillMode=none
Type=notify

[Install]
WantedBy=multi-user.target
```

Включите и запустите службу:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now my-container.service
```

Теперь ваше приложение внутри контейнера будет работать как полноценная служба.

```bash
# Выполнить команду в контейнере

sudo machinectl shell app-webui-eclock-alpine-container /bin/sh

# Или с помощью systemd-nspawn

sudo systemd-nspawn -D /var/lib/machines/app-webui-eclock-alpine-container /bin/sh
```

### Проверка работы ротации

```bash

# Проверить текущее использование логов

journalctl --disk-usage

# Просмотреть информацию о файлах журнала

journalctl --file=/var/log/journal/*/system.journal --list-boots

# Принудительная ротация

journalctl --rotate

# Очистка старых логов

journalctl --vacuum-size=50M
journalctl --vacuum-time=2weeks
```
