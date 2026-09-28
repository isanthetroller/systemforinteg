import 'package:flutter/material.dart';
import '../../../models/user_model.dart';
import '../../../services/auth_service.dart';
import '../../../theme/ncst_theme.dart';
import '../../guard/screens/guard_shell_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController(text: 'guard1');
  final _passwordController = TextEditingController(text: 'password123');

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _applyDemoRole(GuardRole role) {
    setState(() {
      _errorMessage = null;
      if (role == GuardRole.entrance) {
        _usernameController.text = 'guard1';
        _passwordController.text = 'password123';
      } else {
        _usernameController.text = 'guard2';
        _passwordController.text = 'password123';
      }
    });
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await AuthService().login(
        username: _usernameController.text,
        password: _passwordController.text,
      );

      if (!mounted) return;

      // Navigate to shared guard interface with user context
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GuardShellScreen(user: user),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isCompact = media.size.width < 360;

    return Scaffold(
      backgroundColor: NcstColors.slate50,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 16 : 24,
              vertical: 20,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand Logo & Header
                    _buildHeader(isCompact),
                    const SizedBox(height: 24),

                    // Quick Demo Role Selector Pills
                    _buildDemoRoleSelector(),
                    const SizedBox(height: 20),

                    // Error Banner if authentication fails
                    if (_errorMessage != null) ...[
                      _buildErrorBanner(),
                      const SizedBox(height: 16),
                    ],

                    // Credentials Card
                    _buildCredentialsCard(),
                    const SizedBox(height: 20),

                    // Login Button
                    _buildLoginButton(),
                    const SizedBox(height: 24),

                    // Footer Version & Gate Info
                    _buildFooter(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isCompact) {
    return Column(
      children: [
        Container(
          width: isCompact ? 60 : 72,
          height: isCompact ? 60 : 72,
          decoration: BoxDecoration(
            color: NcstColors.navy,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: NcstColors.navy.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.shield_outlined,
              size: 38,
              color: NcstColors.gold,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'NCST SECUREPARK',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            color: NcstColors.navyDark,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        const Text(
          'Gate Security Terminal',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: NcstColors.slate600,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildDemoRoleSelector() {
    final currentText = _usernameController.text.toLowerCase();
    final isEntrance = currentText.contains('1') || currentText.contains('entrance');
    final isExit = currentText.contains('2') || currentText.contains('exit');

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: NcstColors.slate200,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _applyDemoRole(GuardRole.entrance),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isEntrance ? NcstColors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: isEntrance
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.login_rounded,
                        size: 16,
                        color: isEntrance ? NcstColors.green : NcstColors.slate600,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Guard 1 (Entrance)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isEntrance ? FontWeight.w800 : FontWeight.w600,
                          color: isEntrance ? NcstColors.navyDark : NcstColors.slate600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: GestureDetector(
              onTap: () => _applyDemoRole(GuardRole.exit),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isExit ? NcstColors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: isExit
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.logout_rounded,
                        size: 16,
                        color: isExit ? NcstColors.navy : NcstColors.slate600,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Guard 2 (Exit)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isExit ? FontWeight.w800 : FontWeight.w600,
                          color: isExit ? NcstColors.navyDark : NcstColors.slate600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: NcstColors.crimsonLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NcstColors.crimson.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 20, color: NcstColors.crimson),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: NcstColors.crimson,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCredentialsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NcstColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NcstColors.slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Guard Username / ID',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: NcstColors.slate700,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _usernameController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              hintText: 'e.g. guard1 or guard2',
              hintStyle: const TextStyle(color: NcstColors.slate400, fontSize: 14),
              prefixIcon: const Icon(Icons.badge_outlined, color: NcstColors.slate500, size: 20),
              filled: true,
              fillColor: NcstColors.slate50,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: NcstColors.slate200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: NcstColors.slate200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: NcstColors.navy, width: 1.5),
              ),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Please enter your username';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          const Text(
            'Password',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: NcstColors.slate700,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _handleLogin(),
            decoration: InputDecoration(
              hintText: 'Enter guard password',
              hintStyle: const TextStyle(color: NcstColors.slate400, fontSize: 14),
              prefixIcon: const Icon(Icons.lock_outline, color: NcstColors.slate500, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: NcstColors.slate500,
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
              filled: true,
              fillColor: NcstColors.slate50,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: NcstColors.slate200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: NcstColors.slate200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: NcstColors.navy, width: 1.5),
              ),
            ),
            validator: (val) {
              if (val == null || val.isEmpty) {
                return 'Please enter your password';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: NcstColors.navy,
          foregroundColor: NcstColors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(NcstColors.white),
                ),
              )
            : const FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'SIGN IN TO GATE TERMINAL',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildFooter() {
    return const Column(
      children: [
        Text(
          'NCST Campus Security & Safety Management',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: NcstColors.slate500,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 2),
        Text(
          'Integrated Vehicle Access Control System v2.5',
          style: TextStyle(
            fontSize: 10,
            color: NcstColors.slate400,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
