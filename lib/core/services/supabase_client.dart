import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_html/html.dart' as html;

import '../constants/app_constants.dart';
import '../errors/exceptions.dart';

class SupabaseClientService {
  SupabaseClientService._();

  static SupabaseClientService? _instance;
  static SupabaseClientService get instance => _instance ??= SupabaseClientService._();

  late SupabaseClient _client;
  SupabaseClient get client => _client;

  StreamSubscription<AuthState>? _authSubscription;

  Future<void> initialize() async {
    try {
      await Supabase.initialize(
        url: AppConstants.supabaseUrl,
        anonKey: AppConstants.supabaseAnonKey,
        authOptions: const AuthOptions(
          autoRefreshToken: true,
          persistSession: true,
          detectSessionInUrl: true,
        ),
        realtimeClientOptions: const RealtimeClientOptions(
          eventsPerSecond: 40,
        ),
        storageOptions: const StorageClientOptions(
          retryAttempts: 3,
        ),
      );

      _client = Supabase.instance.client;
      
      // Handle deep links for web auth
      if (AppConstants.isWeb) {
        _handleWebAuth();
      }
    } catch (e) {
      throw ServerException('Failed to initialize Supabase: ${e.toString()}');
    }
  }

  void _handleWebAuth() {
    if (!AppConstants.isWeb) return;

    // Check for OAuth callback
    final uri = Uri.base;
    final fragments = uri.fragment.split('&');
    
    for (final fragment in fragments) {
      final parts = fragment.split('=');
      if (parts.length == 2 && parts[0] == 'access_token') {
        _client.auth.getSessionFromUrl(Uri.base);
        break;
      }
    }
  }

