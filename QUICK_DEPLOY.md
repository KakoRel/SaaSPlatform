# ⚡ Быстрый деплой на VPS

## Минимальная установка (5 минут)

```bash
# 1. Подключитесь к VPS
ssh root@your_server_ip

# 2. Установите Docker одной командой
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# 3. Установите Docker Compose
apt install -y docker-compose-plugin

# 4. Клонируйте проект
mkdir -p /opt/SaaSPlatform && cd /opt/SaaSPlatform
git clone https://github.com/KakoRel/SaaSPlatform.git .

# 5. Настройте Supabase credentials
nano lib/core/constants/app_constants.dart
# Замените supabaseUrl и supabaseAnonKey

# 6. Запустите
chmod +x deploy.sh
./deploy.sh
```

## Проверка работы

```bash
# Проверьте статус
docker compose ps

# Откройте в браузере
http://your_server_ip
```

## Если что-то пошло не так

```bash
# Смотрите логи
docker compose logs -f

# Перезапустите
docker compose restart

# Пересоберите с нуля
docker compose down
docker compose build --no-cache
docker compose up -d
```

## Обновление приложения

```bash
cd /opt/SaaSPlatform
git pull
./deploy.sh
```

---

**Готово! Приложение работает на http://your_server_ip** 🚀
