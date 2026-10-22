import 'dart:convert';

/// Seules des valeurs publiques peuvent être embarquées dans l’application.
class AppConfiguration {
  static void validate({
    required String supabaseUrl,
    required String publishableKey,
    required String apiBaseUrl,
    required bool allowDevelopmentHttp,
  }) {
    final supabase = Uri.parse(supabaseUrl);
    final api = Uri.parse(apiBaseUrl);
    bool endpoint(Uri uri) =>
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment;
    if (!endpoint(supabase) ||
        supabase.scheme != 'https' ||
        !endpoint(api) ||
        !(api.scheme == 'https' ||
            (allowDevelopmentHttp && api.scheme == 'http')) ||
        !isPublicKey(publishableKey)) {
      throw const FormatException('Invalid public app configuration');
    }
  }

  static bool isPublicKey(String key) {
    if (key.startsWith('sb_publishable_')) return true;
    try {
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(key.split('.')[1]))),
      );
      return claims is Map && claims['role'] == 'anon';
    } catch (_) {
      return false;
    }
  }
}
