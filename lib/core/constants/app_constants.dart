import 'package:flutter/foundation.dart';

class AppConstants {
  AppConstants._();

  static const String appName = 'TaskFlow';
  static const String appVersion = '1.0.0';

  // Supabase configuration
  static const String supabaseUrl = 'YOUR_SUPABASE_URL';
  static const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';

  // Storage
  static const String avatarBucket = 'avatars';
  static const String attachmentsBucket = 'attachments';

  // Pagination
  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;

  // Task limits
  static const int maxTaskTitleLength = 255;
  static const int maxTaskDescriptionLength = 2000;
  static const int maxCommentLength = 1000;

  // File sizes (in bytes)
  static const int maxAvatarSize = 2 * 1024 * 1024; // 2MB
  static const int maxAttachmentSize = 10 * 1024 * 1024; // 10MB

  // Supported image formats
  static const List<String> supportedImageFormats = [
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
  ];

  // Supported attachment formats
  static const List<String> supportedAttachmentFormats = [
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'txt',
    'zip',
    'rar',
  ];

  // Web specific
  static bool get isWeb => kIsWeb;
  static const String webStorageKey = 'taskflow_auth_token';
}
