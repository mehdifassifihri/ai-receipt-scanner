import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'registration_screen.dart';
import 'password_recovery_screen.dart';

const _ink = Color(0xFF111111);
const _fieldFill = Color(0xFFF3F3F3);
const _hint = Color(0xFF8C8C8C);
const _muted = Color(0xFF6E6E6E);

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, this.register = false, this.initialMessage});
  final bool register;
  final String? initialMessage;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _form = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool get _signup => widget.register;
  bool _busy = false, _obscure = true;
  late String? _message = widget.initialMessage;

  @override
  void didUpdateWidget(covariant AccountScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialMessage != widget.initialMessage) {
      _message = widget.initialMessage;
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(GoTrueClient auth) action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action(Supabase.instance.client.auth);
    } on AuthException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Unable to connect. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    await _run((auth) async {
      if (_signup) {
        final first = _firstName.text.trim();
        final last = _lastName.text.trim();
        final result = await auth.signUp(
          emailRedirectTo: passwordRecoveryRedirect,
          email: _email.text.trim(),
          password: _password.text,
          data: {
            'first_name': first,
            'last_name': last,
            'full_name': [first, last].where((s) => s.isNotEmpty).join(' '),
          },
        );
        if (mounted && result.session == null) {
          setState(
            () => _message =
                'Check your email to confirm your account, then sign in.',
          );
        }
      } else {
        await auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    });
  }

  Future<void> _google() async {
    if (_busy) return;
    await _run(
      (auth) => auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: passwordRecoveryRedirect,
      ),
    );
  }

  void _switchMode() {
    if (_signup) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const RegistrationScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const headerHeight = 250.0;
    const overlap = 34.0;
    final insets = MediaQuery.paddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SingleChildScrollView(
          // Clamped so pulling down never reveals white above the header.
          physics: const ClampingScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: headerHeight + insets.top,
                child: _Header(
                  title: _signup ? 'Create an\naccount' : 'Welcome\nback',
                  topInset: insets.top,
                ),
              ),
              Padding(
                padding: EdgeInsets.only(
                  top: headerHeight + insets.top - overlap,
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(40),
                    ),
                  ),
                  padding: EdgeInsets.fromLTRB(28, 34, 28, 30 + insets.bottom),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: _formBody(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _formBody(BuildContext context) => Form(
    key: _form,
    child: AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GoogleButton(onPressed: _busy ? null : _google),
          const SizedBox(height: 18),
          const Text(
            'or',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 13.5),
          ),
          const SizedBox(height: 18),
          if (_signup) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _PillField(
                    controller: _firstName,
                    hint: 'First Name',
                    enabled: !_busy,
                    shape: _Segment.left,
                    autofillHints: const [AutofillHints.givenName],
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Enter your first name'
                        : null,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _PillField(
                    controller: _lastName,
                    hint: 'Last Name',
                    enabled: !_busy,
                    shape: _Segment.right,
                    autofillHints: const [AutofillHints.familyName],
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          _PillField(
            controller: _email,
            hint: 'Email',
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            validator: (v) =>
                v != null &&
                    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim())
                ? null
                : 'Enter a valid email',
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _PillField(
                  controller: _password,
                  hint: 'Password',
                  enabled: !_busy,
                  obscureText: _obscure,
                  shape: _Segment.left,
                  textInputAction: TextInputAction.done,
                  autofillHints: [
                    _signup
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  onSubmitted: (_) => _submit(),
                  validator: (v) => v == null || v.isEmpty
                      ? 'Enter your password'
                      : _signup && v.length < 8
                      ? 'Use at least 8 characters'
                      : null,
                ),
              ),
              const SizedBox(width: 6),
              _EyeButton(
                obscured: _obscure,
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ],
          ),
          if (!_signup)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 12, right: 6),
                child: _UnderlinedLink(
                  'Forgot password?',
                  fontSize: 12.5,
                  onTap: _busy
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PasswordRecoveryScreen(
                              initialEmail: _email.text.trim(),
                            ),
                          ),
                        ),
                ),
              ),
            ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: _message == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1EC),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF9A3B22),
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(60),
              backgroundColor: _ink,
              disabledBackgroundColor: _ink.withValues(alpha: 0.75),
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
              textStyle: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            child: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(_signup ? 'Create account' : 'Log in'),
          ),
          if (_signup) ...[
            const SizedBox(height: 22),
            Text.rich(
              const TextSpan(
                children: [
                  TextSpan(
                    text:
                        'Signing up for a SnapExpense account means you agree to the ',
                  ),
                  TextSpan(text: 'Privacy Policy', style: _legalLink),
                  TextSpan(text: ' and '),
                  TextSpan(text: 'Terms of Service', style: _legalLink),
                  TextSpan(text: '.'),
                ],
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.55),
            ),
          ],
          const SizedBox(height: 22),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _signup ? 'Have an account? ' : 'Don’t have an account? ',
                style: const TextStyle(color: _ink, fontSize: 13.5),
              ),
              _UnderlinedLink(
                _signup ? 'Log in here' : 'Sign up here',
                onTap: _busy ? null : _switchMode,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

const _legalLink = TextStyle(
  color: Color(0xFF222222),
  decoration: TextDecoration.underline,
  decorationColor: Color(0xFF222222),
);

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.topInset});
  final String title;
  final double topInset;
  @override
  Widget build(BuildContext context) => ClipRect(
    child: Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE4F1CB), Color(0xFFCFE5AE), Color(0xFFE9E4F3)],
            ),
          ),
        ),
        const Positioned(
          top: -90,
          right: -60,
          child: _Glow(color: Color(0xFFB1DB71), size: 300),
        ),
        const Positioned(
          bottom: -120,
          left: -70,
          child: _Glow(color: Color(0xFFBDA5E4), size: 260),
        ),
        const Positioned(
          top: -110,
          left: -70,
          child: _Glow(color: Color(0xCCFFFFFF), size: 230),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: .48),
                  Colors.white.withValues(alpha: .16),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: topInset),
          child: Align(
            alignment: const Alignment(0, -0.38),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  title,
                  key: ValueKey(title),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    height: 1.12,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}

