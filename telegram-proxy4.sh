#!/bin/bash
set -e
# 2026-04-02

ok() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1" >&2; exit 1; }

echo
echo "Updating system..."
echo

export DEBIAN_FRONTEND=noninteractive
apt-get update        && ok "apt-get update"
apt-get dist-upgrade -y && ok "dist-upgrade"
apt-get install -y curl openssl xxd && ok "Установка зависимостей (curl, openssl, xxd)"
apt-get autoremove --purge -y
apt-get clean
clear

echo
echo "Installing Telegram proxy..."
echo

# Параметры
PORT=8443               # Порт для прокси-сервера
DOMAIN="vk.com"         # Домен для маскировки TLS
VERSION="3.3.36"        # Версия telemt (если не указана — ставим последний релиз)
MAX_CONNECTIONS=2000    # Максимальное количество одновременных TCP подключений (0 = без лимита)
BUF_DIVISOR=4           # Делитель буферов — уменьшает буферы если не хватает RAM (1-16, по умолчанию 1)

echo "Переменные"
echo "$DOMAIN --- $PORT --- $VERSION --- $MAX_CONNECTIONS --- $BUF_DIVISOR"
echo

# Максимум TCP подключений для 1 GB RAM:
# MAX_CONNECTIONS=1000 при BUF_DIVISOR=1
# MAX_CONNECTIONS=2000 при BUF_DIVISOR=4
# MAX_CONNECTIONS=4000 при BUF_DIVISOR=16

BINARY_PATH="/usr/local/bin/telemt"
CONFIG_DIR="/etc/telemt"
CONFIG_FILE="$CONFIG_DIR/config.toml"
IP="$(ip route get 1.2.3.4 2>/dev/null | grep -oP 'src \K\S+')"
ARCH="$(uname -m)"
LIBC="gnu"

if [[ -n "${VERSION}" ]]; then
	TELEMT_URL="https://github.com/telemt/telemt/releases/download/${VERSION}/telemt-${ARCH}-linux-${LIBC}.tar.gz"
else
	TELEMT_URL="https://github.com/telemt/telemt/releases/latest/download/telemt-${ARCH}-linux-${LIBC}.tar.gz"
fi

