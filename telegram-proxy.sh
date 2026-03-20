#!/bin/bash
set -e

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
PORT="902"
DOMAIN="2gis.com"
VERSION="3.3.27"
DOMAIN_HEX=$(echo -n "$DOMAIN" | xxd -p)
BINARY_PATH="/usr/local/bin/telemt"
CONFIG_DIR="/etc/telemt"
CONFIG_FILE="$CONFIG_DIR/config.toml"
IP="$(ip route get 1.2.3.4 2>/dev/null | grep -oP 'src \K\S+')"
TMP_DIR="$(mktemp -d)"
ARCH="$(uname -m)"
LIBC="gnu"
TELEMT_URL="https://github.com/telemt/telemt/releases/download/${VERSION}/telemt-${ARCH}-linux-${LIBC}.tar.gz"
if [[ -f "$CONFIG_FILE" ]]; then
    OLD_SECRET="$(sed -n 's/^[[:space:]]*user[[:space:]]*=[[:space:]]*"\([0-9a-fA-F]\{32\}\)".*/\1/p' "$CONFIG_FILE" | head -n 1)"
fi
SECRET="${OLD_SECRET:-$(openssl rand -hex 16)}"

# Остановка сервиса
systemctl disable --now telemt 2>/dev/null || true

# Скачивание бинарника
curl -fL --connect-timeout 30 "$TELEMT_URL" -o "$TMP_DIR/telemt.tar.gz"
tar -xvzf "$TMP_DIR/telemt.tar.gz" -C "$TMP_DIR"
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

# Отключение beobachten и ipv6
sed -i '/^[[:space:]]*beobachten[[:space:]]*=/d' "$CONFIG_FILE"
sed -i '/^\[general\]/a beobachten = false' "$CONFIG_FILE"
sed -i '/^[[:space:]]*ipv6[[:space:]]*=/d' "$CONFIG_FILE"
sed -i '/^\[network\]/a ipv6 = false' "$CONFIG_FILE"
sed -i '/^\[\[server\.listeners\]\]$/ {N; /^\[\[server\.listeners\]\][[:space:]]*\n[[:space:]]*ip = "::"[[:space:]]*$/d; }' "$CONFIG_FILE"

# Запуск сервиса
systemctl restart telemt

# Ссылка на прокси-сервер
echo
echo "Telegram proxy link:"
echo "tg://proxy?server=${IP}&port=${PORT}&secret=ee${SECRET}${DOMAIN_HEX}"
echo
