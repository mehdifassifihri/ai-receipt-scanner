import 'package:flutter/material.dart';

const _ink = Color(0xFF252A23);

/// Navigation latérale : les destinations réutilisent les pages du shell.
class SnapSidebar extends StatelessWidget {
  const SnapSidebar({
    super.key,
    required this.onSelect,
    required this.connected,
    this.email,
    this.onLogout,
  });
  final ValueChanged<int> onSelect;
  final bool connected;
  final String? email;
  final Future<void> Function()? onLogout;

  @override
  Widget build(BuildContext context) {
    const divider = Padding(
      padding: EdgeInsets.symmetric(horizontal: 34, vertical: 17),
      child: Divider(height: 1, color: Color(0xFFD8D6CE)),
    );
    return Drawer(
      width: (MediaQuery.sizeOf(context).width * .82).clamp(260.0, 380.0),
      backgroundColor: const Color(0xFFF2F0EA),
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(top: 12, bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(34, 8, 16, 24),
              child: Row(
                children: [
                  const Icon(
                    Icons.document_scanner_outlined,
                    color: _ink,
                    size: 25,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'snapexpense',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.7,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close menu',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 21),
                  ),
                ],
              ),
            ),
            // Une carte éditoriale reprend l’esprit de la bannière de référence,
            // avec une action existante plutôt qu’un lien promotionnel fictif.
            Material(
              color: const Color(0xFFDDE8C6),
              child: InkWell(
                onTap: () => onSelect(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 34,
                    vertical: 27,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.auto_awesome_outlined, size: 23),
                          Spacer(),
                          Icon(Icons.north_east, size: 25),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'A little clarity.',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'Your spending, explained.\nAsk Snap a question.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.6,
                          color: _ink.withValues(alpha: .75),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 17),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                leading: const Icon(Icons.help_outline_rounded, size: 25),
                title: const Text(
                  'Support',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w400),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                children: const [
                  Text(
                    'To refresh your expenses, pull down on Home. Tap a saved expense to review its details. Ask Snap can help you understand spending, but cannot edit your records.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.8,
                      color: Color(0xFF6E7169),
                    ),
                  ),
                ],
              ),
            ),
            divider,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                leading: const Icon(Icons.shield_outlined, size: 25),
                title: const Text(
                  'Your account',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w400),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  Text(
                    connected ? (email ?? 'Signed in') : 'Preview mode',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6E7169),
                    ),
                  ),
                ],
              ),
            ),
            if (connected) _LogoutButton(onLogout: onLogout),
            const Padding(
              padding: EdgeInsets.fromLTRB(36, 28, 28, 8),
              child: Text(
                'SMALL SCANS. SMARTER SPENDING.',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.3,
                  color: Color(0xFF87897E),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Le verrou local empêche plusieurs déconnexions simultanées, sans modifier
/// le fournisseur d’authentification ou la navigation décidée par AppConnection.
class _LogoutButton extends StatefulWidget {
  const _LogoutButton({required this.onLogout});
  final Future<void> Function()? onLogout;
  @override
  State<_LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends State<_LogoutButton> {
  bool _busy = false;
  Future<void> _logout() async {
    if (_busy || widget.onLogout == null) return;
    setState(() => _busy = true);
    try {
      await widget.onLogout!();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not log out. Please retry.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
    child: ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: const Icon(Icons.logout_rounded, size: 25, color: _ink),
      title: const Text(
        'Log out',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w400),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      enabled: !_busy && widget.onLogout != null,
      onTap: _logout,
    ),
  );
}
