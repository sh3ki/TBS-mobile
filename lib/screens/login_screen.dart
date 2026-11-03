import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/app_update_service.dart';
import '../services/credentials_service.dart';
import '../utils/error_handler.dart';
import '../widgets/tbs_logo.dart';
import 'menu_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberMe = false;
  bool _credentialsLoaded = false;
  List<SavedCredential> _savedAccounts = [];
  SavedCredential? _selectedAccount;
  late final Future<String> _installedVersionFuture;

  @override
  void initState() {
    super.initState();
    print('[LoginScreen] initState called - loading saved credentials');
    WidgetsBinding.instance.addObserver(this);
    _credentialsLoaded = false;
    _installedVersionFuture = AppUpdateService.getInstalledVersion();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    print('[LoginScreen] dispose called');
    WidgetsBinding.instance.removeObserver(this);
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('[LoginScreen] App lifecycle state changed: $state');
    if (state == AppLifecycleState.resumed) {
      print('[LoginScreen] App resumed - reloading credentials');
      _credentialsLoaded = false;
      _loadSavedCredentials();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Always load credentials when screen becomes visible
    // This handles both fresh app start and returning after logout
    print('[LoginScreen] didChangeDependencies called - checking if need to reload credentials');
    
    // Reload if fields are empty (means user logged out) or if this is first load
    if (_usernameController.text.isEmpty && _passwordController.text.isEmpty) {
      print('[LoginScreen] Fields are empty - loading saved credentials');
      _loadSavedCredentials();
    }
  }

  /// Load saved credentials and show picker if multiple exist
  Future<void> _loadSavedCredentials() async {
    try {
      print('[LoginScreen] _loadSavedCredentials called');
      final credentials = await CredentialsService.getCredentials();

      if (!mounted) {
        print('[LoginScreen] Widget unmounted, returning');
        return;
      }

      print('[LoginScreen] Found ${credentials.length} saved credentials');

      setState(() {
        _savedAccounts = credentials;
      });

      if (credentials.isEmpty) {
        // No saved credentials
        print('[LoginScreen] No saved credentials found');
        setState(() {
          _selectedAccount = null;
        });
        return;
      } else if (credentials.length == 1) {
        // Auto-fill the only saved credential
        print('[LoginScreen] Single credential found, auto-filling: ${credentials[0].username}');
        _usernameController.text = credentials[0].username;
        _passwordController.text = credentials[0].password;
        _rememberMe = true;
        setState(() {
          _selectedAccount = credentials[0];
        });
        print('[LoginScreen] State updated with auto-filled credentials');
      } else {
        // Multiple accounts - don't auto-fill, show dropdown for selection
        print('[LoginScreen] Multiple credentials found (${credentials.length}), user must select');
        setState(() {
          _selectedAccount = null;
          // Clear fields so dropdown can be used
          _usernameController.clear();
          _passwordController.clear();
          _rememberMe = false;
        });
      }
    } catch (e) {
      print('[LoginScreen] Error loading saved credentials: $e');
    }
  }

  /// Handle account selection from dropdown
  void _onAccountSelected(SavedCredential? credential) {
    if (credential != null) {
      print('[LoginScreen] Account selected: ${credential.username}');
      _usernameController.text = credential.username;
      _passwordController.text = credential.password;
      _rememberMe = true;
      setState(() {
        _selectedAccount = credential;
      });
      print('[LoginScreen] Fields filled with selected account');
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final auth = context.read<AuthProvider>();

    try {
      print('[LoginScreen] Login attempt with username: ${_usernameController.text.trim()}, rememberMe: $_rememberMe');
      await auth.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );

      // Save credentials if "Remember Me" is checked
      if (_rememberMe) {
        print('[LoginScreen] Remember Me checked, saving credentials...');
        await CredentialsService.saveCredentials(
          _usernameController.text.trim(),
          _passwordController.text,
        );
        print('[LoginScreen] Credentials saved successfully');
      } else {
        print('[LoginScreen] Remember Me NOT checked, skipping credential save');
      }

      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MenuScreen()),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorHandler.getUserFriendlyMessage(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<AuthProvider>().isLoading;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF3E9AF4),
              const Color(0xFF3E9AF4).withOpacity(0.9),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                SizedBox(height: size.height * 0.08),
                const TbsLogo(width: 240),
                const SizedBox(height: 12),
                const Text(
                  'TBS CONTAINER YARD',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Gate Management System',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: Colors.white70,
                      ),
                    ),
                    SizedBox(width: 8),
                    FutureBuilder<String>(
                      future: _installedVersionFuture,
                      builder: (context, snapshot) => Text(
                        snapshot.hasData && snapshot.data!.isNotEmpty
                            ? 'v${snapshot.data}'
                            : 'Version unavailable',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: size.height * 0.08),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sign In',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF31393C),
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Show account selector dropdown if multiple accounts are saved
                        if (_savedAccounts.length > 1)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Saved Accounts',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF31393C),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  border: Border.all(
                                    color: Colors.grey[300]!,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: DropdownButton<SavedCredential>(
                                  value: _selectedAccount,
                                  isExpanded: true,
                                  underline: const SizedBox(),
                                  hint: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 12),
                                    child: Text('Select an account'),
                                  ),
                                  items: _savedAccounts.map((account) {
                                    return DropdownMenuItem(
                                      value: account,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        child: Text(account.username),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: _onAccountSelected,
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
                          ),
                        const Text(
                          'Username',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF31393C),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            hintText: 'Enter your username',
                            hintStyle: TextStyle(
                              color: Colors.grey[400],
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Colors.grey[300]!,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Colors.grey[300]!,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFF3E9AF4),
                                width: 2,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Username is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Password',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF31393C),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            hintText: 'Enter your password',
                            hintStyle: TextStyle(
                              color: Colors.grey[400],
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Colors.grey[300]!,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Colors.grey[300]!,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFF3E9AF4),
                                width: 2,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Password is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Checkbox(
                              value: _rememberMe,
                              onChanged: (value) {
                                setState(() {
                                  _rememberMe = value ?? false;
                                });
                              },
                              activeColor: const Color(0xFF3E9AF4),
                            ),
                            const Text(
                              'Remember Me',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF31393C),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: loading ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3E9AF4),
                              disabledBackgroundColor: Colors.grey[400],
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: loading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Text(
                                    'SIGN IN',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: size.height * 0.06),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
