// lib/login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import 'AuthService.dart';

const String _logoAsset = 'assets/images/xaadirlogo.png';
const String _font = 'Poppins'; // must match `family:` in pubspec.yaml

class _C {
  static const primary = Color(0xFF090808);
  static const ink = Color(0xFF0F172A);

  static const muted = Color(0xFF64748B);
  static const border = Color(0xFFE2E8F0);
  static const fill = Color(0xFFF8FAFC);
  static const error = Color(0xFFDC2626);
  static const errorBg = Color(0xFFFEF2F2);
  static const infoBg = Color(0xFFEFF6FF);
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.notice});

  /// Optional message shown on arrival (e.g. "Your account is inactive").
  final String? notice;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.instance.signIn(
        _emailController.text,
        _passwordController.text,
      );
      // AuthGate reacts to the auth event and picks the next screen.
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not sign in. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Logo(),
                    const SizedBox(height: 28),
                    const Text(
                      'Welcome back',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: _font,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: _C.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Sign in with your email and password.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: _font,
                        fontSize: 14,
                        color: _C.muted,
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (widget.notice != null && _error == null) ...[
                      _Banner(message: widget.notice!, isInfo: true),
                      const SizedBox(height: 14),
                    ],
                    if (_error != null) ...[
                      _Banner(message: _error!),
                      const SizedBox(height: 14),
                    ],
                    _Field(
                      controller: _emailController,
                      label: 'Email',
                      hint: 'you@company.com',
                      enabled: !_loading,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'\s')),
                      ],
                      onSubmitted: (_) => _passwordFocus.requestFocus(),
                      prefix: const HugeIcon(
                        icon: HugeIcons.strokeRoundedMail01,
                        color: _C.muted,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _Field(
                      controller: _passwordController,
                      focusNode: _passwordFocus,
                      label: 'Password',
                      hint: '••••••••',
                      enabled: !_loading,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _submit(),
                      prefix: const HugeIcon(
                        icon: HugeIcons.strokeRoundedLockPassword,
                        color: _C.muted,
                        size: 20,
                      ),
                      suffix: IconButton(
                        splashRadius: 20,
                        icon: HugeIcon(
                          icon: _obscure
                              ? HugeIcons.strokeRoundedViewOffSlash
                              : HugeIcons.strokeRoundedView,
                          color: _C.muted,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _PrimaryButton(
                      label: 'Sign in',
                      loading: _loading,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Forgot password? Ask HR to reset it.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: _font,
                        fontSize: 13,
                        color: _C.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Logo ─────────────────────────

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Image.asset(
        _logoAsset,
        height: 80,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Container(
          height: 80,
          width: 80,
          decoration: BoxDecoration(
            color: _C.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.center,
          child: const HugeIcon(
            icon: HugeIcons.strokeRoundedImage01,
            color: _C.primary,
            size: 32,
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Text field (custom cursor) ─────────────────────────

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.focusNode,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.inputFormatters,
    this.onSubmitted,
    this.prefix,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final FocusNode? focusNode;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;
  final Widget? prefix;
  final Widget? suffix;

  OutlineInputBorder _border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      inputFormatters: inputFormatters,
      onSubmitted: onSubmitted,

      // Custom blinking cursor (instead of the default Flutter one)
      cursorColor: _C.primary,
      cursorWidth: 2.5,
      cursorHeight: 22,
      cursorRadius: const Radius.circular(4),
      cursorOpacityAnimates: true,

      style: const TextStyle(
        fontFamily: _font,
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: _C.ink,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(
          fontFamily: _font,
          fontSize: 14,
          color: _C.muted,
        ),
        floatingLabelStyle: const TextStyle(
          fontFamily: _font,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: _C.primary,
        ),
        hintStyle: TextStyle(
          fontFamily: _font,
          fontSize: 14,
          color: _C.muted.withOpacity(0.6),
        ),
        filled: true,
        fillColor: _C.fill,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        prefixIcon: prefix == null
            ? null
            : Padding(
          padding: const EdgeInsets.only(left: 14, right: 10),
          child: prefix,
        ),
        prefixIconConstraints:
        const BoxConstraints(minWidth: 44, minHeight: 20),
        suffixIcon: suffix,
        enabledBorder: _border(_C.border),
        disabledBorder: _border(_C.border),
        focusedBorder: _border(_C.primary, 1.8),
        border: _border(_C.border),
      ),
    );
  }
}

// ───────────────────────── Button ─────────────────────────

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _C.primary,
          disabledBackgroundColor: _C.primary.withOpacity(0.7),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: loading
            ? const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: Colors.white,
          ),
        )
            : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontFamily: _font,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            const HugeIcon(
              icon: HugeIcons.strokeRoundedArrowRight01,
              color: Colors.white,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Banner ─────────────────────────

class _Banner extends StatelessWidget {
  const _Banner({required this.message, this.isInfo = false});

  final String message;
  final bool isInfo;

  @override
  Widget build(BuildContext context) {
    final color = isInfo ? _C.primary : _C.error;
    final bg = isInfo ? _C.infoBg : _C.errorBg;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: HugeIcon(
              icon: isInfo
                  ? HugeIcons.strokeRoundedInformationCircle
                  : HugeIcons.strokeRoundedAlert02,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: _font,
                fontSize: 13,
                height: 1.4,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}