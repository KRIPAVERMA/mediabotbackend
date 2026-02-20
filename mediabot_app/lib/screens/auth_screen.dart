import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/animated_background.dart';

/// Unified Auth screen: Sign In / Sign Up / Verify Email
class AuthScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;
  const AuthScreen({super.key, required this.onAuthenticated});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

enum _AuthMode { signIn, signUp, verify, forgotPassword, resetPassword }

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  _AuthMode _mode = _AuthMode.signIn;

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();

  bool _loading = false;
  bool _obscurePass = true;
  String? _error;
  String? _success;
  String _pendingEmail = '';

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeInOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _newPassCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _switchMode(_AuthMode newMode) {
    _fadeCtrl.reverse().then((_) {
      setState(() {
        _mode = newMode;
        _error = null;
        _success = null;
      });
      _fadeCtrl.forward();
    });
  }

  Future<void> _handleSignUp() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    final name = _nameCtrl.text.trim();

    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Email and password are required.');
      return;
    }

    setState(() { _loading = true; _error = null; _success = null; });

    try {
      final result = await AuthService.signUp(email: email, password: pass, name: name);
      if (result['success'] == true) {
        _pendingEmail = email;
        setState(() => _success = result['message']);
        await Future.delayed(const Duration(milliseconds: 800));
        _switchMode(_AuthMode.verify);
      } else {
        setState(() => _error = result['message']);
      }
    } catch (e) {
      setState(() => _error = 'Connection error. Check server URL in settings.');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _handleVerify() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Please enter the 6-digit code.');
      return;
    }

    setState(() { _loading = true; _error = null; _success = null; });

    try {
      final result = await AuthService.verifyEmail(email: _pendingEmail, code: code);
      if (result['success'] == true) {
        setState(() => _success = result['message']);
        await Future.delayed(const Duration(milliseconds: 600));
        widget.onAuthenticated();
      } else {
        setState(() => _error = result['message']);
      }
    } catch (e) {
      setState(() => _error = 'Connection error.');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _handleResendCode() async {
    setState(() { _loading = true; _error = null; _success = null; });
    try {
      final result = await AuthService.resendCode(email: _pendingEmail);
      setState(() {
        if (result['success'] == true) {
          _success = result['message'];
        } else {
          _error = result['message'];
        }
      });
    } catch (e) {
      setState(() => _error = 'Connection error.');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Please enter your email address.');
      return;
    }
    setState(() { _loading = true; _error = null; _success = null; });
    try {
      final result = await AuthService.forgotPassword(email: email);
      if (result['success'] == true) {
        _pendingEmail = email;
        setState(() => _success = result['message']);
        await Future.delayed(const Duration(milliseconds: 800));
        _codeCtrl.clear();
        _newPassCtrl.clear();
        _switchMode(_AuthMode.resetPassword);
      } else {
        setState(() => _error = result['message']);
      }
    } catch (e) {
      setState(() => _error = 'Connection error. Check server URL in settings.');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _handleResetPassword() async {
    final code = _codeCtrl.text.trim();
    final newPass = _newPassCtrl.text.trim();
    if (code.isEmpty || newPass.isEmpty) {
      setState(() => _error = 'Code and new password are required.');
      return;
    }
    if (newPass.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    setState(() { _loading = true; _error = null; _success = null; });
    try {
      final result = await AuthService.resetPassword(
        email: _pendingEmail,
        code: code,
        newPassword: newPass,
      );
      if (result['success'] == true) {
        setState(() => _success = 'Password reset! Signing you in...');
        await Future.delayed(const Duration(milliseconds: 800));
        widget.onAuthenticated();
      } else {
        setState(() => _error = result['message']);
      }
    } catch (e) {
      setState(() => _error = 'Connection error.');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _handleSignIn() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Email and password are required.');
      return;
    }

    setState(() { _loading = true; _error = null; _success = null; });

    try {
      final result = await AuthService.login(email: email, password: pass);
      if (result['success'] == true) {
        setState(() => _success = result['message']);
        await Future.delayed(const Duration(milliseconds: 400));
        widget.onAuthenticated();
      } else if (result['needsVerification'] == true) {
        _pendingEmail = email;
        setState(() => _error = result['message']);
        await Future.delayed(const Duration(milliseconds: 800));
        _switchMode(_AuthMode.verify);
      } else {
        setState(() => _error = result['message']);
      }
    } catch (e) {
      setState(() => _error = 'Connection error. Check server URL in settings.');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const AnimatedBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: _buildContent(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_mode) {
      case _AuthMode.signIn:
        return _buildSignIn();
      case _AuthMode.signUp:
        return _buildSignUp();
      case _AuthMode.verify:
        return _buildVerify();
      case _AuthMode.forgotPassword:
        return _buildForgotPassword();
      case _AuthMode.resetPassword:
        return _buildResetPassword();
    }
  }

  Widget _buildSignIn() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildLogo(),
        const SizedBox(height: 12),
        const Text('Welcome back!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 6),
        Text('Sign in to continue', style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.5))),
        const SizedBox(height: 32),
        _buildTextField(_emailCtrl, 'Email', Icons.email_outlined, keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 14),
        _buildTextField(_passCtrl, 'Password', Icons.lock_outline, obscure: true),
        const SizedBox(height: 8),
        _buildMessages(),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () {
              _switchMode(_AuthMode.forgotPassword);
            },
            child: Text(
              'Forgot Password?',
              style: TextStyle(color: const Color(0xFFA78BFA), fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildButton('Sign In', _handleSignIn),
        const SizedBox(height: 20),
        _buildSwitchLink("Don't have an account? ", 'Sign Up', () => _switchMode(_AuthMode.signUp)),
      ],
    );
  }

  Widget _buildSignUp() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildLogo(),
        const SizedBox(height: 12),
        const Text('Create Account', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 6),
        Text('Sign up to get started', style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.5))),
        const SizedBox(height: 32),
        _buildTextField(_nameCtrl, 'Name (optional)', Icons.person_outline),
        const SizedBox(height: 14),
        _buildTextField(_emailCtrl, 'Email', Icons.email_outlined, keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 14),
        _buildTextField(_passCtrl, 'Password (min 6 chars)', Icons.lock_outline, obscure: true),
        const SizedBox(height: 8),
        _buildMessages(),
        const SizedBox(height: 20),
        _buildButton('Sign Up', _handleSignUp),
        const SizedBox(height: 20),
        _buildSwitchLink("Already have an account? ", 'Sign In', () => _switchMode(_AuthMode.signIn)),
      ],
    );
  }

  Widget _buildVerify() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildLogo(),
        const SizedBox(height: 12),
        const Text('Verify Email', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 6),
        Text('Enter the 6-digit code sent to', style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.5))),
        const SizedBox(height: 4),
        Text(_pendingEmail, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFA78BFA))),
        const SizedBox(height: 32),
        _buildTextField(_codeCtrl, '6-digit code', Icons.pin_outlined, keyboardType: TextInputType.number, maxLength: 6),
        const SizedBox(height: 8),
        _buildMessages(),
        const SizedBox(height: 20),
        _buildButton('Verify', _handleVerify),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _loading ? null : _handleResendCode,
          child: Text('Resend Code', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
        ),
        const SizedBox(height: 8),
        _buildSwitchLink('', '← Back to Sign In', () => _switchMode(_AuthMode.signIn)),
      ],
    );
  }

  Widget _buildForgotPassword() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildLogo(),
        const SizedBox(height: 12),
        const Text('Forgot Password', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 6),
        Text("Enter your email and we'll send a reset code", style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.5)), textAlign: TextAlign.center),
        const SizedBox(height: 32),
        _buildTextField(_emailCtrl, 'Email', Icons.email_outlined, keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 8),
        _buildMessages(),
        const SizedBox(height: 20),
        _buildButton('Send Reset Code', _handleForgotPassword),
        const SizedBox(height: 20),
        _buildSwitchLink('', '← Back to Sign In', () => _switchMode(_AuthMode.signIn)),
      ],
    );
  }

  Widget _buildResetPassword() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildLogo(),
        const SizedBox(height: 12),
        const Text('Reset Password', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 6),
        Text('Enter the 6-digit code sent to', style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.5))),
        const SizedBox(height: 4),
        Text(_pendingEmail, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFA78BFA))),
        const SizedBox(height: 32),
        _buildTextField(_codeCtrl, '6-digit code', Icons.pin_outlined, keyboardType: TextInputType.number, maxLength: 6),
        const SizedBox(height: 14),
        _buildTextField(_newPassCtrl, 'New password (min 6 chars)', Icons.lock_outline, obscure: true),
        const SizedBox(height: 8),
        _buildMessages(),
        const SizedBox(height: 20),
        _buildButton('Reset Password', _handleResetPassword),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _loading ? null : () async {
            setState(() { _loading = true; _error = null; _success = null; });
            try {
              final result = await AuthService.forgotPassword(email: _pendingEmail);
              setState(() {
                if (result['success'] == true) _success = result['message'];
                else _error = result['message'];
              });
            } catch (e) {
              setState(() => _error = 'Connection error.');
            } finally {
              setState(() => _loading = false);
            }
          },
          child: Text('Resend Code', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
        ),
        const SizedBox(height: 8),
        _buildSwitchLink('', '← Back to Sign In', () => _switchMode(_AuthMode.signIn)),
      ],
    );
  }

  // ── Reusable widgets ────────────────────────────────────

  Widget _buildLogo() {
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(colors: [Color(0xFFA78BFA), Color(0xFFF472B6)]),
        boxShadow: [BoxShadow(color: const Color(0xFFA78BFA).withValues(alpha: 0.4), blurRadius: 30)],
      ),
      alignment: Alignment.center,
      child: const Text('🤖', style: TextStyle(fontSize: 36)),
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure ? _obscurePass : false,
      keyboardType: keyboardType,
      maxLength: maxLength,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
        prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: 0.4), size: 20),
        suffixIcon: obscure
            ? IconButton(
                icon: Icon(
                  _obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: Colors.white.withValues(alpha: 0.4),
                  size: 20,
                ),
                onPressed: () => setState(() => _obscurePass = !_obscurePass),
              )
            : null,
        counterText: '',
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFA78BFA), width: 1.5),
        ),
      ),
    );
  }

  Widget _buildMessages() {
    return Column(
      children: [
        if (_error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ),
        if (_success != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF34D399).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.3)),
            ),
            child: Text(_success!, style: const TextStyle(color: Color(0xFF34D399), fontSize: 13)),
          ),
      ],
    );
  }

  Widget _buildButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(colors: [Color(0xFFA78BFA), Color(0xFFF472B6)]),
          boxShadow: [
            BoxShadow(color: const Color(0xFFA78BFA).withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 4)),
          ],
        ),
        child: ElevatedButton(
          onPressed: _loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: _loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
        ),
      ),
    );
  }

  Widget _buildSwitchLink(String prefix, String action, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(text: prefix, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
            TextSpan(text: action, style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
