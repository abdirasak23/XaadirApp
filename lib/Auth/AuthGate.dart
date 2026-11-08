// lib/auth_gate.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../Pages/HomePage.dart';
import 'AuthService.dart';
import 'AuthWidgets.dart';
import 'ChangePassword.dart';
import 'Login.dart';

enum _Phase { loading, login, changePassword, home, error }

/// The server decides the screen: every signed-in session goes through `check`.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthService _auth = AuthService.instance;

  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<void>? _recheckSub;

  _Phase _phase = _Phase.loading;
  String? _notice;
  String? _errorMessage;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _authSub = _auth.authChanges.listen(_onAuthEvent);
    _recheckSub = _auth.recheckRequests.listen((_) => _evaluate());

    if (_auth.hasSession) {
      _evaluate();
    } else {
      _phase = _Phase.login;
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _recheckSub?.cancel();
    super.dispose();
  }

  void _onAuthEvent(AuthState state) {
    if (!mounted) return;
    switch (state.event) {
      case AuthChangeEvent.signedOut:
        _seq++;
        setState(() {
          _notice = _auth.flashNotice ?? _notice;
          _auth.flashNotice = null;
          _phase = _Phase.login;
        });
        break;
      case AuthChangeEvent.initialSession:
      case AuthChangeEvent.signedIn:
        if (state.session != null) {
          _evaluate();
        } else if (_phase != _Phase.login) {
          setState(() => _phase = _Phase.login);
        }
        break;
      default:
        break; // tokenRefreshed, userUpdated, passwordRecovery, ...
    }
  }

  Future<void> _evaluate() async {
    final id = ++_seq;
    // Only show the spinner when nothing meaningful is on screen yet.
    if (_phase == _Phase.login || _phase == _Phase.error || _phase == _Phase.loading) {
      if (_phase != _Phase.loading) setState(() => _phase = _Phase.loading);
    }
    try {
      final state = await _auth.check();
      if (!mounted || id != _seq) return;
      setState(() {
        _notice = null;
        _phase = state == StaffState.needsPasswordChange ? _Phase.changePassword : _Phase.home;
      });
    } on AuthFailure catch (e) {
      if (!mounted || id != _seq) return;
      if (e.code == 'UNAUTHORIZED') {
        // Service already cleared the session; the signedOut event shows Login.
        setState(() => _phase = _Phase.login);
      } else if (e.endsSession) {
        setState(() => _notice = e.message);
        await _auth.signOut();
        if (!mounted) return;
        setState(() => _phase = _Phase.login);
      } else if (_phase == _Phase.home || _phase == _Phase.changePassword) {
        // Quiet re-check failed (e.g. offline): keep the current screen.
      } else {
        setState(() {
          _errorMessage = e.message;
          _phase = _Phase.error;
        });
      }
    } catch (_) {
      if (!mounted || id != _seq) return;
      if (_phase == _Phase.home || _phase == _Phase.changePassword) return;
      setState(() {
        _errorMessage = 'Something went wrong. Please try again.';
        _phase = _Phase.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _Phase.loading:
        return const Scaffold(
          backgroundColor: Colors.white,
          body: Center(child: CircularProgressIndicator(color: AuthColors.ink)),
        );
      case _Phase.login:
        return LoginScreen(notice: _notice);
      case _Phase.changePassword:
        return const StaffRecoveryScreen();
      case _Phase.home:
        return const HomeScreen();
      case _Phase.error:
        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AuthLogo(),
                      const SizedBox(height: 24),
                      AuthErrorBanner(message: _errorMessage ?? 'Something went wrong.'),
                      const SizedBox(height: 20),
                      AuthPrimaryButton(label: 'Try again', onPressed: _evaluate),
                      const SizedBox(height: 16),
                      Center(
                        child: GestureDetector(
                          onTap: () => _auth.signOut(),
                          child: const Text(
                            'Sign out',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AuthColors.muted,
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
        );
    }
  }
}