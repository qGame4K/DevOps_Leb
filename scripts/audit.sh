#!/usr/bin/env bash
set -uo pipefail
PASS=0; FAIL=0
check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK]   $desc"; ((PASS++))
    else
        echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"; ((FAIL++))
    fi
}
echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход от имени root запрещён"        "no"  "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no"  "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"
# TODO 1: порт службы отличен от 22
SSH_PORT="$(sudo sshd -T | awk '/^port/{print $2}')"
if [[ -n "$SSH_PORT" && "$SSH_PORT" != "22" ]]; then
    echo "  [OK]   Служба SSH использует нестандартный порт ($SSH_PORT)"; ((PASS++))
else
    echo "  [FAIL] Служба SSH использует стандартный порт 22 (получено: '$SSH_PORT')"; ((FAIL++))
fi
# TODO 2: maxauthtries равно 3
check "Ограничение попыток аутентификации" "3" "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"
# TODO 3: политика по умолчанию для входящего трафика
check "Политика по умолчанию для входящего трафика" "deny" \
      "$(sudo ufw status verbose | awk -F'[ (]' '/^Default:/{print $2}')"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер"
check "Служба nginx активна" "active" "$(systemctl is-active nginx)"
if sudo nginx -t >/dev/null 2>&1; then
    echo "  [OK]   Конфигурация nginx синтаксически корректна"; ((PASS++))
else
    echo "  [FAIL] Конфигурация nginx содержит ошибку"; ((FAIL++))
fi
CERT_DAYS="${CERT_DAYS:-30}"
if sudo openssl x509 -checkend $((CERT_DAYS*86400)) -noout -in /etc/ssl/certs/devops.crt >/dev/null 2>&1; then
    echo "  [OK]   Сертификат действителен ещё не менее $CERT_DAYS дней"; ((PASS++))
else
    echo "  [FAIL] Сертификат истекает ранее чем через $CERT_DAYS дней"; ((FAIL++))
fi
WORLD_WRITABLE="$(find /var/www/devops-site -perm -o+w 2>/dev/null | wc -l | tr -d ' ')"
check "Файлов, доступных для записи всем, нет" "0" "$WORLD_WRITABLE"
check "Права закрытого ключа TLS" "600" "$(sudo stat -c '%a' /etc/ssl/private/devops.key)"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