enum _Segment { full, left, right }

class _PillField extends StatelessWidget {
  const _PillField({
    required this.controller,
    required this.hint,
    required this.enabled,
    this.shape = _Segment.full,
    this.obscureText = false,
    this.keyboardType,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction = TextInputAction.next,
    this.validator,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final String hint;
  final bool enabled, obscureText;
  final _Segment shape;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextCapitalization textCapitalization;
  final TextInputAction textInputAction;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    const outer = Radius.circular(30);
    const inner = Radius.circular(6);
    final radius = switch (shape) {
      _Segment.full => const BorderRadius.all(outer),
      _Segment.left => const BorderRadius.horizontal(left: outer, right: inner),
      _Segment.right => const BorderRadius.horizontal(
        left: inner,
        right: outer,
      ),
    };
    OutlineInputBorder border([Color? color]) => OutlineInputBorder(
      borderRadius: radius,
      borderSide: color == null
          ? BorderSide.none
          : BorderSide(color: color, width: 1.3),
    );
    return TextFormField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      textCapitalization: textCapitalization,
      textInputAction: textInputAction,
      validator: validator,
      onFieldSubmitted: onSubmitted,
      cursorColor: _ink,
      style: const TextStyle(fontSize: 14, color: _ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _hint, fontSize: 14),
        filled: true,
        fillColor: _fieldFill,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 21,
        ),
        errorStyle: const TextStyle(fontSize: 11, height: 1.2),
        errorMaxLines: 2,
        border: border(),
        enabledBorder: border(),
        disabledBorder: border(),
        focusedBorder: border(const Color(0x33111111)),
        errorBorder: border(const Color(0xFFE0614A)),
        focusedErrorBorder: border(const Color(0xFFE0614A)),
      ),
    );
  }
}

class _EyeButton extends StatelessWidget {
  const _EyeButton({required this.obscured, required this.onPressed});
  final bool obscured;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Material(
    color: _fieldFill,
    borderRadius: const BorderRadius.horizontal(
      left: Radius.circular(6),
      right: Radius.circular(30),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onPressed,
      child: SizedBox(
        width: 64,
        height: 63,
        child: Tooltip(
          message: obscured ? 'Show password' : 'Hide password',
          child: Icon(
            obscured ? Icons.visibility : Icons.visibility_off,
            size: 21,
            color: const Color(0xFF6B6B6B),
          ),
        ),
      ),
    ),
  );
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.onPressed});
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(60),
      shape: const StadiumBorder(),
      side: const BorderSide(color: Color(0xFFD9D9DD)),
      foregroundColor: const Color(0xFF2B2B2B),
      backgroundColor: Colors.white,
      textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
    ),
    child: const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CustomPaint(size: Size.square(24), painter: _GoogleLogoPainter()),
        SizedBox(width: 14),
        Flexible(
          child: Text('Sign in with Google', overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );
}

class _UnderlinedLink extends StatelessWidget {
  const _UnderlinedLink(this.text, {required this.onTap, this.fontSize = 13.5});
  final String text;
  final VoidCallback? onTap;
  final double fontSize;
  @override
  Widget build(BuildContext context) => Semantics(
    link: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          text,
          style: TextStyle(
            color: _ink,
            fontSize: fontSize,
            decoration: TextDecoration.underline,
            decorationColor: _ink,
            decorationThickness: 1.2,
          ),
        ),
      ),
    ),
  );
}

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * 0.2;
    final center = Offset(s / 2, s / 2);
    final r = (s - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: r);
    double rad(double deg) => deg * math.pi / 180;
    Paint arc(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(
      rect,
      rad(-140),
      rad(100),
      false,
      arc(const Color(0xFFEA4335)),
    );
    canvas.drawArc(
      rect,
      rad(140),
      rad(80),
      false,
      arc(const Color(0xFFFBBC05)),
    );
    canvas.drawArc(rect, rad(45), rad(95), false, arc(const Color(0xFF34A853)));
    canvas.drawArc(rect, rad(0), rad(45), false, arc(const Color(0xFF4285F4)));
    canvas.drawRect(
      Rect.fromLTRB(
        center.dx,
        center.dy - stroke / 2,
        s,
        center.dy + stroke / 2,
      ),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
