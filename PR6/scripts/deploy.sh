#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: PR6/scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"                          # псевдоним из ~/.ssh/config (ПР № 5, шаг 1.6)
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_ROOT}/PR6/site/"

die() { echo "deploy: $*" >&2; exit 1; }

# 1. Разбор аргумента --dry-run
DRY_RUN=""
case "${1:-}" in
    "")        ;;
    --dry-run) DRY_RUN="--dry-run" ;;
    *)         die "неизвестный аргумент '$1'. Использование: $0 [--dry-run]" ;;
esac

# 2. Проверки: главная страница на месте, рабочая копия чистая
[[ -f "${LOCAL_DIR}index.html" ]] || die "нет файла ${LOCAL_DIR}index.html, доставка отменена"
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
    git -C "$REPO_ROOT" status --short >&2
    die "есть незафиксированные изменения, доставка отменена"
fi
COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"

# 3. Синхронизация: точная копия site/, права 755/644, одно SSH-соединение без запроса пароля
rsync -avz --delete --chmod=D755,F644 ${DRY_RUN} \
    -e "ssh -o BatchMode=yes -o ConnectTimeout=5" \
    "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/" || die "rsync завершился с ошибкой"

# 4. При --dry-run сервер не меняется, проверка доступности не нужна
if [[ -n "$DRY_RUN" ]]; then
    echo "dry-run: план выведен, сервер не изменён (коммит ${COMMIT})"
    exit 0
fi

# 5. Проверка доступности с проверкой сертификата
curl -fsS --max-time 10 --cacert "$CA_CERT" -o /dev/null "${SITE_URL}/" \
    || die "ресурс ${SITE_URL} недоступен после доставки (коммит ${COMMIT})"
echo "Деплой выполнен: коммит ${COMMIT}"
