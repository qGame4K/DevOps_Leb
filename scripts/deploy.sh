#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"                     # псевдоним из ~/.ssh/config (ПР № 5, шаг 1.6)
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
LOCAL_DIR="$(git rev-parse --show-toplevel)/site/"

# 1. Разбор аргумента --dry-run
DRY_RUN=0
if [[ $# -gt 0 ]]; then
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        *) echo "Неизвестный аргумент: $1. Использование: $0 [--dry-run]" >&2; exit 1 ;;
    esac
fi

# 2. Проверки по требованиям 4 и 5
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "ОШИБКА: файл site/index.html отсутствует, доставка не выполняется." >&2
    exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "ОШИБКА: в репозитории есть незафиксированные изменения:" >&2
    git status --short >&2
    exit 1
fi

# 3. Синхронизация каталога
RSYNC_OPTS=(-avz --delete --chmod=D755,F644
            -e "ssh -o BatchMode=yes -o ConnectTimeout=5")
if [[ $DRY_RUN -eq 1 ]]; then
    RSYNC_OPTS+=(--dry-run)
fi
rsync "${RSYNC_OPTS[@]}" "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/"

# 4. При --dry-run завершение без проверки доступности
if [[ $DRY_RUN -eq 1 ]]; then
    echo "Пробный запуск завершён, состояние сервера не изменялось."
    exit 0
fi

# 5. Проверка доступности ресурса с проверкой сертификата
if ! curl -fsS --cacert "$CA_CERT" \
        --connect-to "devops.local:443:127.0.0.1:8443" \
        -o /dev/null "$SITE_URL"; then
    echo "ОШИБКА: ресурс ${SITE_URL} недоступен после доставки." >&2
    exit 1
fi

echo "Доставлен коммит $(git rev-parse --short HEAD)"
exit 0
