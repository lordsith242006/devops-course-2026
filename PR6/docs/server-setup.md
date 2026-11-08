# Конфигурация виртуальной машины devops-vm

Гипервизор: Oracle VirtualBox 7.2. ОС: Ubuntu Server 26.04.1 LTS (образ `ubuntu-26.04.1-live-server-amd64.iso`).

## 1. Параметры машины

| Параметр | Значение |
|---|---|
| Имя | devops-vm |
| Тип / версия | Linux / Ubuntu (64-bit) |
| Оперативная память | 2048 МБ |
| Ядра процессора | 2 |
| Диск | 25 ГБ, VDI, динамически расширяемый (SATA) |
| Установка | Ubuntu Server (не minimized), Use an entire disk, OpenSSH server, без Featured snaps |

## 2. Сетевые интерфейсы

| Адаптер | Тип | Интерфейс в ВМ | Адрес | Назначение |
|---|---|---|---|---|
| 1 | NAT | enp0s3 | 10.0.2.15/24 (DHCP) | выход в Интернет, apt; SSH через проброс порта |
| 2 | Host-only (`VirtualBox Host-Only Ethernet Adapter`, 192.168.56.0/24) | enp0s8 | 192.168.56.105/24 (DHCP) | прямой доступ с хоста (веб-сервер в ПР №6, `devops.local`) |

Адреса получаются по DHCP (netplan, `dhcp4: true` для `en*`).

Имя узла:

- На ВМ: `sudo hostnamectl set-hostname devops-vm`; в `/etc/hosts`: `127.0.1.1 devops-vm.devops.local devops-vm`;
  `hostname -f` → `devops-vm.devops.local`.
- На хосте в `C:\Windows\System32\drivers\etc\hosts`: `192.168.56.105 devops.local`, затем `ipconfig /flushdns`.

## 3. Правило проброса портов

Адаптер 1 (NAT), правило `ssh`, TCP:

| Хост | Гость |
|---|---|
| 127.0.0.1:2222 | порт 22 → после задания 2 изменён на **2222** |

```bash
VBoxManage modifyvm devops-vm --natpf1 "ssh,tcp,127.0.0.1,2222,,22"     # исходно (ВМ выключена)
VBoxManage controlvm devops-vm natpf1 delete ssh                         # после hardening
VBoxManage controlvm devops-vm natpf1 "ssh,tcp,127.0.0.1,2222,,2222"
```

## 4. Учётные записи

| Имя | UID | Группы | Аутентификация по SSH |
|---|---|---|---|
| student | 1000 | student, adm, cdrom, sudo, dip, plugdev, users, lxd | вход по SSH запрещён (`AllowUsers devops`); только консоль ВМ |
| devops | 1001 | devops, sudo, users | только ключ ed25519 |
| root | 0 | — | вход по SSH запрещён |

```bash
sudo adduser devops
sudo usermod -aG sudo devops
```

Ключ на хосте: `ssh-keygen -t ed25519 -C "devops-vm-key" -f ~/.ssh/devops_vm`, открытый ключ добавлен в
`/home/devops/.ssh/authorized_keys` (права: `~/.ssh` — 700, `authorized_keys` — 600).

`~/.ssh/config` на хосте:

```
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

## 5. Служба SSH

Основной `/etc/ssh/sshd_config` не изменяется (копия: `/etc/ssh/sshd_config.backup`).
Файл `/etc/ssh/sshd_config.d/99-hardening.conf`:

```
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

Важно:
- в `/etc/ssh/sshd_config.d/50-cloud-init.conf` строка `PasswordAuthentication yes` закомментирована
  (файлы читаются по алфавиту, действует первое значение);
- отключена активация по сокету, иначе sshd продолжает слушать 22:

```bash
sudo sed -i 's/^\s*PasswordAuthentication yes/#&/' /etc/ssh/sshd_config.d/50-cloud-init.conf
sudo sshd -t
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
sudo ss -tlnp | grep sshd      # 0.0.0.0:2222
```

После перезапуска сразу изменить проброс порта (п. 3), проверять новым соединением, не закрывая старое.

## 6. Правила межсетевого экрана

Политики: `deny (incoming)`, `allow (outgoing)`, `disabled (routed)`. Журналирование: `medium`.

| Порт | Действие | Комментарий |
|---|---|---|
| 80/tcp | ALLOW IN | HTTP |
| 443/tcp | ALLOW IN | HTTPS |
| 2222/tcp | LIMIT IN | SSH rate-limited |

(правила продублированы для IPv6)

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH rate-limited'   # ДО включения!
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable
sudo ufw logging medium
```

## 7. Снимки состояния

| Снимок | Момент создания |
|---|---|
| 01-clean-install | после установки ОС и `apt upgrade`, ВМ выключена |
| 02-keys-configured | после создания devops и настройки входа по ключу |
| 03-ssh-hardened | после hardening SSH (до настройки UFW) |
| 04-nginx-https | после установки Nginx и перевода devops.local на HTTPS (ПР № 6) |

## 8. Веб-сервер

Пакет: `nginx` из репозитория Ubuntu (`sudo apt install -y nginx`), версия 1.28.3.
Главный процесс работает от root, рабочие процессы — от `www-data`.

| Объект | Путь | Владелец | Права |
|---|---|---|---|
| Конфигурация ресурса | `/etc/nginx/sites-available/devops-site` | root:root | 644 |
| Ссылка активации | `/etc/nginx/sites-enabled/devops-site` → `../sites-available/devops-site` | root:root | — |
| Стандартный ресурс | ссылка `/etc/nginx/sites-enabled/default` удалена (файл в sites-available сохранён) | — | — |
| Каталог ресурса | `/var/www/devops-site` | devops:devops | каталоги 755, файлы 644 |
| Сертификат | `/etc/ssl/certs/devops.crt` | root:root | 644 |
| Закрытый ключ | `/etc/ssl/private/devops.key` | root:root | 600 |
| Журналы | `/var/log/nginx/devops-site.access.log`, `devops-site.error.log` | — | — |

Каталог ресурса:

```bash
sudo mkdir -p /var/www/devops-site
sudo chown -R devops:devops /var/www/devops-site
```

Сертификат (самоподписанный, RSA 2048, срок действия 365 дней, поле SAN `DNS:devops.local`):

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/devops.key \
    -out /etc/ssl/certs/devops.crt \
    -subj "/CN=devops.local" \
    -addext "subjectAltName=DNS:devops.local"
```

Выпущен 08.11.2026, действует до 08.11.2027. Копия сертификата на хосте: `~/devops.crt`
(`scp devops:/etc/ssl/certs/devops.crt ~/devops.crt`).

`/etc/nginx/sites-available/devops-site`:

```nginx
# Блок 1: перенаправление HTTP -> HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name devops.local;

    return 301 https://$host$request_uri;
}

# Блок 2: ресурс по HTTPS
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name devops.local;

    ssl_certificate     /etc/ssl/certs/devops.crt;
    ssl_certificate_key /etc/ssl/private/devops.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    root /var/www/devops-site;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    error_page 404 /404.html;

    access_log /var/log/nginx/devops-site.access.log;
    error_log  /var/log/nginx/devops-site.error.log;
}
```

Активация и применение:

```bash
sudo ln -s /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

HSTS не включается (самоподписанный сертификат). Порты 80/443 уже открыты правилами ufw из раздела 6,
профили `Nginx Full` не добавляются.

Содержимое доставляется из каталога `PR6/site/` репозитория сценарием `PR6/scripts/deploy.sh`
(rsync `--delete --chmod=D755,F644`, одно SSH-соединение, проверка `https://devops.local` с `--cacert`).
