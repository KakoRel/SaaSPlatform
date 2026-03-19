import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/user.dart';
import '../../../core/services/supabase_client.dart';
import '../../../core/errors/exceptions.dart';

// Auth state
@freezed
class AuthState with _$AuthState {
  const factory AuthState({
    User? user,
    @Default(false) bool isLoading,
    String? error,
    @Default(false) bool isAuthenticated,
  }) = _AuthState;
}

// Auth provider
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._supabaseService) : super(const AuthState()) {
    _initializeAuth();
  }

  final SupabaseClientService _supabaseService;
  StreamSubscription<AuthState>? _authSubscription;

  void _initializeAuth() {
    state = state.copyWith(isLoading: true);

    // Check current session
    _checkCurrentSession();

    // Listen to auth state changes
    _authSubscription = _supabaseService.authStateChanges.listen(
      (authState) {
        _handleAuthStateChange(authState);
      },
      onError: (error) {
        state = state.copyWith(
          isLoading: false,
          error: error.toString(),
        );
      },
    );
  }

  Future<void> _checkCurrentSession() async {
    try {
      final currentUser = _supabaseService.currentUser;
      if (currentUser != null) {
        final user = await _getUserDetails(currentUser.id);
        state = state.copyWith(
          user: user,
          isAuthenticated: true,
          isLoading: false,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: false,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        isAuthenticated: false,
      );
    }
  }

  void _handleAuthStateChange(AuthState authState) {
    final session = authState.session;
    
    if (session?.user != null) {
      // User signed in
      _getUserDetails(session!.user.id).then((user) {
        state = state.copyWith(
          user: user,
          isAuthenticated: true,
          isLoading: false,
          error: null,
        );
      }).catchError((error) {
        state = state.copyWith(
          isLoading: false,
          error: error.toString(),
          isAuthenticated: false,
        );
      });
    } else {
      // User signed out
      state = state.copyWith(
        user: null,
        isAuthenticated: false,
        isLoading: false,
        error: null,
      );
    }
  }

  Future<User> _getUserDetails(String userId) async {
    try {
      final userData = await _supabaseService.fetchSingle<Map<String, dynamic>>(
        tableName: 'users',
        fromJson: (json) => json,
        filters: [
          Filter('id', 'eq', userId),
        ],
      );

      if (userData == null) {
        throw const AuthenticationException('User not found');
      }

      return User.fromJson(userData);
    } catch (e) {
      throw AuthenticationException('Failed to get user details: ${e.toString()}');
    }
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await _supabaseService.signInWithEmail(
        email: email,
        password: password,
      );

      // Auth state change will be handled by the stream listener
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> signUpWithEmail({
    required String email,
    required String password,
    String? fullName,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await _supabaseService.signUpWithEmail(
        email: email,
        password: password,
        fullName: fullName,
      );

      // Note: User will need to confirm email if enabled in Supabase
      // Auth state change will be handled by the stream listener
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await _supabaseService.signOut();
      // Auth state change will be handled by the stream listener
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> resetPassword(String email) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await _supabaseService.resetPassword(email);
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> updatePassword(String newPassword) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await _supabaseService.updatePassword(newPassword);
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> updateProfile({
    String? fullName,
    String? avatarUrl,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final userId = _supabaseService.currentUserId;
      if (userId == null) {
        throw const AuthenticationException('User not authenticated');
      }

      final updateData = <String, dynamic>{};
      if (fullName != null) updateData['full_name'] = fullName;
      if (avatarUrl != null) updateData['avatar_url'] = avatarUrl;

      if (updateData.isEmpty) {
        state = state.copyWith(isLoading: false);
        return;
      }

      final updatedUser = await _supabaseService.update<Map<String, dynamic>>(
        tableName: 'users',
        id: userId,
        data: updateData,
        fromJson: (json) => json,
      );

      state = state.copyWith(
        user: User.fromJson(updatedUser),
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

// Providers
final authServiceProvider = Provider<SupabaseClientService>((ref) {
  return SupabaseClientService.instance;
});

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final supabaseService = ref.watch(authServiceProvider);
  return AuthNotifier(supabaseService);
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authProvider).user;
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isAuthenticated;
});

// Auth guards
final authGuardProvider = Provider<bool>((ref) {
  final isAuthenticated = ref.watch(isAuthenticatedProvider);
  final isLoading = ref.watch(authProvider.select((state) => state.isLoading));
  
  // Return true only when we know the auth state (not loading)
  return !isLoading && isAuthenticated;
});

final unauthenticatedGuardProvider = Provider<bool>((ref) {
  final isAuthenticated = ref.watch(isAuthenticatedProvider);
  final isLoading = ref.watch(authProvider.select((state) => state.isLoading));
  
  // Return true only when we know the user is not authenticated (not loading)
  return !isLoading && !isAuthenticated;
});
