// lib/staff_recovery_screen.dart
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
  static const ok = Color(0xFF16A34A);
  static const okBg = Color(0xFFF0FDF4);
  static const error = Color(0xFFDC2626);
  static const errorBg = Color(0xFFFEF2F2);
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

/// Pops with `true` once the password was reset, so Login can show a message.
class StaffRecoveryScreen extends StatefulWidget {
  const StaffRecoveryScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<StaffRecoveryScreen> createState() => _StaffRecoveryScreenState();
}

class _StaffRecoveryScreenState extends State<StaffRecoveryScreen> {
  late final TextEditingController _emailController;
  final _codeController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  final _codeFocus = FocusNode();
  final _newFocus = FocusNode();
  final _confirmFocus = FocusNode();

  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  bool _success = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
    _emailController.addListener(_refresh);
    _codeController.addListener(_refresh);
    _newController.addListener(_refresh);
    _confirmController.addListener(_refresh);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    _codeFocus.dispose();
    _newFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  String get _password => _newController.text;

  bool get _emailOk {
    final e = _emailController.text.trim();
    return e.contains('@') && e.contains('.');
  }

  bool get _codeOk => _codeController.text.trim().length >= 6;
  bool get _hasLength => _password.length >= 12;
  bool get _hasUpper => RegExp(r'[A-Z]').hasMatch(_password);
  bool get _hasLower => RegExp(r'[a-z]').hasMatch(_password);
  bool get _hasNumber => RegExp(r'\d').hasMatch(_password);
  bool get _matches =>
      _password.isNotEmpty && _password == _confirmController.text;

  bool get _canSubmit =>
      !_loading &&
          _emailOk &&
          _codeOk &&
          _hasLength &&
          _hasUpper &&
          _hasLower &&
          _hasNumber &&
          _matches;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.instance.resetStaffPassword(
        email: _emailController.text,
        code: _codeController.text,
        newPassword: _newController.text,
        confirmPassword: _confirmController.text,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = true;
      });
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong. Please try again.';
        _loading = false;
      });
    }
  }

  void _backToLogin() {
    if (_loading) return;
    Navigator.of(context).pop(_success);
  }

  Widget _rule(String text, bool ok) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          HugeIcon(
            icon: ok
                ? HugeIcons.strokeRoundedCheckmarkCircle02
                : HugeIcons.strokeRoundedCircle,
            size: 18,
            color: ok ? _C.ok : _C.muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: _font,
                fontSize: 13,
                color: ok ? _C.ink : _C.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _eye(bool obscure, VoidCallback onTap) {
    return IconButton(
      splashRadius: 20,
      icon: HugeIcon(
        icon: obscure
            ? HugeIcons.strokeRoundedViewOffSlash
            : HugeIcons.strokeRoundedView,
        color: _C.muted,
        size: 20,
      ),
      onPressed: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // System back: leave unless a request is in flight, and still report
        // success to Login if the reset already went through.
        if (!didPop) _backToLogin();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: _success ? _buildSuccess() : _buildForm(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Logo(),
        const SizedBox(height: 28),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: _C.okBg,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const HugeIcon(
              icon: HugeIcons.strokeRoundedCheckmarkCircle02,
              color: _C.ok,
              size: 40,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Password updated',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: _font,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: _C.ink,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your password was reset. Sign in with your new password.',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: _font, fontSize: 14, color: _C.muted),
        ),
        const SizedBox(height: 28),
        _PrimaryButton(label: 'Back to sign in', onPressed: _backToLogin),
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Logo(),
        const SizedBox(height: 28),
        const Text(
          'Reset password',
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
          'Enter the reset code HR gave you (valid for 30 minutes, one use) and choose a new password.',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: _font, fontSize: 14, color: _C.muted),
        ),
        const SizedBox(height: 28),
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
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
          onSubmitted: (_) => _codeFocus.requestFocus(),
          prefix: const HugeIcon(
            icon: HugeIcons.strokeRoundedMail01,
            color: _C.muted,
            size: 20,
          ),
        ),
        const SizedBox(height: 14),
        _Field(
          controller: _codeController,
          focusNode: _codeFocus,
          label: 'Reset code',
          enabled: !_loading,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.next,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
            _UpperCaseFormatter(),
            LengthLimitingTextInputFormatter(32),
          ],
          onSubmitted: (_) => _newFocus.requestFocus(),
          prefix: const HugeIcon(
            icon: HugeIcons.strokeRoundedKey01,
            color: _C.muted,
            size: 20,
          ),
        ),
        const SizedBox(height: 14),
        _Field(
          controller: _newController,
          focusNode: _newFocus,
          label: 'New password',
          enabled: !_loading,
          obscureText: _obscureNew,
          textInputAction: TextInputAction.next,
          inputFormatters: [LengthLimitingTextInputFormatter(128)],
          onSubmitted: (_) => _confirmFocus.requestFocus(),
          prefix: const HugeIcon(
            icon: HugeIcons.strokeRoundedLockPassword,
            color: _C.muted,
            size: 20,
          ),
          suffix: _eye(_obscureNew, () => setState(() => _obscureNew = !_obscureNew)),
        ),
        const SizedBox(height: 14),
        _Field(
          controller: _confirmController,
          focusNode: _confirmFocus,
          label: 'Confirm password',
          enabled: !_loading,
          obscureText: _obscureConfirm,
          textInputAction: TextInputAction.done,
          inputFormatters: [LengthLimitingTextInputFormatter(128)],
          onSubmitted: (_) => _submit(),
          prefix: const HugeIcon(
            icon: HugeIcons.strokeRoundedLockPassword,
            color: _C.muted,
            size: 20,
          ),
          suffix: _eye(
            _obscureConfirm,
                () => setState(() => _obscureConfirm = !_obscureConfirm),
          ),
        ),
        const SizedBox(height: 16),
        _rule('At least 12 characters', _hasLength),
        _rule('Contains an uppercase letter', _hasUpper),
        _rule('Contains a lowercase letter', _hasLower),
        _rule('Contains a number', _hasNumber),
        _rule('Passwords match', _matches),
        const SizedBox(height: 24),
        _PrimaryButton(
          label: 'Reset password',
          loading: _loading,
          onPressed: _canSubmit ? _submit : null,
        ),
        const SizedBox(height: 16),
        Center(
          child: GestureDetector(
            onTap: _loading ? null : _backToLogin,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedArrowLeft01,
                    color: _C.muted,
                    size: 16,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Back to sign in',
                    style: TextStyle(
                      fontFamily: _font,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _C.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
    this.textCapitalization = TextCapitalization.none,
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
  final TextCapitalization textCapitalization;
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
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      onSubmitted: onSubmitted,
      autocorrect: false,
      enableSuggestions: false,

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
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _C.primary,
          disabledBackgroundColor:
          loading ? _C.primary : _C.primary.withOpacity(0.25),
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
  const _Banner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _C.errorBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.error.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: HugeIcon(
              icon: HugeIcons.strokeRoundedAlert02,
              color: _C.error,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontFamily: _font,
                fontSize: 13,
                height: 1.4,
                color: _C.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}