#!/bin/bash

set -e
set -o pipefail
#set -x  # раскомментируй если нужен полный трейс команд

LOGI() { echo -e "\e[32m[INFO]\e[0m $1"; }
LOGE() { echo -e "\e[31m[ERROR]\e[0m $1"; }
LOGW() { echo -e "\e[33m[WARN]\e[0m $1"; }

is_port_in_use() {
    ss -tuln | grep -q ":$1 "
}

install_acme() {
    LOGI "Installing acme.sh..."
    curl https://get.acme.sh | sh
}

LOGI "=== SSL SCRIPT START ==="

# ---- IP ----
LOGI "Detecting public IP..."
server_ip=$(curl -v -s --max-time 5 https://api.ipify.org)

if [ -z "$server_ip" ]; then
    LOGW "Primary IP service failed, trying backup..."
    server_ip=$(curl -v -s --max-time 5 https://4.ident.me)
fi

if [ -z "$server_ip" ]; then
    LOGE "Cannot detect public IP"
    exit 1
fi

LOGI "Detected IP: $server_ip"

# ---- acme.sh ----
if [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
    install_acme
else
    LOGI "acme.sh already installed"
fi

# ---- socat ----
LOGI "Installing socat..."
apt-get update
apt-get install -y socat

# ---- port ----
read -rp "Port for validation (default 80): " WebPort
WebPort="${WebPort:-80}"

LOGI "Checking port $WebPort..."
while is_port_in_use "$WebPort"; do
    LOGW "Port $WebPort is busy"
    read -rp "Enter another port: " WebPort
done

LOGI "Port $WebPort is free"

# ---- cert path ----
certPath="/root/cert/ip"
mkdir -p "$certPath"

LOGI "Cert path: $certPath"

# ---- issue cert ----
LOGI "Setting Let's Encrypt as default CA..."
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt --force

LOGI "Issuing certificate..."
~/.acme.sh/acme.sh --issue \
    -d "$server_ip" \
    --standalone \
    --httpport "$WebPort" \
    --server letsencrypt \
    --certificate-profile shortlived \
    --days 6 \
    --force

LOGI "acme.sh exit code: $?"

if [ $? -ne 0 ]; then
    LOGE "Certificate issue FAILED"
    exit 1
fi

# ---- install cert ----
LOGI "Installing certificate files..."
~/.acme.sh/acme.sh --installcert -d "$server_ip" \
    --key-file "$certPath/privkey.pem" \
    --fullchain-file "$certPath/fullchain.pem"

LOGI "Checking result..."
ls -la "$certPath"

if [[ ! -f "$certPath/fullchain.pem" ]]; then
    LOGE "Certificate not found"
    exit 1
fi

LOGI "=== SUCCESS ==="
echo "Certificate:"
echo "  Key: $certPath/privkey.pem"
echo "  Cert: $certPath/fullchain.pem"

