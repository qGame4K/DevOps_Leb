# Конфигурация виртуальной машины devops-vm

Документ описывает конфигурацию учебного сервера в объёме, достаточном для её
полного восстановления из снимка состояния `01-clean-install`.

## 1. Параметры машины

| Параметр | Значение |
|---|---|
| Средство виртуализации | Lima 2.0 (Apple Virtualization framework, тип 2) |
| Гостевая система | Ubuntu Server 24.04.5 LTS (aarch64) |
| Оперативная память | 2048 МБ |
| Ядра процессора | 2 |
| Дисковый накопитель | 25 ГБ, динамически расширяемый |
| Имя узла | devops-vm (FQDN devops-vm.devops.local) |

Примечание. Методические указания предусматривают VirtualBox. На хостовой системе
Apple Silicon VirtualBox неработоспособен, поэтому применён гипервизор того же
типа с эквивалентной моделью сети: пользовательский NAT и адрес, доступный с
хостовой системы.

## 2. Сетевые интерфейсы

| Интерфейс | Тип | Адрес | Назначение |
|---|---|---|---|
| eth0 | NAT (пользовательская сеть гипервизора) | 192.168.5.15/24 | доступ к репозиториям пакетов |
| lima0 | сеть хоста (аналог Host-only) | 192.168.64.4/24 | обращение к серверу с хостовой системы |

Шлюз сегмента NAT — 192.168.5.2, шлюз сегмента хоста — 192.168.64.1.

## 3. Правило проброса портов

| Порт хостовой системы | Порт гостевой системы | Назначение |
|---|---|---|
| 127.0.0.1:2222 | 2222 | SSH |
| 127.0.0.1:8080 | 80 | HTTP |
| 127.0.0.1:8443 | 443 | HTTPS |

Порты 80 и 443 на хостовой системе требуют привилегий root, поэтому сопоставлены
непривилегированным портам 8080 и 8443.

## 4. Учётные записи

| Имя | Группы | Способ аутентификации |
|---|---|---|
| student | student, sudo, users | пароль (создана при установке системы) |
| devops | devops, sudo, users | открытый ключ ed25519 (~/.ssh/devops_vm) |

Ключ доступа отделён от ключа системы контроля версий. Права: `~/.ssh` — 700,
`~/.ssh/authorized_keys` — 600.

На хостовой системе в `~/.ssh/config` описан псевдоним:

```
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

## 5. Служба SSH

Конфигурация размещена в дополняющем файле `/etc/ssh/sshd_config.d/99-hardening.conf`;
основной файл `/etc/ssh/sshd_config` не изменялся, его копия сохранена как
`/etc/ssh/sshd_config.backup`.

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

Особенности восстановления:

1. В файле `/etc/ssh/sshd_config.d/60-cloudimg-settings.conf` директива
   `PasswordAuthentication yes` подлежит комментированию: файлы обрабатываются в
   лексикографическом порядке и действует первое встреченное значение.
2. Активация по сокету отключается, иначе порт остаётся равным 22:
   `sudo systemctl disable --now ssh.socket && sudo systemctl enable --now ssh.service`.
3. Контроль: `sudo sshd -t`, затем `sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers)'`.
4. Отдельный экземпляр службы на порту 22 (`/etc/ssh/sshd_config_lima`,
   юнит `sshd-lima.service`, `AllowUsers ivanlebedev`) обслуживает служебный канал
   управления гипервизора и заменяет окно консоли виртуальной машины.

## 6. Правила межсетевого экрана

Политики по умолчанию: `deny incoming`, `allow outgoing`. Регистрация событий: `medium`.

| Порт | Действие | Источник | Комментарий |
|---|---|---|---|
| 2222/tcp | LIMIT | любой | SSH с ограничением частоты подключений |
| 80/tcp | ALLOW | любой | HTTP |
| 443/tcp | ALLOW | любой | HTTPS |
| 22/tcp | ALLOW | 192.168.5.0/24 | служебный канал управления гипервизора |

Порядок восстановления: сначала разрешающее правило для управляющего порта, затем
`sudo ufw enable`. Обратный порядок приводит к потере доступа к серверу.

## 7. Снимки состояния

| Наименование | Момент создания |
|---|---|
| 01-clean-install | после установки системы и обновления пакетов |
| 02-keys-configured | после создания учётной записи devops и настройки доступа по ключу |
| 03-ssh-hardened | после усиления защиты службы SSH |
| 04-nginx-https | после публикации ресурса по HTTPS (практическая работа № 6) |

## 8. Веб-сервер

| Параметр | Значение |
|---|---|
| Пакет | nginx (репозиторий дистрибутива), версия 1.24.0 |
| Конфигурация ресурса | `/etc/nginx/sites-available/devops-site`, символическая ссылка в `sites-enabled/` |
| Стандартный ресурс | отключён удалением ссылки `/etc/nginx/sites-enabled/default` |
| Каталог ресурса | `/var/www/devops-site`, владелец `devops:devops`, права 755 |
| Файлы ресурса | права 644, владелец `devops:devops` |
| Сертификат | `/etc/ssl/certs/devops.crt`, права 644, владелец root |
| Закрытый ключ | `/etc/ssl/private/devops.key`, права 600, владелец root |
| Срок действия сертификата | 365 дней с момента выпуска |
| Журналы | `/var/log/nginx/devops-site.access.log`, `devops-site.error.log` |

Команда формирования сертификата:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"
```

Конфигурация ресурса состоит из двух блоков `server`: первый принимает запросы на
порту 80 и возвращает `301` с перенаправлением на HTTPS, второй обслуживает ресурс
на порту 443 с протоколами TLSv1.2 и TLSv1.3. Применение изменений выполняется
последовательностью `sudo nginx -t && sudo systemctl reload nginx`.

Доставка содержимого выполняется с хостовой системы сценарием `scripts/deploy.sh`,
использующим `rsync -avz --delete --chmod=D755,F644`.
