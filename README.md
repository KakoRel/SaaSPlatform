# 🚀 SaaS Task Management Platform

Современная платформа для управления задачами в стиле Trello/Jira, построенная на Flutter Web, Supabase и Riverpod.

## ✨ Возможности

- 📋 **Kanban доски** с drag-and-drop
- 👥 **Управление проектами** и командами
- 🔐 **Row Level Security (RLS)** на уровне базы данных
- 🎨 **Material 3 UI** с адаптивным дизайном
- 📱 **Responsive** дизайн для mobile/tablet/desktop
- ⚡ **Realtime обновления** через Supabase
- 🔒 **Аутентификация** и авторизация
- 🎯 **Приоритеты задач** и дедлайны
- 💬 **Комментарии** к задачам

## 🛠 Технологический стек

- **Frontend**: Flutter Web (stable)
- **Backend**: Supabase (PostgreSQL + Auth + Realtime + Storage)
- **State Management**: Riverpod
- **Routing**: GoRouter
- **UI**: Material 3
- **Deployment**: Docker + Nginx

## 📋 Требования

- Flutter SDK 3.11.1+
- Dart SDK 3.11.1+
- Supabase аккаунт
- Docker (для деплоя)

## 🚀 Быстрый старт

### Локальная разработка

```bash
# Клонируйте репозиторий
git clone https://github.com/your-username/saas-platform.git
cd saas-platform

# Установите зависимости
flutter pub get

# Настройте Supabase credentials
# Отредактируйте lib/core/constants/app_constants.dart

# Запустите приложение
flutter run -d chrome
```

### Деплой на VPS

См. подробную инструкцию в [DEPLOYMENT.md](DEPLOYMENT.md)

Быстрый деплой:
```bash
# На VPS
curl -fsSL https://get.docker.com | sh
git clone https://github.com/your-username/saas-platform.git /opt/saas-platform
cd /opt/saas-platform
chmod +x deploy.sh
./deploy.sh
```

## 📁 Структура проекта

```
lib/
├── core/
│   ├── constants/       # Константы приложения
│   ├── errors/          # Обработка ошибок
│   ├── models/          # Базовые модели
│   ├── services/        # Сервисы (Supabase)
│   ├── theme/           # Material 3 темы
│   └── utils/           # Утилиты (RLS)
├── features/
│   ├── auth/            # Аутентификация
│   ├── kanban/          # Kanban доски
│   └── projects/        # Управление проектами
└── shared/
    └── presentation/    # Общие виджеты
```

## 🗄 База данных

Схема базы данных находится в `database/migration.sql`

Основные таблицы:
- `users` - пользователи
- `projects` - проекты
- `project_members` - участники проектов
- `tasks` - задачи
- `task_comments` - комментарии

## 🔐 Безопасность

- Row Level Security (RLS) политики на всех таблицах
- JWT аутентификация через Supabase
- Проверка прав доступа на frontend и backend
- HTTPS через Let's Encrypt

## 📚 Документация

- [Полная инструкция по деплою](DEPLOYMENT.md)
- [Быстрый деплой](QUICK_DEPLOY.md)
- [Supabase документация](https://supabase.com/docs)
- [Flutter Web документация](https://docs.flutter.dev/platform-integration/web)

## 🤝 Вклад в проект

1. Fork проекта
2. Создайте feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit изменения (`git commit -m 'Add some AmazingFeature'`)
4. Push в branch (`git push origin feature/AmazingFeature`)
5. Откройте Pull Request

## 📝 Лицензия

MIT License

## 👨‍💻 Автор

Ваше имя - [@your-username](https://github.com/your-username)

## 🙏 Благодарности

- [Flutter](https://flutter.dev)
- [Supabase](https://supabase.com)
- [Riverpod](https://riverpod.dev)
- [Material Design 3](https://m3.material.io)
