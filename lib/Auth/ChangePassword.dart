// lib/change_password_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'AuthService.dart';

const String _logoAsset = 'assets/images/xaadirlogo.png';
const String _font = 'Poppins'; // must match `family:` in pubspec.yaml


class _C {
  static const primary = Color(0xFF000000); // brand black
  static const ink = Color(0xFF0A0A0A);
  static const muted = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);
  static const fill = Color(0xFFF9FAFB);
  static const ok = Color(0xFF16A34A);
  static const error = Color(0xFFDC2626);
  static const errorBg = Color(0xFFFEF2F2);
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _codeController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;

  // Temporary password is "Xd" + 4 digits (always 6 chars); the server enforces the exact rule.
  static final RegExp _temporaryPattern =
  RegExp(r'^xd\d{4}$', caseSensitive: false);

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_refresh);
    _newController.addListener(_refresh);
    _confirmController.addListener(_refresh);
  }

  @override
  void dispose() {
    _codeController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  String get _password => _newController.text;

  bool get _hasLength => _password.length >= 8;
  bool get _hasLetter => RegExp(r'[A-Za-z]').hasMatch(_password);
  bool get _hasNumber => RegExp(r'[0-9]').hasMatch(_password);
  bool get _notTemporary =>
      _password.isNotEmpty && !_temporaryPattern.hasMatch(_password);
  bool get _matches =>
      _password.isNotEmpty && _password == _confirmController.text;
  bool get _codeComplete => _codeController.text.length == 8;

  bool get _canSubmit =>
      !_loading &&
          _codeComplete &&
          _hasLength &&
          _hasLetter &&
          _hasNumber &&
          _notTemporary &&
          _matches &&
          _password.length <= 72;

  String _messageFor(AuthFailure e) {
    switch (e.code) {
      case 'WRONG_CODE':
        final left = e.attemptsLeft;
        if (left != null) {
          return 'Wrong invite code. $left attempt${left == 1 ? '' : 's'} left.';
        }
        return 'Wrong invite code.';
      case 'INVITE_LOCKED':
        return 'Your invite is locked. Ask HR to resend it.';
      case 'INVITE_EXPIRED':
        return 'This invite has expired. Ask HR to send a new one.';
      case 'NO_INVITE':
        return 'No active invite. Ask HR to send you an invite code.';
      case 'WEAK_PASSWORD':
        return e.message;
      case 'DEVICE_NOT_APPROVED':
        return 'This account is linked to another phone. Ask HR for help.';
      case 'ALREADY_CHANGED':
        return 'Your password was already changed. Opening the app…';
      case 'STAFF_INACTIVE':
        return 'Your account is inactive. Contact HR.';
      default:
        return e.message;
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.instance.changePassword(
        newPassword: _newController.text,
        inviteCode: _codeController.text,
      );
      // Success: re-sign-in fires an auth event and AuthGate opens Home.
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _messageFor(e);
        _loading = false;
      });
      if (e.code == 'ALREADY_CHANGED' || e.code == 'STAFF_INACTIVE') {
        AuthService.instance.requestRecheck();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _signOut() async {
    if (_loading) return;
    await AuthService.instance.signOut();
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
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Logo(),
                    const SizedBox(height: 28),
                    const Text(
                      'Change password',
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
                      'Enter the invite code HR sent you and choose a new password.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: _font,
                        fontSize: 14,
                        color: _C.muted,
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (_error != null) ...[
                      _Banner(message: _error!),
                      const SizedBox(height: 14),
                    ],
                    _Field(
                      controller: _codeController,
                      label: 'Invite code',
                      enabled: !_loading,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-z0-9]')),
                        _UpperCaseFormatter(),
                        LengthLimitingTextInputFormatter(8),
                      ],
                      prefix: const HugeIcon(
                        icon: HugeIcons.strokeRoundedKey01,
                        color: _C.muted,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _Field(
                      controller: _newController,
                      label: 'New password',
                      enabled: !_loading,
                      obscureText: _obscureNew,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [LengthLimitingTextInputFormatter(72)],
                      prefix: const HugeIcon(
                        icon: HugeIcons.strokeRoundedLockPassword,
                        color: _C.muted,
                        size: 20,
                      ),
                      suffix: _eye(_obscureNew,
                              () => setState(() => _obscureNew = !_obscureNew)),
                    ),
                    const SizedBox(height: 14),
                    _Field(
                      controller: _confirmController,
                      label: 'Confirm password',
                      enabled: !_loading,
                      obscureText: _obscureConfirm,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [LengthLimitingTextInputFormatter(72)],
                      onSubmitted: (_) => _submit(),
                      prefix: const HugeIcon(
                        icon: HugeIcons.strokeRoundedLockPassword,
                        color: _C.muted,
                        size: 20,
                      ),
                      suffix: _eye(
                        _obscureConfirm,
                            () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _rule('At least 8 characters', _hasLength),
                    _rule('Contains a letter', _hasLetter),
                    _rule('Contains a number', _hasNumber),
                    _rule('Not your temporary password', _notTemporary),
                    _rule('Passwords match', _matches),
                    const SizedBox(height: 24),
                    _PrimaryButton(
                      label: 'Update password',
                      loading: _loading,
                      onPressed: _canSubmit ? _submit : null,
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: GestureDetector(
                        onTap: _signOut,
                        behavior: HitTestBehavior.opaque,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              HugeIcon(
                                icon: HugeIcons.strokeRoundedLogout01,
                                color: _C.muted,
                                size: 16,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Sign out',
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
            color: _C.primary.withOpacity(0.06),
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
        focusedBorder: _border(_C.primary, 1.6),
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
          // Solid black while loading, faded black when form is incomplete.
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