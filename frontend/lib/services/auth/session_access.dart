import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/backend_api.dart';

/// Un client API appartient à un compte précis, même pendant un refresh.
class SessionAccess {
  SessionAccess(this.auth, this.owner);
  final GoTrueClient auth;
  final String owner;

  Future<String> token() async {
    var session = auth.currentSession;
    if (session == null || session.user.id != owner) throw _signedOut;
    try {
      // Le SDK déduplique déjà les refresh simultanés et invalide les jetons révoqués.
      if (session.isExpired) await auth.refreshSession();
    } on AuthException {
      throw const ApiException(
        'Your session could not be renewed. Please sign in again.',
        status: 401,
      );
    }
    // Relire la source de vérité, pas la réponse potentiellement ancienne du refresh.
    session = auth.currentSession;
    if (session == null || session.user.id != owner || session.isExpired) {
      throw _signedOut;
    }
    return session.accessToken;
  }

  static const _signedOut = ApiException('Please sign in again.', status: 401);
}
