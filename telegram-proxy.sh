#!/bin/bash
set -e
# 2026-04-02
echo
echo "Installing Telegram proxy..."
echo

# Обновление системы
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get dist-upgrade -y
apt-get install -y curl openssl xxd
apt-get autoremove --purge -y
apt-get clean

# Параметры
PORT=8443				# Порт для прокси-сервера
DOMAIN="eh.vk.comm"		# Домен для маскировки TLS
VERSION=""				# Версия telemt (если версия не указана то ставим последнюю релизную версию)
MAX_CONNECTIONS=2000	# Максимальное количество одновременных TCP подключений (0 = без лимита)
BUF_DIVISOR=4			# Делитель буферов - уменьшает буферы если не хватает оперативной памяти (1-16, по умолчанию без деления = 1)

# Максимум TCP подключений для 1Gb оперативной памяти:
# MAX_CONNECTIONS=1000 при BUF_DIVISOR=1
# MAX_CONNECTIONS=2000 при BUF_DIVISOR=4
# MAX_CONNECTIONS=4000 при BUF_DIVISOR=16
# Уменьшение буферов в 4 раза дает увеличение количества TCP подключений в 2 раза

# Переменные
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
if [[ -f "$CONFIG_FILE" ]]; then
	OLD_SECRET="$(sed -n 's/^[[:space:]]*user[[:space:]]*=[[:space:]]*"\([0-9a-fA-F]\{32\}\)".*/\1/p' "$CONFIG_FILE" | head -n 1)"
	OLD_PORT="$(awk -F'=' '/^\[server\]/{in_server=1; next} /^\[/{in_server=0} in_server && $1 ~ /^[[:space:]]*port[[:space:]]*$/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' "$CONFIG_FILE")"
	OLD_DOMAIN="$(sed -n 's/^[[:space:]]*tls_domain[[:space:]]*=[[:space:]]*"\([^"]\+\)".*/\1/p' "$CONFIG_FILE" | head -n 1)"
fi
SECRET="${OLD_SECRET:-$(openssl rand -hex 16)}"
PORT="${OLD_PORT:-$PORT}"
DOMAIN="${OLD_DOMAIN:-$DOMAIN}"
DOMAIN_HEX=$(echo -n "$DOMAIN" | xxd -p)
BUF_C2S=$((65536 / BUF_DIVISOR))
BUF_S2C=$((262144 / BUF_DIVISOR))
BUF_CRYPTO=$((262144 / BUF_DIVISOR))

# Остановка сервиса
systemctl disable --now telemt 2>/dev/null || true

# Скачивание бинарника
TMP_DIR="$(mktemp -d)"
echo "Downloading $TELEMT_URL"
curl -fL --connect-timeout 30 "$TELEMT_URL" -o "$TMP_DIR/telemt.tar.gz"
tar -xzf "$TMP_DIR/telemt.tar.gz" -C "$TMP_DIR"
install -m 0755 "$TMP_DIR/telemt" "$BINARY_PATH"
rm -rf "$TMP_DIR"

# Инициализация конфигурации
$BINARY_PATH --init \
	--port "$PORT" \
	--domain "$DOMAIN" \
	--secret "$SECRET" \
	--user user \
	--config-dir "$CONFIG_DIR" \
	--no-start > /dev/null 2>&1

# Отключение beobachten
sed -i 's/^beobachten = .*/beobachten = false/' "$CONFIG_FILE"
grep -q '^beobachten = false' "$CONFIG_FILE" || sed -i '/^\[general\]/a beobachten = false' "$CONFIG_FILE"

# Отключение IPv6
sed -i 's/^ipv6 = .*/ipv6 = false/' "$CONFIG_FILE"
grep -q '^ipv6 = false' "$CONFIG_FILE" || sed -i '/^\[network\]/a ipv6 = false' "$CONFIG_FILE"
sed -i 's/^listen_addr_ipv6 = "::"/#listen_addr_ipv6 = "::"/' "$CONFIG_FILE"
sed -i '/^\[\[server\.listeners\]\]$/{N;s|^\[\[server\.listeners\]\]\nip = "::"|#[[server.listeners]]\n#ip = "::"|;}' "$CONFIG_FILE"

# Уменьшение таймаутов клиентов
sed -i 's/^client_keepalive = .*/client_keepalive = 15/' "$CONFIG_FILE"
grep -q '^client_keepalive' "$CONFIG_FILE" || sed -i '/^\[timeouts\]/a client_keepalive = 15' "$CONFIG_FILE"
sed -i 's/^client_ack = .*/client_ack = 60/' "$CONFIG_FILE"
grep -q '^client_ack' "$CONFIG_FILE" || sed -i '/^\[timeouts\]/a client_ack = 60' "$CONFIG_FILE"

# Тихое логирование
sed -i 's/^log_level = .*/log_level = "silent"/' "$CONFIG_FILE"
grep -q '^log_level = "silent"' "$CONFIG_FILE" || sed -i '/^\[general\]/a log_level = "silent"' "$CONFIG_FILE"

# Отключение телеметрии
grep -q '^\[general\.telemetry\]' "$CONFIG_FILE" || echo -e '\n[general.telemetry]\n' >> "$CONFIG_FILE"
sed -i 's/^core_enabled = .*/core_enabled = false/' "$CONFIG_FILE"
grep -q '^core_enabled' "$CONFIG_FILE" || sed -i '/^\[general\.telemetry\]/a core_enabled = false' "$CONFIG_FILE"
sed -i 's/^user_enabled = .*/user_enabled = false/' "$CONFIG_FILE"
grep -q '^user_enabled' "$CONFIG_FILE" || sed -i '/^\[general\.telemetry\]/a user_enabled = false' "$CONFIG_FILE"

# Отключение STUN
sed -i 's/^stun_use = .*/stun_use = false/' "$CONFIG_FILE"
grep -q '^stun_use' "$CONFIG_FILE" || sed -i '/^\[network\]/a stun_use = false' "$CONFIG_FILE"

# Лимит подключений
sed -i "s/^max_connections = .*/max_connections = $MAX_CONNECTIONS/" "$CONFIG_FILE"
grep -q '^max_connections' "$CONFIG_FILE" || sed -i "/^\[server\]/a max_connections = $MAX_CONNECTIONS" "$CONFIG_FILE"

# Отключение WEB-API
grep -q '^\[server\.api\]' "$CONFIG_FILE" || echo -e '\n[server.api]\n' >> "$CONFIG_FILE"
sed -i '/^\[server\.api\]/,/^\[/{s/^enabled *=.*/enabled = false/}' "$CONFIG_FILE"
grep -q '^enabled = false' "$CONFIG_FILE" || sed -i '/^\[server\.api\]/a enabled = false' "$CONFIG_FILE"

# Уменьшение буферов в BUF_DIVISOR раз
sed -i "s/^direct_relay_copy_buf_c2s_bytes = .*/direct_relay_copy_buf_c2s_bytes = $BUF_C2S/" "$CONFIG_FILE"
grep -q '^direct_relay_copy_buf_c2s_bytes' "$CONFIG_FILE" || sed -i "/^\[general\]/a direct_relay_copy_buf_c2s_bytes = $BUF_C2S" "$CONFIG_FILE"
sed -i "s/^direct_relay_copy_buf_s2c_bytes = .*/direct_relay_copy_buf_s2c_bytes = $BUF_S2C/" "$CONFIG_FILE"
grep -q '^direct_relay_copy_buf_s2c_bytes' "$CONFIG_FILE" || sed -i "/^\[general\]/a direct_relay_copy_buf_s2c_bytes = $BUF_S2C" "$CONFIG_FILE"
sed -i "s/^crypto_pending_buffer = .*/crypto_pending_buffer = $BUF_CRYPTO/" "$CONFIG_FILE"
grep -q '^crypto_pending_buffer' "$CONFIG_FILE" || sed -i "/^\[general\]/a crypto_pending_buffer = $BUF_CRYPTO" "$CONFIG_FILE"

# Рабочая директория telemt
mkdir -p /var/lib/telemt

# Запуск сервиса
systemctl restart telemt

# Ссылка на прокси-сервер
echo
echo "Telegram proxy link:"
echo "tg://proxy?server=${IP}&port=${PORT}&secret=ee${SECRET}${DOMAIN_HEX}"
echo
