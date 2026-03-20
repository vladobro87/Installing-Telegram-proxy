# Installing-Telegram-proxy

Один порт **8443**: по SNI трафик к домену маскировки (например `vk.com`) 

- **Telemt** — современный Telemt - MTProxy on Rust + Tokio https://github.com/telemt/telemt.
- скипрт автоматической установки:
- можно задать свой PORT и DOMAIN

### Параметры
- PORT="8443"
- DOMAIN="vk.com"
- VERSION="3.3.27"
- BINARY_PATH="/usr/local/bin/telemt"
- CONFIG_DIR="/etc/telemt"

## Установка на сервере (всё тянется с GitHub)
```bash
curl -sSL https://raw.githubusercontent.com/vladobro87/Installing-Telegram-proxy/main/telegram-proxy.sh | bash
```

## Удаление
```bash
systemctl disable --now telemt 2>/dev/null; rm -f /etc/systemd/system/telemt.service; systemctl daemon-reload; rm -f /usr/local/bin/telemt; rm -rf /etc/telemt
```
или
```bash
systemctl stop telemt && systemctl disable telemt && rm -f /etc/systemd/system/telemt.service && systemctl daemon-reload && systemctl reset-failed && rm -f /usr/local/bin/telemt && rm -rf /etc/telemt
```
