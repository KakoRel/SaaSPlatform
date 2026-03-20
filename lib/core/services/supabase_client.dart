import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/app_constants.dart';
import '../errors/exceptions.dart';

class SupabaseClientService {
  SupabaseClientService._();

  static SupabaseClientService? _instance;
  static SupabaseClientService get instance => _instance ??= SupabaseClientService._();

  SupabaseClient? _client;
  bool _isInitialized = false;
  String? _initializationError;

  SupabaseClient get client {
    return _requireClient();
  }

  bool get isInitialized => _isInitialized;
  String? get initializationError => _initializationError;

  StreamSubscription<AuthState>? _authSubscription;

  Future<void> initialize() async {
    _isInitialized = false;
    _initializationError = null;

    try {
      await Supabase.initialize(
        url: AppConstants.supabaseUrl,
        anonKey: AppConstants.supabaseAnonKey,
        realtimeClientOptions: const RealtimeClientOptions(
          eventsPerSecond: 40,
        ),
      );

      _client = Supabase.instance.client;
      _isInitialized = true;
    } catch (e) {
      _initializationError = e.toString();
      _isInitialized = false;
      _client = null;
      throw ServerException('Failed to initialize Supabase: ${e.toString()}');
    }
  }

  // Auth methods
  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final client = _requireClient();
    try {
      final response = await client.auth.signInWithPassword(
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
    final client = _requireClient();
    try {
      final response = await client.auth.signUp(
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
    final client = _requireClient();
    try {
      await client.auth.signOut();
    } catch (e) {
      throw ServerException('Failed to sign out: ${e.toString()}');
    }
  }

  Future<void> resendConfirmationEmail(String email) async {
    final client = _requireClient();
    try {
      await client.auth.resend(
        type: OtpType.signup,
        email: email,
      );
    } on AuthException catch (e) {
      throw AuthenticationException(e.message);
    } catch (e) {
      throw ServerException('Failed to resend confirmation: ${e.toString()}');
    }
  }

  Future<void> resetPassword(String email) async {
    final client = _requireClient();
    try {
      await client.auth.resetPasswordForEmail(email);
    } on AuthException catch (e) {
      throw AuthenticationException(e.message);
    } catch (e) {
      throw ServerException('Failed to reset password: ${e.toString()}');
    }
  }

  Future<void> updatePassword(String newPassword) async {
    final client = _requireClient();
    try {
      await client.auth.updateUser(
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
    List<QueryFilter>? filters,
    List<Ordering>? orderBy,
    int? limit,
    int? offset,
  }) async {
    final client = _requireClient();
    try {
      var query = client.from(tableName).select(select ?? '*');

      if (filters != null) {
        for (final filter in filters) {
          query = query.filter(filter.column, filter.operator, filter.value);
        }
      }

      // Build the final query with transforms applied at the end
      PostgrestTransformBuilder<PostgrestList> transformed = query;

      if (orderBy != null) {
        transformed = query.order(orderBy.first.column, ascending: orderBy.first.ascending);
      }

      if (limit != null) {
        transformed = transformed.limit(limit);
      }

      if (offset != null) {
        transformed = transformed.range(offset, offset + (limit ?? 10) - 1);
      }

      final data = await transformed;
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
    List<QueryFilter>? filters,
  }) async {
    final client = _requireClient();
    try {
      var query = client.from(tableName).select(select ?? '*');

      if (filters != null) {
        for (final filter in filters) {
          query = query.filter(filter.column, filter.operator, filter.value);
        }
      }

      final data = await query.maybeSingle();
      return data != null ? fromJson(data) : null;
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
    final client = _requireClient();
    try {
      final response = await client.from(tableName).insert(data).select(select ?? '*').single();
      return fromJson(response);
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
    final client = _requireClient();
    try {
      final response = await client
          .from(tableName)
          .update(data)
          .eq('id', id)
          .select(select ?? '*')
          .single();
      return fromJson(response);
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
    final client = _requireClient();
    try {
      await client.from(tableName).delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw ServerException('Delete operation failed: ${e.message}');
    } catch (e) {
      throw ServerException('Failed to delete data: ${e.toString()}');
    }
  }

  // RPC methods (for SECURITY DEFINER helpers etc.)
  Future<dynamic> rpc({
    required String functionName,
    required Map<String, dynamic> params,
  }) async {
    final client = _requireClient();
    try {
      return await client.rpc(functionName, params: params);
    } on PostgrestException catch (e) {
      throw ServerException('RPC "$functionName" failed: ${e.message}');
    } catch (e) {
      throw ServerException('RPC "$functionName" failed: ${e.toString()}');
    }
  }

  // Realtime subscriptions
  RealtimeChannel subscribeToTable({
    required String tableName,
    required String channelId,
    required void Function(PostgresChangePayload payload) callback,
  }) {
    final client = _requireClient();
    return client.channel(channelId).onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: tableName,
      callback: callback,
    );
  }

  // Storage methods
  Future<String> uploadFileBytes({
    required String bucket,
    required String path,
    required Uint8List bytes,
    String? contentType,
  }) async {
    final client = _requireClient();
    try {
      final response = await client.storage
          .from(bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType),
          );
      return response;
    } on StorageException catch (e) {
      throw AppStorageException('Failed to upload file: ${e.message}', path);
    } catch (e) {
      throw AppStorageException('Failed to upload file: ${e.toString()}', path);
    }
  }

  String getPublicUrl({
    required String bucket,
    required String path,
  }) {
    final client = _requireClient();
    return client.storage.from(bucket).getPublicUrl(path);
  }

  Future<void> deleteFile({
    required String bucket,
    required String path,
  }) async {
    final client = _requireClient();
    try {
      await client.storage.from(bucket).remove([path]);
    } on StorageException catch (e) {
      throw AppStorageException('Failed to delete file: ${e.message}', path);
    } catch (e) {
      throw AppStorageException('Failed to delete file: ${e.toString()}', path);
    }
  }

  // Utility methods
  User? get currentUser => _isInitialized ? _client?.auth.currentUser : null;
  String? get currentUserId => currentUser?.id;
  Stream<AuthState> get authStateChanges =>
      _isInitialized && _client != null ? _client!.auth.onAuthStateChange : const Stream.empty();

  bool get isAuthenticated => currentUser != null;

  Future<bool> isTokenValid() async {
    if (!_isInitialized || _client == null) {
      return false;
    }

    try {
      final session = _client!.auth.currentSession;
      return session?.expiresAt != null &&
             DateTime.now().isBefore(
               DateTime.fromMillisecondsSinceEpoch(session!.expiresAt! * 1000),
             );
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    _authSubscription?.cancel();
    _authSubscription = null;
  }

  SupabaseClient _requireClient() {
    if (!_isInitialized || _client == null) {
      throw const ServerException('Supabase client is not initialized');
    }
    return _client!;
  }
}

class QueryFilter {
  const QueryFilter(this.column, this.operator, this.value);

  final String column;
  final String operator;
  final dynamic value;
}

class Ordering {
  const Ordering(this.column, {this.ascending = true});

  final String column;
  final bool ascending;
}
