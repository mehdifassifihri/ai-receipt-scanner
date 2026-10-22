import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Adaptateurs officiels Supabase : la session reste gérée par le SDK.
/// Migre les anciennes préférences seulement après une écriture sécurisée réussie.
class SecureAuthStorage extends LocalStorage implements GotrueAsyncStorage {
  SecureAuthStorage({
    required this.namespace,
    FlutterSecureStorage? storage,
    LocalStorage? legacySession,
    GotrueAsyncStorage? legacyPkce,
  }) : _storage =
           storage ??
           const FlutterSecureStorage(
             iOptions: IOSOptions(
               accessibility: KeychainAccessibility.first_unlock_this_device,
             ),
           ),
       _legacySession =
           legacySession ??
           SharedPreferencesLocalStorage(persistSessionKey: namespace),
       _legacyPkce = legacyPkce ?? SharedPreferencesGotrueAsyncStorage();

  final String namespace;
  final FlutterSecureStorage _storage;
  final LocalStorage _legacySession;
  final GotrueAsyncStorage _legacyPkce;
  Future<void> _pending = Future.value();
  Future<void>? _initialization;
  String get _sessionKey => '$namespace.secure-session';
  String _pkceKey(String key) => '$namespace.pkce.$key';

  // Le SDK persiste les événements sans attendre leur écriture. Cette file
  // conserve leur ordre : une sauvegarde lente ne doit pas annuler un logout.
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<void> initialize() => _initialization ??= _serial(() async {
    await _legacySession.initialize();
    final current = await _storage.read(key: _sessionKey);
    if (current == null) {
      final previous = await _legacySession.accessToken();
      if (previous != null) {
        await _storage.write(key: _sessionKey, value: previous);
      }
    }
    // En cas d’échec d’écriture, l’ancienne session reste récupérable.
    await _legacySession.removePersistedSession();
  });

  @override
  Future<String?> accessToken() =>
      _serial(() => _storage.read(key: _sessionKey));
  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;
  @override
  Future<void> persistSession(String persistSessionString) => _serial(() async {
    await _storage.write(key: _sessionKey, value: persistSessionString);
    await _legacySession.removePersistedSession();
  });
  @override
  Future<void> removePersistedSession() => _serial(() async {
    await _storage.delete(key: _sessionKey);
    await _legacySession.removePersistedSession();
  });

  @override
  Future<String?> getItem({required String key}) => _serial(() async {
    final current = await _storage.read(key: _pkceKey(key));
    final previous = current == null
        ? await _legacyPkce.getItem(key: key)
        : null;
    if (previous != null) {
      await _storage.write(key: _pkceKey(key), value: previous);
    }
    await _legacyPkce.removeItem(key: key);
    return current ?? previous;
  });
  @override
  Future<void> setItem({required String key, required String value}) =>
      _serial(() async {
        await _storage.write(key: _pkceKey(key), value: value);
        await _legacyPkce.removeItem(key: key);
      });
  @override
  Future<void> removeItem({required String key}) => _serial(() async {
    await _storage.delete(key: _pkceKey(key));
    await _legacyPkce.removeItem(key: key);
  });
}
