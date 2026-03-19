# SaaS Task Management Platform - Project Structure

## 📁 Feature-First Clean Architecture

```
lib/
├── main.dart
├── app/
│   ├── app.dart
│   ├── router/
│   │   ├── app_router.dart
│   │   └── route_names.dart
│   └── providers/
│       └── app_providers.dart
│
├── core/                           # Global utilities and services
│   ├── constants/
│   │   ├── app_constants.dart
│   │   ├── api_constants.dart
│   │   └── route_constants.dart
│   ├── errors/
│   │   ├── exceptions.dart
│   │   ├── failures.dart
│   │   └── error_handler.dart
│   ├── models/
│   │   ├── base_model.dart
│   │   └── pagination_model.dart
│   ├── services/
│   │   ├── supabase_client.dart
│   │   ├── storage_service.dart
│   │   └── notification_service.dart
│   ├── theme/
│   │   ├── app_theme.dart
│   │   ├── colors.dart
│   │   ├── text_styles.dart
│   │   └── theme_extensions.dart
│   ├── utils/
│   │   ├── date_utils.dart
│   │   ├── validation_utils.dart
│   │   ├── format_utils.dart
│   │   └── web_utils.dart
│   └── widgets/
│       ├── custom_buttons.dart
│       ├── custom_text_fields.dart
│       ├── loading_widgets.dart
│       └── custom_cards.dart
│
├── features/                       # Feature modules
│   ├── auth/                       # Authentication feature
│   │   ├── data/
│   │   │   ├── datasources/
│   │   │   │   └── auth_remote_datasource.dart
│   │   │   ├── models/
│   │   │   │   └── user_model.dart
│   │   │   └── repositories/
│   │   │       └── auth_repository_impl.dart
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   └── user.dart
│   │   │   ├── repositories/
│   │   │   │   └── auth_repository.dart
│   │   │   └── usecases/
│   │   │       ├── sign_in_usecase.dart
│   │   │       ├── sign_up_usecase.dart
│   │   │       └── sign_out_usecase.dart
│   │   ├── presentation/
│   │   │   ├── pages/
│   │   │   │   ├── sign_in_page.dart
│   │   │   │   ├── sign_up_page.dart
│   │   │   │   └── forgot_password_page.dart
│   │   │   ├── widgets/
│   │   │   │   ├── auth_form.dart
│   │   │   │   └── social_auth_buttons.dart
│   │   │   └── providers/
│   │   │       └── auth_provider.dart
│   │   └── providers/
│   │       └── auth_providers.dart
│   │
│   ├── projects/                   # Project management feature
│   │   ├── data/
│   │   │   ├── datasources/
│   │   │   │   └── project_remote_datasource.dart
│   │   │   ├── models/
│   │   │   │   ├── project_model.dart
│   │   │   │   └── project_member_model.dart
│   │   │   └── repositories/
│   │   │       └── project_repository_impl.dart
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   ├── project.dart
│   │   │   │   └── project_member.dart
│   │   │   ├── repositories/
│   │   │   │   └── project_repository.dart
│   │   │   └── usecases/
│   │   │       ├── create_project_usecase.dart
│   │   │       ├── get_projects_usecase.dart
│   │   │       └── invite_member_usecase.dart
│   │   ├── presentation/
│   │   │   ├── pages/
│   │   │   │   ├── projects_page.dart
│   │   │   │   ├── project_detail_page.dart
│   │   │   │   └── invite_members_page.dart
│   │   │   ├── widgets/
│   │   │   │   ├── project_card.dart
│   │   │   │   ├── project_form.dart
│   │   │   │   └── members_list.dart
│   │   │   └── providers/
│   │   │       └── project_provider.dart
│   │   └── providers/
│   │       └── project_providers.dart
│   │
│   ├── kanban/                     # Kanban board feature
│   │   ├── data/
│   │   │   ├── datasources/
│   │   │   │   └── task_remote_datasource.dart
│   │   │   ├── models/
│   │   │   │   ├── task_model.dart
│   │   │   │   └── task_comment_model.dart
│   │   │   └── repositories/
│   │   │       └── task_repository_impl.dart
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   ├── task.dart
│   │   │   │   └── task_comment.dart
│   │   │   ├── repositories/
│   │   │   │   └── task_repository.dart
│   │   │   └── usecases/
│   │   │       ├── create_task_usecase.dart
│   │   │       ├── update_task_status_usecase.dart
│   │   │       └── get_tasks_usecase.dart
│   │   ├── presentation/
│   │   │   ├── pages/
│   │   │   │   ├── kanban_board_page.dart
│   │   │   │   └── task_detail_page.dart
│   │   │   ├── widgets/
│   │   │   │   ├── kanban_column.dart
│   │   │   │   ├── task_card.dart
│   │   │   │   └── task_form.dart
│   │   │   └── providers/
│   │   │       └── kanban_provider.dart
│   │   └── providers/
│   │       └── kanban_providers.dart
│   │
│   └── notifications/              # Notifications feature
│       ├── data/
│       │   ├── datasources/
│       │   │   └── notification_remote_datasource.dart
│       │   ├── models/
│       │   │   └── notification_model.dart
│       │   └── repositories/
│       │       └── notification_repository_impl.dart
│       ├── domain/
│       │   ├── entities/
│       │   │   └── notification.dart
│       │   ├── repositories/
│       │   │   └── notification_repository.dart
│       │   └── usecases/
│       │       ├── get_notifications_usecase.dart
│       │       └── mark_as_read_usecase.dart
│       ├── presentation/
│       │   ├── pages/
│       │   │   └── notifications_page.dart
│       │   ├── widgets/
│       │   │   ├── notification_item.dart
│       │   │   └── notification_settings.dart
│       │   └── providers/
│       │       └── notification_provider.dart
│       └── providers/
│           └── notification_providers.dart
│
└── shared/                        # Shared components across features
    ├── data/
    │   ├── datasources/
    │   │   └── base_remote_datasource.dart
    │   └── repositories/
    │       └── base_repository.dart
    ├── domain/
    │   ├── entities/
    │   │   └── base_entity.dart
    │   └── usecases/
    │       └── base_usecase.dart
    ├── presentation/
    │   ├── pages/
    │   │   ├── splash_page.dart
    │   │   └── error_page.dart
    │   ├── widgets/
    │   │   ├── adaptive_layout.dart
    │   │   ├── responsive_builder.dart
    │   │   └── custom_app_bar.dart
    │   └── providers/
    │       └── shared_providers.dart
    └── providers/
        └── global_providers.dart
```

