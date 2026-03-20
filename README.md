# Installing-Telegram-proxy

Один порт **8443**: по SNI трафик к домену маскировки (например `vk.com`) 

- **Telemt** — современный MTProxy (Rust, distroless), поддерживает Fake TLS.

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
