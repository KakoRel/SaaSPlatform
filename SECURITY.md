# 🔒 Безопасность и работа с секретами

## ⚠️ ВАЖНО: Никогда не коммитьте секреты в Git!

Этот проект настроен так, чтобы **чувствительные данные не попадали в Git**.

---

## 📋 Что НЕ должно попадать в Git

### ❌ Запрещено коммитить:
- Supabase URL и API ключи
- Пароли и токены
- SSL сертификаты и приватные ключи
- Файлы `.env`
- Файл `lib/core/constants/app_constants.dart` с реальными данными

### ✅ Можно коммитить:
- `.env.example` (шаблон без реальных данных)
- `app_constants.dart.example` (шаблон)
- Документацию
- Исходный код без секретов

---

## 🛠 Настройка проекта

### Шаг 1: Клонируйте репозиторий

```bash
git clone https://github.com/your-username/saas-platform.git
cd saas-platform
```

### Шаг 2: Создайте файл с реальными credentials

```bash
# Скопируйте шаблон
cp lib/core/constants/app_constants.dart.example lib/core/constants/app_constants.dart

# Отредактируйте файл
nano lib/core/constants/app_constants.dart
```

Замените значения:
```dart
static const String supabaseUrl = 'https://ваш-проект.supabase.co';
static const String supabaseAnonKey = 'ваш-реальный-anon-key';
```

**Важно:** Файл `app_constants.dart` уже добавлен в `.gitignore` и не будет закоммичен!

### Шаг 3: Проверьте, что секреты не попадут в Git

```bash
# Проверьте статус
git status

# app_constants.dart НЕ должен отображаться в списке изменений
```

---

## 🚀 Деплой на VPS

### Вариант 1: Через переменные окружения (рекомендуется)

На VPS создайте файл `.env`:

```bash
cd /opt/saas-platform
nano .env
```

Содержимое:
```env
SUPABASE_URL=https://ваш-проект.supabase.co
SUPABASE_ANON_KEY=ваш-anon-key
```

Затем в `app_constants.dart` используйте переменные окружения (для production):

```dart
static String get supabaseUrl => 
    const String.fromEnvironment('SUPABASE_URL', 
        defaultValue: 'YOUR_SUPABASE_URL');
```

### Вариант 2: Создание файла на сервере

```bash
# На VPS после клонирования
cd /opt/saas-platform
cp lib/core/constants/app_constants.dart.example lib/core/constants/app_constants.dart
nano lib/core/constants/app_constants.dart
# Вставьте реальные credentials
```

### Вариант 3: GitHub Secrets (для CI/CD)

В GitHub репозитории:
1. Settings → Secrets and variables → Actions
2. Добавьте секреты:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`

В `.github/workflows/deploy.yml` используйте:
```yaml
env:
  SUPABASE_URL: ${{ secrets.SUPABASE_URL }}
  SUPABASE_ANON_KEY: ${{ secrets.SUPABASE_ANON_KEY }}
```

---

## 🔍 Проверка безопасности

### Перед коммитом проверьте:

```bash
# Убедитесь, что секреты не в индексе
git diff --cached

# Проверьте историю (если случайно закоммитили)
git log --all --full-history -- lib/core/constants/app_constants.dart
```

### Если случайно закоммитили секреты:

```bash
# НЕМЕДЛЕННО удалите из истории
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch lib/core/constants/app_constants.dart" \
  --prune-empty --tag-name-filter cat -- --all

# Форсированно запушьте
git push origin --force --all

# ВАЖНО: Смените все секреты в Supabase!
# Settings → API → Reset anon key
```

---

## 📝 Checklist перед коммитом

- [ ] `app_constants.dart` не в списке изменений
- [ ] `.env` файлы не в списке изменений
- [ ] Нет паролей и токенов в коде
- [ ] Нет API ключей в комментариях
- [ ] SSL сертификаты не добавлены

---

## 🛡 Дополнительные меры безопасности

### 1. Используйте pre-commit hook

Создайте `.git/hooks/pre-commit`:

```bash
#!/bin/bash

# Проверка на наличие секретов
if git diff --cached --name-only | grep -q "app_constants.dart$"; then
    echo "❌ ОШИБКА: Попытка закоммитить app_constants.dart!"
    echo "Используйте app_constants.dart.example вместо этого"
    exit 1
fi

# Проверка на наличие .env файлов
if git diff --cached --name-only | grep -q "\.env"; then
    echo "❌ ОШИБКА: Попытка закоммитить .env файл!"
    exit 1
fi

exit 0
```

Сделайте исполняемым:
```bash
chmod +x .git/hooks/pre-commit
```

### 2. Используйте git-secrets

```bash
# Установите git-secrets
brew install git-secrets  # macOS
# или
apt install git-secrets   # Ubuntu

# Настройте
git secrets --install
git secrets --register-aws
```

### 3. Сканируйте на секреты

```bash
# Установите truffleHog
pip install truffleHog

# Сканируйте репозиторий
truffleHog --regex --entropy=False .
```

---

## 🔄 Ротация секретов

Регулярно меняйте секреты:

1. **Supabase API ключи** (каждые 3-6 месяцев)
   - Dashboard → Settings → API → Reset keys

2. **SSL сертификаты** (автоматически через Let's Encrypt)

3. **Пароли базы данных** (каждые 6 месяцев)

---

## 📞 Что делать при утечке

1. **Немедленно** смените все скомпрометированные ключи
2. Удалите секреты из истории Git
3. Проверьте логи доступа в Supabase
4. Уведомите команду
5. Проведите аудит безопасности

---

## 📚 Дополнительные ресурсы

- [Supabase Security Best Practices](https://supabase.com/docs/guides/platform/security)
- [GitHub Secrets Documentation](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [OWASP Secrets Management](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)

---

**Помните: Безопасность — это не одноразовая задача, а постоянный процесс!** 🔒