  // Auth methods
  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response;
    } on AuthException catch (e) {
      throw AuthenticationException(e.message);
    } catch (e) {
      throw ServerException('Failed to sign in: ${e.toString()}');
    }
  }

  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    String? fullName,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: fullName != null ? {'full_name': fullName} : null,
      );
      return response;
    } on AuthException catch (e) {
      throw AuthenticationException(e.message);
    } catch (e) {
      throw ServerException('Failed to sign up: ${e.toString()}');
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      throw ServerException('Failed to sign out: ${e.toString()}');
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
    } on AuthException catch (e) {
      throw AuthenticationException(e.message);
    } catch (e) {
      throw ServerException('Failed to reset password: ${e.toString()}');
    }
  }

  Future<void> updatePassword(String newPassword) async {
    try {
      await _client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
    } on AuthException catch (e) {
      throw AuthenticationException(e.message);
    } catch (e) {
      throw ServerException('Failed to update password: ${e.toString()}');
    }
  }

  // Database methods
  Future<List<T>> fetchList<T>({
    required String tableName,
    required T Function(Map<String, dynamic>) fromJson,
    String? select,
    List<Filter>? filters,
    List<Ordering>? orderBy,
    int? limit,
    int? offset,
  }) async {
    try {
      var query = _client.from(tableName).select(select ?? '*');

      if (filters != null) {
        for (final filter in filters) {
          query = query.filter(filter.column, filter.operator, filter.value);
        }
      }

      if (orderBy != null) {
        query = query.order(orderBy.first.column, ascending: orderBy.first.ascending);
      }

      if (limit != null) {
        query = query.limit(limit);
      }

      if (offset != null) {
        query = query.range(offset, offset + (limit ?? 10) - 1);
      }

      final data = await query;
      return (data as List).map((item) => fromJson(item as Map<String, dynamic>)).toList();
    } on PostgrestException catch (e) {
      throw ServerException('Database query failed: ${e.message}');
    } catch (e) {
      throw ServerException('Failed to fetch data: ${e.toString()}');
    }
  }

  Future<T?> fetchSingle<T>({
    required String tableName,
    required T Function(Map<String, dynamic>) fromJson,
    String? select,
    List<Filter>? filters,
  }) async {
    try {
      var query = _client.from(tableName).select(select ?? '*');

      if (filters != null) {
        for (final filter in filters) {
          query = query.filter(filter.column, filter.operator, filter.value);
        }
      }

      final data = await query.maybeSingle();
      return data != null ? fromJson(data as Map<String, dynamic>) : null;
    } on PostgrestException catch (e) {
      throw ServerException('Database query failed: ${e.message}');
    } catch (e) {
      throw ServerException('Failed to fetch data: ${e.toString()}');
    }
  }

  Future<T> insert<T>({
    required String tableName,
    required Map<String, dynamic> data,
    required T Function(Map<String, dynamic>) fromJson,
    String? select,
  }) async {
    try {
      final response = await _client.from(tableName).insert(data).select(select ?? '*').single();
      return fromJson(response as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw ServerException('Insert operation failed: ${e.message}');
    } catch (e) {
      throw ServerException('Failed to insert data: ${e.toString()}');
    }
  }

  Future<T> update<T>({
    required String tableName,
    required String id,
    required Map<String, dynamic> data,
    required T Function(Map<String, dynamic>) fromJson,
    String? select,
  }) async {
    try {
      final response = await _client
          .from(tableName)
          .update(data)
          .eq('id', id)
          .select(select ?? '*')
          .single();
      return fromJson(response as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw ServerException('Update operation failed: ${e.message}');
    } catch (e) {
      throw ServerException('Failed to update data: ${e.toString()}');
    }
  }

  Future<void> delete({
    required String tableName,
    required String id,
  }) async {
    try {
      await _client.from(tableName).delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw ServerException('Delete operation failed: ${e.message}');
    } catch (e) {
      throw ServerException('Failed to delete data: ${e.toString()}');
    }
  }

  // Realtime subscriptions
  RealtimeChannel subscribeToTable({
    required String tableName,
    required String channelId,
    required Function(RealtimePayload) callback,
  }) {
    return _client.channel(channelId).onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: tableName,
      callback: callback,
    );
  }

  // Storage methods
  Future<String> uploadFile({
    required String bucket,
    required String path,
    required File file,
    Map<String, String>? metadata,
  }) async {
    try {
      final fileBytes = await file.readAsBytes();
      final response = await _client.storage
          .from(bucket)
          .uploadBinary(path, fileBytes, fileOptions: FileOptions(metadata: metadata));
      return response;
    } on StorageException catch (e) {
      throw StorageException('Failed to upload file: ${e.message}', path);
    } catch (e) {
      throw StorageException('Failed to upload file: ${e.toString()}', path);
    }
  }

  Future<String> uploadFileWeb({
    required String bucket,
    required String path,
    required List<int> bytes,
    String? contentType,
    Map<String, String>? metadata,
  }) async {
    try {
      final response = await _client.storage
          .from(bucket)
          .uploadBinary(path, bytes, fileOptions: FileOptions(
        contentType: contentType,
        metadata: metadata,
      ));
      return response;
    } on StorageException catch (e) {
      throw StorageException('Failed to upload file: ${e.message}', path);
    } catch (e) {
      throw StorageException('Failed to upload file: ${e.toString()}', path);
    }
  }

  Future<String> getPublicUrl({
    required String bucket,
    required String path,
  }) async {
    try {
      return _client.storage.from(bucket).getPublicUrl(path);
    } catch (e) {
      throw StorageException('Failed to get public URL: ${e.toString()}', path);
    }
  }

  Future<void> deleteFile({
    required String bucket,
    required String path,
  }) async {
    try {
      await _client.storage.from(bucket).remove([path]);
    } catch (e) {
      throw StorageException('Failed to delete file: ${e.toString()}', path);
    }
  }

  // Utility methods
  User? get currentUser => _client.auth.currentUser;
  String? get currentUserId => _client.auth.currentUser?.id;
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  bool get isAuthenticated => currentUser != null;

  Future<bool> isTokenValid() async {
    try {
      final session = _client.auth.currentSession;
      return session?.expiresAt != null && 
             DateTime.now().isBefore(DateTime.fromMillisecondsSinceEpoch(session!.expiresAt! * 1000));
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    _authSubscription?.cancel();
  }
}

class Filter {
  const Filter(this.column, this.operator, this.value);

  final String column;
  final String operator;
  final dynamic value;
}

class Ordering {
  const Ordering(this.column, {this.ascending = true});

  final String column;
  final bool ascending;
}
