import 'package:flutter/material.dart';
import '../../../core/constants/api_constants.dart';
import '../../../models/user_model.dart';
import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/local_cache_service.dart';
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

  String _currentServerUrl = ApiConstants.baseUrl;
  bool _isTestingConnection = false;
  bool? _connectionStatus;
  String _connectionMessage = '';

  @override
  void initState() {
    super.initState();
    _currentServerUrl = LocalCacheService.getServerBaseUrl(defaultUrl: ApiConstants.defaultBaseUrl);
    ApiConstants.baseUrl = _currentServerUrl;
    _checkServerConnection();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkServerConnection([String? urlToTest]) async {
    final target = urlToTest ?? _currentServerUrl;
    if (mounted) {
      setState(() {
        _isTestingConnection = true;
      });
    }
    final res = await ApiService.testConnection(target);
    if (!mounted) return;
    setState(() {
      _isTestingConnection = false;
      _connectionStatus = res['success'] == true;
      _connectionMessage = res['message'] ?? '';
    });
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

  void _showServerConfigDialog() {
    String selectedUrl = _currentServerUrl;
    final customController = TextEditingController(text: selectedUrl);
    bool testing = false;
    bool? testSuccess;
    String testFeedback = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return Container(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(modalContext).viewInsets.bottom + 20,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.dns_rounded, color: NcstColors.navy),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Backend Server Connection',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: NcstColors.navy,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose where this terminal connects to authenticate guards and sync gate logs:',
                      style: TextStyle(fontSize: 12, color: NcstColors.slate500),
                    ),
                    const SizedBox(height: 16),
                    _buildServerOptionTile(
                      title: 'Live Cloud Server',
                      subtitle: 'InfinityFree (ncstparking-test.rf.gd)',
                      url: ApiConstants.liveCloudUrl,
                      selectedUrl: selectedUrl,
                      icon: Icons.cloud_outlined,
                      onTap: () {
                        setModalState(() {
                          selectedUrl = ApiConstants.liveCloudUrl;
                          customController.text = selectedUrl;
                          testSuccess = null;
                          testFeedback = '';
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildServerOptionTile(
                      title: 'Local Wi-Fi PC Server',
                      subtitle: 'Local Admin Web App (192.168.0.102:8000)',
                      url: ApiConstants.localLanUrl,
                      selectedUrl: selectedUrl,
                      icon: Icons.computer_outlined,
                      onTap: () {
                        setModalState(() {
                          selectedUrl = ApiConstants.localLanUrl;
                          customController.text = selectedUrl;
                          testSuccess = null;
                          testFeedback = '';
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildServerOptionTile(
                      title: 'Android Emulator',
                      subtitle: 'Host Loopback (10.0.2.2:8000)',
                      url: ApiConstants.localEmulatorUrl,
                      selectedUrl: selectedUrl,
                      icon: Icons.phone_android_outlined,
                      onTap: () {
                        setModalState(() {
                          selectedUrl = ApiConstants.localEmulatorUrl;
                          customController.text = selectedUrl;
                          testSuccess = null;
                          testFeedback = '';
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: customController,
                      decoration: InputDecoration(
                        labelText: 'Server API Base URL',
                        hintText: 'http://<IP_OR_DOMAIN>/api',
                        prefixIcon: const Icon(Icons.link, size: 18),
                        filled: true,
                        fillColor: NcstColors.slate50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      style: const TextStyle(fontSize: 13),
                      onChanged: (val) {
                        setModalState(() {
                          selectedUrl = val.trim();
                          testSuccess = null;
                          testFeedback = '';
                        });
                      },
                    ),
                    if (testFeedback.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: testSuccess == true ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: testSuccess == true ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              testSuccess == true ? Icons.check_circle : Icons.error_outline,
                              color: testSuccess == true ? NcstColors.success : NcstColors.error,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                testFeedback,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: testSuccess == true ? NcstColors.success : NcstColors.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: testing
                                ? null
                                : () async {
                                    setModalState(() {
                                      testing = true;
                                      testFeedback = 'Testing connection...';
                                    });
                                    final res = await ApiService.testConnection(customController.text.trim());
                                    setModalState(() {
                                      testing = false;
                                      testSuccess = res['success'] == true;
                                      testFeedback = res['message'] ?? (testSuccess! ? 'Connected successfully' : 'Unreachable');
                                    });
                                  },
                            icon: testing
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.network_check_rounded, size: 16),
                            label: const Text('TEST PING', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final clean = customController.text.trim().replaceAll(RegExp(r'/+$'), '');
                              if (clean.isEmpty) return;
                              ApiConstants.baseUrl = clean;
                              await LocalCacheService.setServerBaseUrl(clean);
                              if (!mounted) return;
                              setState(() {
                                _currentServerUrl = clean;
                                _errorMessage = null;
                              });
                              _checkServerConnection();
                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                              }
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Connected to $clean'),
                                  backgroundColor: NcstColors.navy,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: NcstColors.navy,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.save_rounded, size: 16),
                            label: const Text('SAVE & CONNECT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildServerOptionTile({
    required String title,
    required String subtitle,
    required String url,
    required String selectedUrl,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final isSelected = selectedUrl == url;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? NcstColors.navy.withValues(alpha: 0.06) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? NcstColors.navy : NcstColors.slate200,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: isSelected ? NcstColors.navy : NcstColors.slate500),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? NcstColors.navy : NcstColors.slate900,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: NcstColors.slate500),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: NcstColors.navy, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildServerConnectionCard() {
    final isCloud = _currentServerUrl == ApiConstants.liveCloudUrl;
    final isLocal = _currentServerUrl == ApiConstants.localLanUrl;
    final isEmulator = _currentServerUrl == ApiConstants.localEmulatorUrl;

    String label = 'Custom Server';
    if (isCloud) {
      label = 'Live Cloud (rf.gd)';
    } else if (isLocal) {
      label = 'Local PC (192.168.0.102)';
    } else if (isEmulator) {
      label = 'Android Emulator (10.0.2.2)';
    }

    final Color statusColor;
    final String statusText;
    final IconData statusIcon;

    if (_isTestingConnection) {
      statusColor = NcstColors.slate500;
      statusText = 'Checking connection...';
      statusIcon = Icons.sync;
    } else if (_connectionStatus == true) {
      statusColor = NcstColors.success;
      statusText = 'Connected to $label';
      statusIcon = Icons.cloud_done_rounded;
    } else if (_connectionStatus == false) {
      statusColor = NcstColors.error;
      statusText = 'Unreachable: Tap to switch';
      statusIcon = Icons.cloud_off_rounded;
    } else {
      statusColor = NcstColors.slate500;
      statusText = label;
      statusIcon = Icons.dns_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        color: _connectionStatus == false
            ? const Color(0xFFFEF2F2)
            : (_connectionStatus == true ? const Color(0xFFF0FDF4) : NcstColors.white),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _connectionStatus == false
              ? const Color(0xFFFECACA)
              : (_connectionStatus == true ? const Color(0xFFBBF7D0) : NcstColors.slate200),
        ),
      ),
      child: InkWell(
        onTap: _showServerConfigDialog,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(statusIcon, size: 18, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                    Text(
                      _currentServerUrl,
                      style: const TextStyle(
                        fontSize: 10,
                        color: NcstColors.slate500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_connectionMessage.isNotEmpty && _connectionStatus != true)
                      Text(
                        _connectionMessage,
                        style: const TextStyle(
                          fontSize: 9,
                          color: NcstColors.error,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: NcstColors.navy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'CHANGE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: NcstColors.navy,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
                    const SizedBox(height: 18),

                    // Active Server Connection Indicator
                    _buildServerConnectionCard(),
                    const SizedBox(height: 16),

                    // Quick Demo Role Selector Pills
                    _buildDemoRoleSelector(),
                    const SizedBox(height: 16),

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
