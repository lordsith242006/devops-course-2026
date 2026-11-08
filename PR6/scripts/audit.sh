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
SSHD_T="$(sudo sshd -T)"
check "Вход от имени root запрещён"        "no" "$(awk '/^permitrootlogin/{print $2}' <<<"$SSHD_T")"
check "Парольная аутентификация отключена" "no" "$(awk '/^passwordauthentication/{print $2}' <<<"$SSHD_T")"

# TODO 1: значение параметра port отлично от 22
PORT="$(awk '/^port /{print $2}' <<<"$SSHD_T" | head -n1)"
check "Порт SSH отличен от 22 (port=$PORT)" "yes" "$([[ -n "$PORT" && "$PORT" != "22" ]] && echo yes || echo no)"

# TODO 2: значение параметра maxauthtries равно 3
check "MaxAuthTries равно 3" "3" "$(awk '/^maxauthtries/{print $2}' <<<"$SSHD_T")"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"

# TODO 3: политика по умолчанию для входящего трафика равна deny
check "Политика входящего трафика по умолчанию: deny" "deny" \
    "$(sudo ufw status verbose | awk '/^Default:/{print $2}')"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "  %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер"
CERT=/etc/ssl/certs/devops.crt
KEY=/etc/ssl/private/devops.key
SITE_DIR=/var/www/devops-site
CERT_MIN_DAYS="${CERT_MIN_DAYS:-30}"
check "Служба nginx активна" "active" "$(systemctl is-active nginx)"
check "Конфигурация nginx корректна" "0" "$(sudo nginx -t >/dev/null 2>&1; echo $?)"
check "Сертификат действителен ещё ${CERT_MIN_DAYS} дн." "0" \
    "$(openssl x509 -in "$CERT" -noout -checkend $((CERT_MIN_DAYS * 86400)) >/dev/null; echo $?)"
check "Нет файлов ресурса, доступных для записи всем" "" "$(find "$SITE_DIR" -perm -o+w)"
check "Права ключа TLS равны 600" "600" "$(sudo stat -c '%a' "$KEY")"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
