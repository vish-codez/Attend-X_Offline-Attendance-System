import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';

const _storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);
const _userKey = 'current_user';

class AuthNotifier extends AsyncNotifier<UserModel?> {
  @override
  Future<UserModel?> build() async {
    // Init ApiService (reads base_url + token from storage once)
    await ApiService.instance.init();
    // Restore saved user session
    final stored = await _storage.read(key: _userKey);
    if (stored != null) {
      try {
        return UserModel.fromJson(jsonDecode(stored));
      } catch (_) {}
    }
    return null;
  }

  Future<void> login(String username, String password) async {
    state = const AsyncLoading();
    try {
      final data = await ApiService.instance.login(username, password);
      final user = UserModel.fromJson(data);
      await ApiService.instance.saveToken(user.token);
      await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
      state = AsyncData(user);
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
      rethrow;
    }
  }

  Future<void> logout() async {
    await ApiService.instance.clearToken();
    await _storage.delete(key: _userKey);
    state = const AsyncData(null);
  }
}

final authProvider =
AsyncNotifierProvider<AuthNotifier, UserModel?>(AuthNotifier.new);

final currentUserProvider = Provider<UserModel?>((ref) {
  return ref.watch(authProvider).value;
});