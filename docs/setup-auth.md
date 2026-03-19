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

## 4. Настройка Email подтверждения (опционально)

В настройках проекта Supabase:
1. Перейдите в Authentication → Settings
2. Настройте Email templates для подтверждения регистрации
3. Включите "Enable email confirmations"

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