# Читаем старые значения из конфига (если он существует)
if [[ -f "$CONFIG_FILE" ]]; then
	OLD_SECRET="$(sed -n 's/^[[:space:]]*user[[:space:]]*=[[:space:]]*"\([0-9a-fA-F]\{32\}\)".*/\1/p' "$CONFIG_FILE" | head -n 1)"
	OLD_PORT="$(awk -F'=' '/^\[server\]/{in_server=1; next} /^\[/{in_server=0} in_server && $1 ~ /^[[:space:]]*port[[:space:]]*$/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' "$CONFIG_FILE")"
	OLD_DOMAIN="$(sed -n 's/^[[:space:]]*tls_domain[[:space:]]*=[[:space:]]*"\([^"]\+\)".*/\1/p' "$CONFIG_FILE" | head -n 1)"
	ok "Прочитан существующий конфиг"
fi

SECRET="${OLD_SECRET:-$(openssl rand -hex 16)}"
PORT="${OLD_PORT:-$PORT}"
DOMAIN="${OLD_DOMAIN:-$DOMAIN}"
DOMAIN_HEX=$(echo -n "$DOMAIN" | xxd -p)
BUF_C2S=$((65536 / BUF_DIVISOR))
BUF_S2C=$((262144 / BUF_DIVISOR))
BUF_CRYPTO=$((262144 / BUF_DIVISOR))

# Вспомогательная функция для безопасного применения настройки:
# Сначала пробуем заменить существующий ключ, если не нашли — вставляем после заголовка секции.
set_config() {
	local key="$1"
	local value="$2"
	local section="$3"   # например: \[general\]

	if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$CONFIG_FILE"; then
		sed -i "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "$CONFIG_FILE"
	else
		sed -i "/^${section}/a ${key} = ${value}" "$CONFIG_FILE"
	fi
}

# ── Остановка сервиса ──────────────────────────────────────────────────────────
echo "Остановка сервиса"
systemctl disable --now telemt 2>/dev/null || true
ok "Сервис остановлен (или не был запущен)"

# ── Скачивание бинарника ───────────────────────────────────────────────────────
echo "Скачивание бинарника"
TMP_DIR="$(mktemp -d)"
echo "  Downloading $TELEMT_URL"
curl -fL --connect-timeout 30 "$TELEMT_URL" -o "$TMP_DIR/telemt.tar.gz" \
	|| fail "Не удалось скачать бинарник"
tar -xzf "$TMP_DIR/telemt.tar.gz" -C "$TMP_DIR" \
	|| fail "Не удалось распаковать архив"
install -m 0755 "$TMP_DIR/telemt" "$BINARY_PATH" \
	|| fail "Не удалось установить бинарник в $BINARY_PATH"
rm -rf "$TMP_DIR"
ok "Бинарник установлен в $BINARY_PATH"

# ── Инициализация конфигурации ─────────────────────────────────────────────────
echo "Инициализация конфигурации"
$BINARY_PATH --init \
	--port "$PORT" \
	--domain "$DOMAIN" \
	--secret "$SECRET" \
	--user user \
	--config-dir "$CONFIG_DIR" \
	--no-start > /dev/null 2>&1 \
	|| fail "Инициализация конфигурации завершилась ошибкой"
ok "Конфиг инициализирован: $CONFIG_FILE"

# ── Отключение beobachten ──────────────────────────────────────────────────────
echo "Отключение beobachten"
set_config "beobachten" "false" '\[general\]'
ok "beobachten = false"

# ── Отключение IPv6 ────────────────────────────────────────────────────────────
echo "Отключение IPv6"
set_config "ipv6" "false" '\[network\]'
# Комментируем listen_addr_ipv6
sed -i 's/^listen_addr_ipv6 = "::"/#listen_addr_ipv6 = "::"/' "$CONFIG_FILE"
# Комментируем блок listeners с IPv6 — используем perl для многострочного match
perl -i -0pe 's/\[\[server\.listeners\]\]\nip = "::"/\#[[server.listeners]]\n#ip = "::"/g' "$CONFIG_FILE"
ok "IPv6 отключён"

# ── Уменьшение таймаутов клиентов ─────────────────────────────────────────────
echo "Уменьшение таймаутов клиентов"
set_config "client_keepalive" "15" '\[timeouts\]'
set_config "client_ack" "60" '\[timeouts\]'
ok "client_keepalive=15, client_ack=60"

# ── Тихое логирование ─────────────────────────────────────────────────────────
echo "Тихое логирование"
set_config 'log_level' '"silent"' '\[general\]'
ok "log_level = \"silent\""

# ── Отключение телеметрии ──────────────────────────────────────────────────────
echo "Отключение телеметрии"
grep -q '^\[general\.telemetry\]' "$CONFIG_FILE" \
	|| echo -e '\n[general.telemetry]\n' >> "$CONFIG_FILE"
set_config "core_enabled" "false" '\[general\.telemetry\]'
set_config "user_enabled" "false" '\[general\.telemetry\]'
ok "Телеметрия отключена"

# ── Отключение STUN ───────────────────────────────────────────────────────────
echo "Отключение STUN"
set_config "stun_use" "false" '\[network\]'
ok "stun_use = false"

# ── Лимит подключений ─────────────────────────────────────────────────────────
echo "Лимит подключений"
set_config "max_connections" "$MAX_CONNECTIONS" '\[server\]'
ok "max_connections = $MAX_CONNECTIONS"

# ── Отключение WEB-API ────────────────────────────────────────────────────────
echo "Отключение WEB-API"
grep -q '^\[server\.api\]' "$CONFIG_FILE" \
	|| echo -e '\n[server.api]\n' >> "$CONFIG_FILE"
# Заменяем enabled только внутри секции [server.api]
if grep -qE "^[[:space:]]*enabled[[:space:]]*=" "$CONFIG_FILE"; then
	# Используем perl для замены строго в нужной секции
	perl -i -0pe 's/(\[server\.api\][^\[]*?)enabled\s*=\s*\S+/${1}enabled = false/s' "$CONFIG_FILE"
else
	sed -i '/^\[server\.api\]/a enabled = false' "$CONFIG_FILE"
fi
ok "WEB-API отключён"

# ── Уменьшение буферов ────────────────────────────────────────────────────────
echo "Уменьшение буферов в $BUF_DIVISOR раз"
set_config "direct_relay_copy_buf_c2s_bytes" "$BUF_C2S" '\[general\]'
set_config "direct_relay_copy_buf_s2c_bytes" "$BUF_S2C" '\[general\]'
set_config "crypto_pending_buffer" "$BUF_CRYPTO" '\[general\]'
ok "Буферы: c2s=$BUF_C2S, s2c=$BUF_S2C, crypto=$BUF_CRYPTO"

# ── Рабочая директория ────────────────────────────────────────────────────────
echo "Рабочая директория telemt"
mkdir -p /var/lib/telemt
ok "Директория /var/lib/telemt создана"

# ── Запуск сервиса ────────────────────────────────────────────────────────────
echo "Запуск сервиса"
systemctl restart telemt || fail "Не удалось запустить сервис telemt"
# Даём секунду на старт и проверяем статус
sleep 1
if systemctl is-active --quiet telemt; then
	ok "Сервис telemt запущен и активен"
else
	fail "Сервис telemt запустился, но не активен — проверьте: journalctl -u telemt -n 50"
fi

# ── Итог ──────────────────────────────────────────────────────────────────────
echo
echo "================================================"
echo " Telegram proxy успешно установлен!"
echo "================================================"
echo " Сервер : ${IP}"
echo " Порт   : ${PORT}"
echo " Секрет : ${SECRET}"
echo " Домен  : ${DOMAIN}"
echo
echo "Ссылка для подключения:"
echo "tg://proxy?server=${IP}&port=${PORT}&secret=ee${SECRET}${DOMAIN_HEX}"
echo