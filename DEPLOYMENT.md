# 📦 Инструкция по развертыванию на VPS

## Требования к серверу

- **ОС**: Ubuntu 20.04/22.04 LTS или Debian 11/12
- **RAM**: минимум 2GB (рекомендуется 4GB)
- **CPU**: 2 ядра
- **Диск**: минимум 20GB свободного места
- **Сеть**: публичный IP адрес

---

## Шаг 1: Подключение к VPS

```bash
# Подключитесь к серверу по SSH
ssh root@ваш_ip_адрес

# Или если используете пользователя с sudo
ssh username@ваш_ip_адрес
```

---

## Шаг 2: Обновление системы

```bash
# Обновите список пакетов
sudo apt update

# Обновите установленные пакеты
sudo apt upgrade -y

# Установите необходимые утилиты
sudo apt install -y curl wget git nano ufw
```

---

## Шаг 3: Установка Docker

```bash
# Удалите старые версии Docker (если есть)
sudo apt remove docker docker-engine docker.io containerd runc

# Установите зависимости
sudo apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Добавьте официальный GPG ключ Docker
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Добавьте репозиторий Docker
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Установите Docker Engine
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Проверьте установку
docker --version
docker compose version

# Добавьте текущего пользователя в группу docker (чтобы не использовать sudo)
sudo usermod -aG docker $USER

# Перелогиньтесь для применения изменений
exit
# Подключитесь снова
ssh username@ваш_ip_адрес
```

---

## Шаг 4: Настройка Firewall (UFW)

```bash
# Включите UFW
sudo ufw enable

# Разрешите SSH (ВАЖНО: сделайте это ДО включения firewall!)
sudo ufw allow 22/tcp

# Разрешите HTTP
sudo ufw allow 80/tcp

# Разрешите HTTPS
sudo ufw allow 443/tcp

# Проверьте статус
sudo ufw status
```

---

## Шаг 5: Клонирование проекта

```bash
# Создайте директорию для проекта
sudo mkdir -p /opt/SaaSPlatform
sudo chown $USER:$USER /opt/SaaSPlatform

# Перейдите в директорию
cd /opt/SaaSPlatform

# Клонируйте репозиторий
git clone https://github.com/KakoRel/SaaSPlatform.git .

# Или если используете SSH ключ
git clone git@github.com:Kakorel/SaaSPlatform.git .
```

---

## Шаг 6: Настройка Supabase

### 6.1 Создание проекта в Supabase

1. Зайдите на https://supabase.com
2. Создайте новый проект
3. Скопируйте **Project URL** и **anon public key**

### 6.2 Применение миграции базы данных

```bash
# В Supabase Dashboard перейдите в SQL Editor
# Скопируйте содержимое файла database/migration.sql
# Выполните SQL скрипт
```

Или используйте Supabase CLI:

```bash
# Установите Supabase CLI
npm install -g supabase

# Войдите в Supabase
supabase login

# Примените миграцию
supabase db push
```

### 6.3 Настройка переменных окружения

```bash
# Создайте файл с переменными окружения
nano /opt/SaaSPlatform/lib/core/constants/app_constants.dart

# Замените значения:
static const String supabaseUrl = 'https://ваш-проект.supabase.co';
static const String supabaseAnonKey = 'ваш-anon-key';
```

---

## Шаг 7: Сборка и запуск приложения

```bash
# Перейдите в директорию проекта
cd /opt/SaaSPlatform

# Сделайте скрипт деплоя исполняемым
chmod +x deploy.sh

# Запустите деплой
sudo ./deploy.sh
```

Или вручную:

```bash
# Соберите Docker образ
docker compose build

# Запустите контейнер
docker compose up -d

# Проверьте статус
docker compose ps

# Посмотрите логи
docker compose logs -f
```

---

## Шаг 8: Настройка SSL (HTTPS) с Let's Encrypt

### 8.1 Установка Certbot

```bash
# Установите Certbot
sudo apt install -y certbot python3-certbot-nginx

# Остановите текущий контейнер
docker compose down
```

### 8.2 Получение SSL сертификата

```bash
# Получите сертификат (замените на ваш домен)
sudo certbot certonly --standalone -d yourdomain.com -d www.yourdomain.com

# Сертификаты будут сохранены в:
# /etc/letsencrypt/live/yourdomain.com/fullchain.pem
# /etc/letsencrypt/live/yourdomain.com/privkey.pem
```

### 8.3 Обновите nginx.conf для HTTPS

Создайте новый файл `nginx-ssl.conf`:

