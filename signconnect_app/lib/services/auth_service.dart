import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'socket_service.dart';

class UserAccount {
  String name;
  String email;
  AppRole role;
  String? phone;
  String? location;
  String? bio;
  double micSensitivity;
  String vocabularyFocus;
  bool ttsEnabled;

  UserAccount({
    required this.name,
    required this.email,
    this.role = AppRole.deaf,
    this.phone,
    this.location,
    this.bio,
    this.micSensitivity = 0.75,
    this.vocabularyFocus = "Daily",
    this.ttsEnabled = true,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'role': role == AppRole.deaf ? 'deaf' : 'hearing',
        'phone': phone,
        'location': location,
        'bio': bio,
        'micSensitivity': micSensitivity,
        'vocabularyFocus': vocabularyFocus,
        'ttsEnabled': ttsEnabled,
      };

  factory UserAccount.fromJson(Map<String, dynamic> json) => UserAccount(
        name: (json['name'] as String?) ?? 'User',
        email: (json['email'] as String?) ?? '',
        role: json['role'] == 'hearing' ? AppRole.hearing : AppRole.deaf,
        phone: json['phone'] as String?,
        location: json['location'] as String?,
        bio: json['bio'] as String?,
        micSensitivity: (json['micSensitivity'] as num?)?.toDouble() ?? 0.75,
        vocabularyFocus: (json['vocabularyFocus'] as String?) ?? 'Daily',
        ttsEnabled: (json['ttsEnabled'] as bool?) ?? true,
      );
}

class AuthResult {
  final bool success;
  final String message;
  final UserAccount? account;
  const AuthResult(this.success, this.message, [this.account]);
}

/// Local multi-user email accounts persisted on-device via SharedPreferences.
/// Anyone can sign up with any email — no admin approval needed.
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static const _accountsKey = 'signconnect_accounts_v1';
  static const _sessionKey = 'signconnect_session_v1';

  final Map<String, Map<String, dynamic>> _accounts = {};
  UserAccount? _current;
  bool _loaded = false;

  UserAccount? get currentAccount => _current;
  bool get isLoggedIn => _current != null;

  String _hash(String password, String email) =>
      sha256.convert(utf8.encode('$email::${password.trim()}::signconnect-salt')).toString();

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_accountsKey);
    if (raw != null) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded.forEach((k, v) => _accounts[k.toLowerCase()] = v);
    }
    final session = prefs.getString(_sessionKey);
    if (session != null && _accounts.containsKey(session.toLowerCase())) {
      _current = UserAccount.fromJson(
        Map<String, dynamic>.from(_accounts[session.toLowerCase()]!['profile']),
      );
    }
    _loaded = true;
  }

  Future<AuthResult> restoreSession() async {
    await _ensureLoaded();
    if (_current != null) {
      return AuthResult(true, 'Session restored', _current);
    }
    return const AuthResult(false, 'No active session');
  }

  Future<bool> emailExists(String email) async {
    await _ensureLoaded();
    return _accounts.containsKey(email.trim().toLowerCase());
  }

  Future<AuthResult> signUp({
    required String name,
    required String email,
    required String password,
    AppRole role = AppRole.deaf,
  }) async {
    await _ensureLoaded();
    final key = email.trim().toLowerCase();
    if (_accounts.containsKey(key)) {
      return const AuthResult(false, 'An account with this email already exists. Please sign in.');
    }
    final account = UserAccount(name: name.trim(), email: email.trim(), role: role);
    _accounts[key] = {
      'hash': _hash(password, key),
      'profile': account.toJson(),
    };
    await _persist();
    await _startSession(key);
    return AuthResult(true, 'Welcome to SignConnect, ${account.name}!', account);
  }

  Future<AuthResult> signIn({required String email, required String password}) async {
    await _ensureLoaded();
    final key = email.trim().toLowerCase();
    final record = _accounts[key];
    if (record == null) {
      return const AuthResult(false, 'No account found for this email. Create one first.');
    }
    if (record['hash'] != _hash(password, key)) {
      return const AuthResult(false, 'Incorrect password. Please try again.');
    }
    final account = UserAccount.fromJson(Map<String, dynamic>.from(record['profile']));
    await _startSession(key);
    return AuthResult(true, 'Signed in as ${account.name}', account);
  }

  Future<AuthResult> signInGuest(String name, AppRole role) async {
    await _ensureLoaded();
    final guest = UserAccount(name: name.trim().isEmpty ? 'Guest' : name.trim(), email: 'guest@local', role: role);
    _current = guest;
    final key = guest.email.toLowerCase();
    _accounts[key] = {'profile': guest.toJson()};
    await _persist();
    await _startSession(key);
    return AuthResult(true, 'Continuing as guest', guest);
  }

  /// Editable profile: persists any subset of fields for the signed-in user.
  Future<UserAccount?> updateProfile({
    String? name,
    String? email,
    String? phone,
    String? location,
    String? bio,
    AppRole? role,
    double? micSensitivity,
    String? vocabularyFocus,
    bool? ttsEnabled,
  }) async {
    await _ensureLoaded();
    final current = _current;
    if (current == null) return null;

    if (name != null && name.trim().isNotEmpty) current.name = name.trim();
    if (phone != null) current.phone = phone.trim();
    if (location != null) current.location = location.trim();
    if (bio != null) current.bio = bio.trim();
    if (role != null) current.role = role;
    if (micSensitivity != null) current.micSensitivity = micSensitivity;
    if (vocabularyFocus != null) current.vocabularyFocus = vocabularyFocus;
    if (ttsEnabled != null) current.ttsEnabled = ttsEnabled;

    // Email change is allowed when the new address is not taken.
    if (email != null && email.trim().isNotEmpty) {
      final newKey = email.trim().toLowerCase();
      final oldKey = current.email.toLowerCase();
      if (newKey != oldKey && !_accounts.containsKey(newKey)) {
        final record = _accounts.remove(oldKey);
        if (record != null) {
          current.email = email.trim();
          record['profile'] = current.toJson();
          _accounts[newKey] = record;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_sessionKey, newKey);
        }
      }
    }

    await _saveProfile(current);
    return current;
  }

  Future<void> changePassword(String newPassword) async {
    await _ensureLoaded();
    final current = _current;
    if (current == null) return;
    final key = current.email.toLowerCase();
    final record = _accounts[key];
    if (record == null) return;
    record['hash'] = _hash(newPassword, key);
    await _persist();
  }

  Future<void> deleteAccount() async {
    await _ensureLoaded();
    final current = _current;
    if (current == null) return;
    _accounts.remove(current.email.toLowerCase());
    _current = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    await _persist();
  }

  Future<void> signOut() async {
    _current = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  Future<void> _startSession(String key) async {
    _current = UserAccount.fromJson(Map<String, dynamic>.from(_accounts[key]!['profile']));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, key);
  }

  Future<void> _saveProfile(UserAccount account) async {
    final key = account.email.toLowerCase();
    final record = _accounts[key];
    if (record != null) {
      record['profile'] = account.toJson();
      await _persist();
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_accountsKey, jsonEncode(_accounts));
    } catch (e) {
      debugPrint('Auth persist error: $e');
    }
  }
}
