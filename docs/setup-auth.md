# Настройка аутентификации Supabase

## 1. Создание проекта Supabase

1. Перейдите на [supabase.com](https://supabase.com)
2. Создайте новый проект или используйте существующий
3. Скопируйте **Project URL** и **anon key** из настроек проекта

## 2. Настройка приложения

1. Откройте файл `lib/core/constants/app_constants.dart`
2. Замените плейсхолдеры на реальные значения:

```dart
class AppConstants {
  // ...
  static const String supabaseUrl = 'https://your-project-id.supabase.co';
  static const String supabaseAnonKey = 'your-anon-key-here';
  // ...
}
```

## 3. Настройка таблиц в Supabase

### Таблица users

Выполните в SQL Editor Supabase:

```sql
CREATE TABLE IF NOT EXISTS users (
  id UUID REFERENCES auth.users(id) PRIMARY KEY,
  full_name TEXT,
  avatar_url TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Создаем политику для чтения
CREATE POLICY "Users can view own profile" ON users
  FOR SELECT USING (auth.uid() = id);

-- Создаем политику для обновления
CREATE POLICY "Users can update own profile" ON users
  FOR UPDATE USING (auth.uid() = id);

-- Создаем политику для вставки
CREATE POLICY "Users can insert own profile" ON users
  FOR INSERT WITH CHECK (auth.uid() = id);
```

### Триггер для автоматического создания профиля

```sql
-- Функция для создания профиля пользователя
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (id, full_name)
  VALUES (new.id, new.raw_user_meta_data->>'full_name');
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Триггер для вызова функции при регистрации
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();
```

## 4. Настройка Email подтверждения и Redirect URLs

В настройках проекта Supabase:
1. Перейдите в Authentication → Settings
2. В разделе **Site URL** добавьте: `http://localhost:3000`
3. В разделе **Redirect URLs** добавьте:
   - `http://localhost:3000/auth/callback`
   - `http://localhost:3000/**` (для всех остальных редиректов)
4. Настройте Email templates для подтверждения регистрации

**Subject (Тема письма):**
```
Подтвердите ваш аккаунт в TaskFlow
```

**Body (Тело письма):**
```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Подтверждение аккаунта</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 600px;
            margin: 0 auto;
            padding: 20px;
            background-color: #f4f4f4;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 0 20px rgba(0,0,0,0.1);
        }
        .header {
            text-align: center;
            margin-bottom: 30px;
        }
        .logo {
            font-size: 32px;
            font-weight: bold;
            color: #2563eb;
            margin-bottom: 10px;
        }
        .button {
            display: inline-block;
            background: #2563eb;
            color: white;
            padding: 12px 30px;
            text-decoration: none;
            border-radius: 6px;
            font-weight: bold;
            margin: 20px 0;
        }
        .button:hover {
            background: #1d4ed8;
        }
        .footer {
            text-align: center;
            margin-top: 30px;
            color: #666;
            font-size: 14px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="logo">📋 TaskFlow</div>
            <h2>Подтвердите ваш аккаунт</h2>
        </div>
        
        <p>Здравствуйте! 👋</p>
        
        <p>Спасибо за регистрацию в <strong>TaskFlow</strong> - платформе для управления задачами.</p>
        
        <p>Для завершения регистрации и получения доступа к вашему аккаунту, пожалуйста, подтвердите ваш email:</p>
        
        <div style="text-align: center;">
            <a href="{{ .ConfirmationURL }}" class="button">Подтвердить Email</a>
        </div>
        
        <p>Если кнопка не работает, скопируйте и вставьте эту ссылку в браузер:</p>
        <p style="word-break: break-all; background: #f4f4f4; padding: 10px; border-radius: 4px; font-family: monospace;">
            {{ .ConfirmationURL }}
        </p>
        
        <p><strong>Важно:</strong> Эта ссылка действительна 24 часа. Если вы не регистрировались в TaskFlow, проигнорируйте это письмо.</p>
        
        <div class="footer">
            <p>С уважением,<br>Команда TaskFlow</p>
            <p style="font-size: 12px; color: #999;">
                Это автоматическое письмо, пожалуйста, не отвечайте на него.
            </p>
        </div>
    </div>
</body>
</html>
```

5. Убедитесь, что включена опция подтверждения email (если она есть в вашей версии Supabase)

**Важно**: Убедитесь, что redirect URL в настройках Supabase совпадает с тем, что указан в коде (`http://localhost:3000/auth/callback`).

## 5. Использование приложения

Теперь вы можете:
- **Зарегистрироваться**: введите email, пароль и имя
- **Войти**: используйте существующие учетные данные
- **Сбросить пароль**: нажмите "Забыли пароль?" на экране входа

## 6. Тестирование

Для тестирования можно создать тестового пользователя:
1. Зарегистрируйтесь через приложение
2. Проверьте email (если включено подтверждение)
3. Попробуйте войти

## Устранение проблем

### Ошибка 400 (Bad Request)
- Убедитесь, что Supabase URL и anon ключ правильные
- Проверьте, что проект Supabase активен

### Ошибка аутентификации
- Проверьте настройки RLS политик
- Убедитесь, что таблицы созданы правильно

### Проблемы с email
- Проверьте настройки SMTP в Supabase
- Убедитесь, что email не попадает в спам
