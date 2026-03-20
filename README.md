# Installing-Telegram-proxy

Один порт **8443**: по SNI трафик к домену маскировки (например `vk.com`) 

- **Telemt** — современный MTProxy (Rust, distroless), поддерживает Fake TLS.

## Установка на сервере (всё тянется с GitHub)
```bash
curl -sSL https://raw.githubusercontent.com/vladobro87/Installing-Telegram-proxy/main/telegram-proxy.sh | bash
```
