import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import '../domain/entities/user.dart';
import '../../../core/services/supabase_client.dart';
import '../../../core/errors/exceptions.dart';

// Auth state (renamed to avoid conflict with Supabase AuthState)
class AppAuthState {
  const AppAuthState({
    this.user,
    this.isLoading = false,
    this.error,
    this.isAuthenticated = false,
    this.pendingEmailConfirmationEmail,
  });

  final AppUser? user;
  final bool isLoading;
  final String? error;
  final bool isAuthenticated;
  final String? pendingEmailConfirmationEmail;

  AppAuthState copyWith({
    AppUser? user,
    bool? isLoading,
    String? error,
    bool? isAuthenticated,
    bool clearUser = false,
    bool clearError = false,
    String? pendingEmailConfirmationEmail,
    bool clearPendingEmailConfirmationEmail = false,
  }) {
    return AppAuthState(
      user: clearUser ? null : (user ?? this.user),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      pendingEmailConfirmationEmail: clearPendingEmailConfirmationEmail
          ? null
          : (pendingEmailConfirmationEmail ?? this.pendingEmailConfirmationEmail),
    );
  }
}

// Auth provider
class AuthNotifier extends StateNotifier<AppAuthState> {
  AuthNotifier(this._supabaseService) : super(const AppAuthState()) {
    _initializeAuth();
  }

  final SupabaseClientService _supabaseService;
  StreamSubscription<supa.AuthState>? _authSubscription;

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

  void _handleAuthStateChange(supa.AuthState authState) {
    final session = authState.session;

    if (session?.user != null) {
      _getUserDetails(session!.user.id).then((user) {
        state = state.copyWith(
          user: user,
          isAuthenticated: true,
          isLoading: false,
          clearError: true,
          clearPendingEmailConfirmationEmail: true,
        );
      }).catchError((error) {
        state = state.copyWith(
          isLoading: false,
          error: error.toString(),
          isAuthenticated: false,
        );
      });
    } else {
      state = state.copyWith(
        clearUser: true,
        isAuthenticated: false,
        isLoading: false,
        clearError: true,
      );
    }
  }

  Future<AppUser> _getUserDetails(String userId) async {
    try {
      final userData = await _supabaseService.fetchSingle<Map<String, dynamic>>(
        tableName: 'users',
        fromJson: (json) => json,
        filters: [
          QueryFilter('id', 'eq', userId),
        ],
      );

      if (userData == null) {
        throw const AuthenticationException('User not found');
      }

      final supaUser = _supabaseService.currentUser;
      return AppUser.fromJson(userData).copyWith(
        isEmailConfirmed: supaUser?.emailConfirmedAt != null,
      );
    } catch (e) {
      throw AuthenticationException('Failed to get user details: ${e.toString()}');
    }
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      await _supabaseService.signInWithEmail(
        email: email,
        password: password,
      );
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
    bool showLoading = true,
  }) async {
    if (showLoading) {
      state = state.copyWith(isLoading: true, clearError: true);
    }

    try {
      await _supabaseService.signUpWithEmail(
        email: email,
        password: password,
        fullName: fullName,
      );
      
      // Reset loading state on success
      if (showLoading) {
        state = state.copyWith(isLoading: false);
      }

      // Supabase creates the user but requires email confirmation.
      // Even if session is not available yet, keep the UI on a confirmation screen.
      state = state.copyWith(
        pendingEmailConfirmationEmail: email.trim(),
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      await _supabaseService.signOut();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> resetPassword(String email) async {
    state = state.copyWith(isLoading: true, clearError: true);

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
    state = state.copyWith(isLoading: true, clearError: true);

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
    state = state.copyWith(isLoading: true, clearError: true);

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
        user: AppUser.fromJson(updatedUser).copyWith(
          isEmailConfirmed: _supabaseService.currentUser?.emailConfirmedAt != null,
        ),
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> resendConfirmationEmail([String? email]) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final targetEmail = email ?? state.user?.email;
      if (targetEmail == null) {
        throw const AuthenticationException('Email not found');
      }
      await _supabaseService.resendConfirmationEmail(targetEmail);
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> uploadAvatar(List<int> bytes, String extension) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final userId = _supabaseService.currentUserId;
      if (userId == null) throw const AuthenticationException('User not authenticated');

      final fileName = '$userId.${DateTime.now().millisecondsSinceEpoch}.$extension';
      final path = 'avatars/$fileName';

      await _supabaseService.uploadFileBytes(
        bucket: 'avatars',
        path: path,
        bytes: Uint8List.fromList(bytes),
        contentType: 'image/$extension',
      );

      final avatarUrl = _supabaseService.getPublicUrl(bucket: 'avatars', path: path);
      await updateProfile(avatarUrl: avatarUrl);
      
      // Reset loading state on success
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  void clearError() {
    state = state.copyWith(clearError: true);
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

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AppAuthState>((ref) {
  final supabaseService = ref.watch(authServiceProvider);
  return AuthNotifier(supabaseService);
});

final currentUserProvider = Provider<AppUser?>((ref) {
  return ref.watch(authNotifierProvider).user;
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authNotifierProvider).isAuthenticated;
});

// Auth guards
final authGuardProvider = Provider<bool>((ref) {
  final isAuthenticated = ref.watch(isAuthenticatedProvider);
  final isLoading = ref.watch(authNotifierProvider.select((s) => s.isLoading));
  return !isLoading && isAuthenticated;
});

final unauthenticatedGuardProvider = Provider<bool>((ref) {
  final isAuthenticated = ref.watch(isAuthenticatedProvider);
  final isLoading = ref.watch(authNotifierProvider.select((s) => s.isLoading));
  return !isLoading && !isAuthenticated;
});
