import 'package:flutter/foundation.dart';
import 'data/app_configuration.dart';
import 'services/auth/secure_auth_storage.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'data/app_connection.dart';
import 'app.dart';
export 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  const api = String.fromEnvironment('API_BASE_URL');
  if (url.isEmpty || key.isEmpty || api.isEmpty) {
    runApp(const SnapExpenseApp(destination: ConnectionSetupScreen()));
    return;
  }
  try {
    final supabaseUri = Uri.parse(url);
    AppConfiguration.validate(
      supabaseUrl: url,
      publishableKey: key,
      apiBaseUrl: api,
      allowDevelopmentHttp: kDebugMode,
    );
    final storage = SecureAuthStorage(
      namespace: 'sb-${supabaseUri.host.split(".").first}-auth-token',
    );
    await Supabase.initialize(
      url: url,
      publishableKey: key,
      authOptions: FlutterAuthClientOptions(
        localStorage: storage,
        pkceAsyncStorage: storage,
        detectSessionInUriPredicate: (uri) =>
            uri.scheme == 'snapexpense' &&
            uri.host == 'auth' &&
            uri.path == '/callback',
      ),
    );
    runApp(const AppConnection(baseUrl: api));
  } catch (_) {
    runApp(
      const SnapExpenseApp(
        destination: ConnectionSetupScreen(
          message:
              'Connection setup failed. Check the public app configuration and restart the app.',
        ),
      ),
    );
  }
}
