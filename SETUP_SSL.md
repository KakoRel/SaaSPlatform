# 🔒 Настройка SSL для kanban.diligentcrossbill.com.ru

## Автоматическая настройка (рекомендуется)

```bash
# На VPS выполните:
cd /opt/saas-platform
chmod +x ssl-setup.sh

# Отредактируйте email в скрипте
nano ssl-setup.sh
# Замените: EMAIL="your-email@example.com" на ваш реальный email

# Запустите скрипт
sudo ./ssl-setup.sh
```

Скрипт автоматически:
- Остановит Docker контейнеры
- Установит Certbot (если не установлен)
- Получит SSL сертификат для `kanban.diligentcrossbill.com.ru`
- Настроит автоматическое обновление сертификата
- Запустит приложение с HTTPS

---

## Ручная настройка

### Шаг 1: Остановите контейнеры

```bash
cd /opt/saas-platform
docker compose down
```

### Шаг 2: Установите Certbot

```bash
sudo apt update
sudo apt install -y certbot
```

### Шаг 3: Получите SSL сертификат

```bash
sudo certbot certonly --standalone \
    -d kanban.diligentcrossbill.com.ru \
    --agree-tos \
    --email your-email@example.com
```

**Важно:** Замените `your-email@example.com` на ваш реальный email.

Сертификаты будут сохранены в:
- `/etc/letsencrypt/live/kanban.diligentcrossbill.com.ru/fullchain.pem`
- `/etc/letsencrypt/live/kanban.diligentcrossbill.com.ru/privkey.pem`

### Шаг 4: Обновите docker-compose.yml

Создайте файл `docker-compose-ssl.yml`:

```yaml
version: '3.8'

services:
  web:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: saas-platform-web
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - ./nginx-ssl.conf:/etc/nginx/conf.d/default.conf
    environment:
      - NODE_ENV=production
    networks:
      - app-network
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  app-network:
    driver: bridge
```

### Шаг 5: Запустите с SSL

```bash
docker compose -f docker-compose-ssl.yml up -d --build
```

### Шаг 6: Настройте автообновление сертификата

```bash
# Добавьте задачу в cron
sudo crontab -e

# Добавьте строку (обновление каждый день в 3:00)
0 3 * * * certbot renew --quiet && docker compose -f /opt/saas-platform/docker-compose-ssl.yml restart
```

---

## Проверка SSL

```bash
# Проверьте сертификат
sudo certbot certificates

# Проверьте работу HTTPS
curl -I https://kanban.diligentcrossbill.com.ru

# Проверьте редирект с HTTP на HTTPS
curl -I http://kanban.diligentcrossbill.com.ru
```

---

## Тестирование SSL

Откройте в браузере:
- https://kanban.diligentcrossbill.com.ru

Проверьте SSL рейтинг:
- https://www.ssllabs.com/ssltest/analyze.html?d=kanban.diligentcrossbill.com.ru

---

## Устранение проблем

### Ошибка: "Port 80 already in use"

```bash
# Остановите Docker
docker compose down

# Проверьте, что использует порт 80
sudo lsof -i :80

# Попробуйте снова
sudo ./ssl-setup.sh
```

### Ошибка: "DNS resolution failed"

Убедитесь, что DNS записи настроены правильно:

```bash
# Проверьте A-запись
dig kanban.diligentcrossbill.com.ru

# Должен вернуть IP вашего VPS
```

Если DNS не настроен, добавьте A-запись в панели управления доменом:
- **Тип**: A
- **Имя**: kanban.diligentcrossbill
- **Значение**: IP_вашего_VPS
- **TTL**: 300

Подождите 5-10 минут для распространения DNS.

### Сертификат не обновляется автоматически

```bash
# Проверьте cron задачи
sudo crontab -l

# Проверьте логи обновления
sudo certbot renew --dry-run

# Вручную обновите сертификат
sudo certbot renew
sudo docker compose -f /opt/saas-platform/docker-compose-ssl.yml restart
```

---

## Готово! 🎉

Ваше приложение доступно по адресу:
- **HTTPS**: https://kanban.diligentcrossbill.com.ru
- **HTTP** автоматически перенаправляется на HTTPS
