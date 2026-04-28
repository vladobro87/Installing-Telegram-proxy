#!/bin/bash

# ==== CONFIG ====
xui_folder="/usr/local/x-ui"   # при необходимости измени путь

# ==== LOG FUNCTIONS ====
LOGI() { echo -e "[INFO] $1"; }
LOGE() { echo -e "[ERROR] $1"; }
LOGW() { echo -e "[WARN] $1"; }

# ==== HELPERS ====
is_ipv6() {
    [[ "$1" =~ : ]]
}

is_port_in_use() {
    ss -tuln | grep -q ":$1 "
}

install_acme() {
    curl https://get.acme.sh | sh
}

restart() {
    systemctl restart x-ui 2>/dev/null || true
}

# ==== MAIN FUNCTION ====
ssl_cert_issue_for_ip() {

    LOGI "Starting automatic SSL certificate generation for server IP..."

    local existing_webBasePath=$(${xui_folder}/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(${xui_folder}/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')

    local server_ip=$(curl -s --max-time 3 https://api.ipify.org)
    [ -z "$server_ip" ] && server_ip=$(curl -s --max-time 3 https://4.ident.me)

    if [ -z "$server_ip" ]; then
        LOGE "Failed to get server IP address"
        exit 1
    fi

    LOGI "Server IP detected: ${server_ip}"

    read -rp "IPv6 (optional): " ipv6_addr
    ipv6_addr="${ipv6_addr// /}"

    if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
        LOGI "Installing acme.sh..."
        install_acme
    fi

    apt-get update -y && apt-get install -y socat

    certPath="/root/cert/ip"
    mkdir -p "$certPath"

    domain_args="-d ${server_ip}"
    if [[ -n "$ipv6_addr" ]] && is_ipv6 "$ipv6_addr"; then
        domain_args="${domain_args} -d ${ipv6_addr}"
    fi

    read -rp "Port (default 80): " WebPort
    WebPort="${WebPort:-80}"

    while is_port_in_use "$WebPort"; do
        read -rp "Port busy. Enter another: " WebPort
    done

    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt --force

    ~/.acme.sh/acme.sh --issue \
        ${domain_args} \
        --standalone \
        --httpport ${WebPort} \
        --force

    if [ $? -ne 0 ]; then
        LOGE "Certificate issue failed"
        exit 1
    fi

    ~/.acme.sh/acme.sh --installcert -d ${server_ip} \
        --key-file "${certPath}/privkey.pem" \
        --fullchain-file "${certPath}/fullchain.pem"

    if [[ ! -f "${certPath}/fullchain.pem" ]]; then
        LOGE "Cert files not found"
        exit 1
    fi

    ${xui_folder}/x-ui cert \
        -webCert "${certPath}/fullchain.pem" \
        -webCertKey "${certPath}/privkey.pem"

    LOGI "SSL installed!"
    echo "https://${server_ip}:${existing_port}${existing_webBasePath}"

    restart
}

# ==== RUN ====
ssl_cert_issue_for_ip