```nginx
server {
    listen 80;
    server_name yourdomain.com www.yourdomain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name yourdomain.com www.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    root /usr/share/nginx/html;
    index index.html;

    # Остальная конфигурация как в nginx.conf
    # ...
}
```

### 8.4 Обновите docker-compose.yml

```yaml
services:
  web:
    # ...
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /etc/letsencrypt:/etc/letsencrypt:ro
```

### 8.5 Автоматическое обновление сертификата

```bash
# Добавьте задачу в cron
sudo crontab -e

# Добавьте строку (обновление каждый день в 3:00)
0 3 * * * certbot renew --quiet && docker compose -f /opt/SaaSPlatform/docker-compose.yml restart
```

---

## Шаг 9: Мониторинг и обслуживание

### Просмотр логов

```bash
# Все логи
docker compose logs -f

# Только веб-сервер
docker compose logs -f web

# Последние 100 строк
docker compose logs --tail=100 web
```

### Перезапуск приложения

```bash
cd /opt/SaaSPlatform
docker compose restart
```

### Обновление приложения

```bash
cd /opt/SaaSPlatform
git pull origin main
sudo ./deploy.sh
```

### Проверка использования ресурсов

```bash
# Использование Docker контейнерами
docker stats

# Использование диска
df -h

# Использование памяти
free -h

# Загрузка CPU
top
```

---

## Шаг 10: Резервное копирование

### Создание бэкапа

```bash
# Создайте директорию для бэкапов
mkdir -p /opt/backups

# Бэкап базы данных Supabase (через Supabase Dashboard)
# Settings -> Database -> Backups

# Бэкап файлов приложения
tar -czf /opt/backups/SaaSPlatform-$(date +%Y%m%d).tar.gz /opt/SaaSPlatform
```

### Автоматический бэкап (cron)

```bash
# Создайте скрипт бэкапа
nano /opt/backup.sh
```

Содержимое скрипта:

```bash
#!/bin/bash
BACKUP_DIR="/opt/backups"
DATE=$(date +%Y%m%d_%H%M%S)
tar -czf $BACKUP_DIR/SaaSPlatform-$DATE.tar.gz /opt/SaaSPlatform
# Удалить бэкапы старше 7 дней
find $BACKUP_DIR -name "SaaSPlatform-*.tar.gz" -mtime +7 -delete
```

```bash
# Сделайте скрипт исполняемым
chmod +x /opt/backup.sh

# Добавьте в cron (каждый день в 2:00)
sudo crontab -e
0 2 * * * /opt/backup.sh
```

---

## Устранение неполадок

### Приложение не запускается

```bash
# Проверьте логи
docker compose logs

# Проверьте статус контейнера
docker compose ps

# Пересоберите образ
docker compose down
docker compose build --no-cache
docker compose up -d
```

### Порт уже занят

```bash
# Найдите процесс, использующий порт 80
sudo lsof -i :80

# Остановите процесс
sudo kill -9 PID
```

### Недостаточно памяти

```bash
# Проверьте использование памяти
free -h

# Очистите Docker кэш
docker system prune -af --volumes
```

### Проблемы с SSL

```bash
# Проверьте сертификаты
sudo certbot certificates

# Обновите сертификаты вручную
sudo certbot renew

# Проверьте конфигурацию nginx
docker exec saas-platform-web nginx -t
```

---

## Полезные команды

```bash
# Просмотр всех контейнеров
docker ps -a

# Остановить все контейнеры
docker compose down

# Удалить все неиспользуемые образы
docker image prune -a

# Войти в контейнер
docker exec -it saas-platform-web sh

# Проверить health check
curl http://localhost/health

# Перезагрузить nginx внутри контейнера
docker exec saas-platform-web nginx -s reload
```

---

## Безопасность

### Рекомендации

1. **Измените SSH порт** (по умолчанию 22)
2. **Отключите вход root по SSH**
3. **Используйте SSH ключи** вместо паролей
4. **Настройте fail2ban** для защиты от брутфорса
5. **Регулярно обновляйте систему**
6. **Используйте сильные пароли**
7. **Включите автоматические обновления безопасности**

### Установка fail2ban

```bash
sudo apt install -y fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

---

## Контакты и поддержка

Если возникли проблемы:
1. Проверьте логи: `docker compose logs`
2. Проверьте документацию Supabase
3. Создайте issue в GitHub репозитории

---

**Готово! Ваше приложение развернуто и работает! 🎉**

Доступ: `http://ваш_ip_адрес` или `https://yourdomain.com`
