// lib/screens/forgot_password_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  bool _isLoading = false;
  bool _emailSent = false;

  static const Color _ink = Color(0xFF0F172A);
  static const Color _fieldBg = Color(0xFFF1F3F7);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _error = Color(0xFFDC2626);

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'Please enter your email';
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(email)) return 'Please enter a valid email';
    return null;
  }

  Future<void> _onSendResetLink() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      debugPrint('⚠️ Forgot password: validation failed');
      return;
    }

    final email = _emailController.text.trim();
    setState(() => _isLoading = true);
    debugPrint('📧 Sending reset link to: $email');

    try {
      // TODO: connect to Supabase later, for example:
      // await Supabase.instance.client.auth.resetPasswordForEmail(email);
      await Future.delayed(const Duration(milliseconds: 1200));

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _emailSent = true;
      });
      debugPrint('✅ Reset link sent');
    } catch (e) {
      debugPrint('❌ Reset link failed: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong. Please try again.')),
      );
    }
  }

  void _onBackToSignIn() {
    debugPrint('⬅️ Back to sign in tapped');
    Navigator.maybePop(context);
  }

  void _onTryAnotherEmail() {
    debugPrint('🔁 Try another email tapped');
    setState(() => _emailSent = false);
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
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _emailSent ? _buildSuccess() : _buildForm(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────── Form state ─────────────────────────
  Widget _buildForm() {
    return Column(
      key: const ValueKey('form'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLogo(const Icon(Icons.hexagon_rounded, color: Colors.white, size: 32)),
        const SizedBox(height: 28),
        const Text(
          'Forgot password?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "No worries, we'll send you reset instructions.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: _muted),
        ),
        const SizedBox(height: 32),

        Form(
          key: _formKey,
          child: TextFormField(
            controller: _emailController,
            validator: _validateEmail,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            onFieldSubmitted: (_) => _onSendResetLink(),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: _ink,
            ),
            decoration: _inputDecoration('Email'),
          ),
        ),
        const SizedBox(height: 24),

        SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _onSendResetLink,
            style: ElevatedButton.styleFrom(
              backgroundColor: _ink,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _ink.withOpacity(0.6),
              disabledForegroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: Colors.white,
              ),
            )
                : const Text(
              'Send reset link',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 24),

        _buildBackToSignInRow(),
      ],
    );
  }

  // ───────────────────────── Success state ─────────────────────────
  Widget _buildSuccess() {
    final email = _emailController.text.trim();

    return Column(
      key: const ValueKey('success'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLogo(
          const Icon(Icons.mark_email_read_outlined, color: Colors.white, size: 30),
        ),
        const SizedBox(height: 28),
        const Text(
          'Check your email',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'We sent a password reset link to\n$email',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: _muted, height: 1.5),
        ),
        const SizedBox(height: 32),

        SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: _onBackToSignIn,
            style: ElevatedButton.styleFrom(
              backgroundColor: _ink,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: const Text(
              'Back to sign in',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 24),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Didn't receive the email? ",
              style: TextStyle(fontSize: 13, color: _muted),
            ),
            GestureDetector(
              onTap: _onTryAnotherEmail,
              child: const Text(
                'Try again',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ───────────────────────── Shared widgets ─────────────────────────
  Widget _buildLogo(Widget icon) {
    return Center(
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: _ink,
          borderRadius: BorderRadius.circular(18),
        ),
        child: icon,
      ),
    );
  }

  Widget _buildBackToSignInRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.arrow_back_rounded, size: 16, color: _ink),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: _onBackToSignIn,
          child: const Text(
            'Back to sign in',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 14, color: _muted),
      floatingLabelStyle: const TextStyle(fontSize: 13, color: _muted),
      errorStyle: const TextStyle(fontSize: 12, color: _error),
      filled: true,
      fillColor: _fieldBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _ink, width: 1.2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _error, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _error, width: 1.2),
      ),
    );
  }
}