## 🏗️ Architecture Layers

### **Data Layer**
- **Datasources**: API calls, local storage, Supabase queries
- **Models**: Data transfer objects with JSON serialization
- **Repositories**: Implementation of domain repositories

### **Domain Layer**
- **Entities**: Business objects (pure Dart, no framework dependencies)
- **Repositories**: Abstract interfaces for data operations
- **Use Cases**: Business logic and use case implementations

### **Presentation Layer**
- **Pages**: Full-screen UI components
- **Widgets**: Reusable UI components
- **Providers**: Riverpod state management

## 📦 Package Dependencies

### **Core Dependencies**
- `supabase_flutter`: Backend integration
- `flutter_riverpod`: State management
- `go_router`: Navigation and routing
- `freezed`: Code generation for immutable classes
- `json_annotation`: JSON serialization

### **UI Dependencies**
- `material_symbols_icons`: Modern Material icons
- `dnd_list`: Drag and drop for Kanban board
- `fl_chart`: Charts for analytics dashboard
- `cached_network_image`: Image loading with caching
- `shimmer`: Loading animations

### **Utility Dependencies**
- `uuid`: UUID generation
- `intl`: Date formatting and localization
- `url_launcher`: Launch URLs and emails
- `image_picker`: Image selection
- `universal_html`: Web-specific utilities

## 🔄 State Management Pattern

```dart
// Feature providers structure
lib/features/feature/providers/
├── feature_provider.dart          // Main state logic
├── feature_providers.dart        // Riverpod providers
└── feature_state.dart           // State classes (freezed)
```

## 🎯 Key Principles

1. **Feature-First**: Each feature is self-contained
2. **Clean Architecture**: Clear separation of concerns
3. **Type Safety**: Full null safety and type annotations
4. **Testability**: Dependency injection and pure functions
5. **Reusability**: Shared components and utilities
6. **Web-Ready**: Responsive design and web optimizations
