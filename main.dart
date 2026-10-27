import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const EmergencyLocatorApp());
}

// ============================================================
// APP
// ============================================================

class EmergencyLocatorApp extends StatefulWidget {
  const EmergencyLocatorApp({super.key});

  @override
  State<EmergencyLocatorApp> createState() =>
      _EmergencyLocatorAppState();
}

class _EmergencyLocatorAppState extends State<EmergencyLocatorApp> {
  bool darkMode = false;

  @override
  void initState() {
    super.initState();
    _loadSavedTheme();
  }

  Future<void> _loadSavedTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDarkMode = prefs.getBool('emergency_locator_dark_mode') ?? false;
    if (!mounted) return;
    setState(() => darkMode = savedDarkMode);
  }

  Future<void> changeTheme(bool value) async {
    // Update the UI immediately so switching back to white is instant.
    setState(() => darkMode = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('emergency_locator_dark_mode', value);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Emergency Locator',
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      // Emergency access should not be blocked by a login screen.
      home: MainPage(
        darkMode: darkMode,
        onThemeChanged: changeTheme,
      ),
    );
  }
}

// ============================================================
// SPLASH / AUTOMATIC LOGIN
// ============================================================

class SplashPage extends StatefulWidget {
  final bool darkMode;
  final ValueChanged<bool> onThemeChanged;

  const SplashPage({
    super.key,
    required this.darkMode,
    required this.onThemeChanged,
  });

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  Future<void> _checkLogin() async {
    await Future.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MainPage(
          darkMode: widget.darkMode,
          onThemeChanged: widget.onThemeChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _AnimatedSplashLogo(),
            SizedBox(height: 20),
            Text(
              'EMERGENCY LOCATOR',
              style: TextStyle(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Find help when you need it.',
              style: TextStyle(color: Colors.white70),
            ),
            SizedBox(height: 35),
            CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// LOGIN PAGE
// ============================================================

class LoginPage extends StatefulWidget {
  final bool darkMode;
  final ValueChanged<bool> onThemeChanged;

  const LoginPage({
    super.key,
    required this.darkMode,
    required this.onThemeChanged,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _message(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _authError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-not-found':
      case 'invalid-credential':
      case 'wrong-password':
        return 'Incorrect email or password.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your internet connection.';
      case 'operation-not-allowed':
        return 'Email/Password sign-in is not enabled in Firebase.';
      default:
        return e.message ?? 'Authentication failed. Please try again.';
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      await FirebaseAuth.instance.currentUser?.reload();
      final signedInUser = FirebaseAuth.instance.currentUser;
      if (signedInUser != null && !signedInUser.emailVerified) {
        await FirebaseAuth.instance.signOut();
        _message('Please verify your email first. Open the verification link sent to your inbox, then sign in again.');
        return;
      }
      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => MainPage(
            darkMode: widget.darkMode,
            onThemeChanged: widget.onThemeChanged,
          ),
        ),
            (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      _message(_authError(e));
    } catch (e) {
      _message('Unable to sign in. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreateAccount() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateAccountPage(
          darkMode: widget.darkMode,
          onThemeChanged: widget.onThemeChanged,
        ),
      ),
    );
  }

  Future<void> _openForgotPassword() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ForgotPasswordPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF123B70);
    const blue = Color(0xFF0877E8);
    const pale = Color(0xFFF2F7FF);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF101827) : pale,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                // Soft blue background decorations.
                Positioned(
                  top: -95,
                  right: -70,
                  child: Container(
                    width: 230,
                    height: 230,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: blue.withValues(alpha: isDark ? 0.10 : 0.07),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -110,
                  left: -55,
                  child: Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: blue.withValues(alpha: isDark ? 0.12 : 0.08),
                    ),
                  ),
                ),
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Brand header
                            Row(
                              children: [
                                Container(
                                  width: 54,
                                  height: 54,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [blue, Color(0xFF42A5F5)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: [
                                      BoxShadow(
                                        color: blue.withValues(alpha: 0.22),
                                        blurRadius: 18,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.add_location_alt_rounded,
                                    color: Colors.white,
                                    size: 31,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Emergency Locator',
                                        style: TextStyle(
                                          fontSize: 19,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.4,
                                          color: isDark ? Colors.white : navy,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        'B U L A C A N',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.5,
                                          color: isDark
                                              ? Colors.blue.shade200
                                              : blue,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.shield_outlined,
                                  color: isDark
                                      ? Colors.blue.shade200
                                      : const Color(0xFF5B7CA8),
                                  size: 25,
                                ),
                              ],
                            ),
                            const SizedBox(height: 34),

                            // Map-inspired hero illustration
                            Container(
                              height: 154,
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(26),
                                gradient: LinearGradient(
                                  colors: isDark
                                      ? const [
                                    Color(0xFF142B48),
                                    Color(0xFF1C4777),
                                  ]
                                      : const [
                                    Color(0xFFE4F1FF),
                                    Color(0xFFF5FAFF),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  Positioned(
                                    left: -18,
                                    bottom: -52,
                                    child: Transform.rotate(
                                      angle: -0.24,
                                      child: Container(
                                        width: 260,
                                        height: 110,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(28),
                                          color: blue.withValues(alpha: 0.08),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 24,
                                    top: 15,
                                    child: Icon(
                                      Icons.health_and_safety_rounded,
                                      size: 112,
                                      color: blue.withValues(alpha: 0.09),
                                    ),
                                  ),
                                  Positioned(
                                    right: 42,
                                    bottom: 16,
                                    child: Container(
                                      width: 76,
                                      height: 76,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: blue.withValues(alpha: 0.10),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 58,
                                    bottom: 31,
                                    child: const Icon(
                                      Icons.location_on_rounded,
                                      size: 54,
                                      color: blue,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(20, 18, 115, 16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'FIND HELP.',
                                          style: TextStyle(
                                            color: isDark
                                                ? Colors.blue.shade100
                                                : const Color(0xFF41648F),
                                            fontWeight: FontWeight.w800,
                                            fontSize: 11,
                                            letterSpacing: 1.4,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          'Stay safe,\nwherever you are.',
                                          style: TextStyle(
                                            color: isDark ? Colors.white : navy,
                                            fontSize: 21,
                                            height: 1.15,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Emergency support in Bulacan',
                                          style: TextStyle(
                                            color: isDark
                                                ? Colors.white70
                                                : const Color(0xFF58769B),
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 28),

                            Text(
                              'Welcome back!',
                              textAlign: TextAlign.left,
                              style: TextStyle(
                                fontSize: 31,
                                height: 1.12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.8,
                                color: isDark ? Colors.white : navy,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Sign in to continue to your Emergency Locator.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: isDark ? Colors.white70 : const Color(0xFF60738D),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Email field
                            _LoginInputShell(
                              child: TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  hintText: 'Email address',
                                  prefixIcon: Icon(Icons.mail_outline_rounded),
                                  border: InputBorder.none,
                                  filled: false,
                                  contentPadding: EdgeInsets.symmetric(vertical: 18),
                                ),
                                validator: (value) {
                                  final email = value?.trim() ?? '';
                                  if (email.isEmpty) return 'Email is required.';
                                  if (!email.contains('@') || !email.contains('.')) {
                                    return 'Enter a valid email address.';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(height: 13),

                            // Password field
                            _LoginInputShell(
                              child: TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                autofillHints: const [AutofillHints.password],
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _login(),
                                decoration: InputDecoration(
                                  hintText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                                  suffixIcon: IconButton(
                                    tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                  border: InputBorder.none,
                                  filled: false,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 18),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Password is required.';
                                  }
                                  return null;
                                },
                              ),
                            ),

                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _loading ? null : _openForgotPassword,
                                child: const Text('Forgot password?'),
                              ),
                            ),
                            const SizedBox(height: 4),

                            // Sign-in action
                            SizedBox(
                              height: 56,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF1688F8), Color(0xFF075BC8)],
                                  ),
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: blue.withValues(alpha: 0.24),
                                      blurRadius: 17,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: FilledButton(
                                  onPressed: _loading ? null : _login,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    disabledBackgroundColor: Colors.blueGrey,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  child: _loading
                                      ? const SizedBox(
                                    width: 23,
                                    height: 23,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Colors.white,
                                    ),
                                  )
                                      : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Sign In',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                        ),
                                      ),
                                      SizedBox(width: 10),
                                      Icon(Icons.arrow_forward_rounded, size: 20),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),

                            Row(
                              children: [
                                Expanded(child: Divider(color: isDark ? Colors.white24 : const Color(0xFFD2DFEF))),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(
                                    'OR',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: isDark ? Colors.white54 : const Color(0xFF8799B0),
                                    ),
                                  ),
                                ),
                                Expanded(child: Divider(color: isDark ? Colors.white24 : const Color(0xFFD2DFEF))),
                              ],
                            ),
                            const SizedBox(height: 12),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text(
                                    "Don't have an account?",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? Colors.white70 : const Color(0xFF718198),
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _loading ? null : _openCreateAccount,
                                  child: const Text(
                                    'Create Account',
                                    style: TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Small trust indicators
                            Row(
                              children: [
                                _LoginBenefit(
                                  icon: Icons.verified_user_outlined,
                                  label: 'Safer\ncommunities',
                                  dark: isDark,
                                ),
                                _LoginBenefit(
                                  icon: Icons.near_me_outlined,
                                  label: 'Quick\naccess',
                                  dark: isDark,
                                ),
                                _LoginBenefit(
                                  icon: Icons.favorite_border_rounded,
                                  label: 'Emergency\nsupport',
                                  dark: isDark,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LoginInputShell extends StatelessWidget {
  final Widget child;

  const _LoginInputShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1B2638) : Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: dark ? Colors.white12 : const Color(0xFFDCE7F6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.05 : 0.025),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _LoginBenefit extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool dark;

  const _LoginBenefit({
    required this.icon,
    required this.label,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(
            icon,
            size: 23,
            color: dark ? Colors.blue.shade200 : const Color(0xFF6D8CB5),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              height: 1.2,
              color: dark ? Colors.white60 : const Color(0xFF7187A3),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// CREATE ACCOUNT
// ============================================================

class CreateAccountPage extends StatefulWidget {
  final bool darkMode;
  final ValueChanged<bool> onThemeChanged;

  const CreateAccountPage({
    super.key,
    required this.darkMode,
    required this.onThemeChanged,
  });

  @override
  State<CreateAccountPage> createState() => _CreateAccountPageState();
}

class _CreateAccountPageState extends State<CreateAccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _message(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final credential =
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      final name = _nameController.text.trim();

      if (name.isNotEmpty) {
        await credential.user?.updateDisplayName(name);
      }
      await credential.user?.sendEmailVerification();
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;
      _message('Account created. Check your email and verify your account before signing in.');
      Navigator.of(context).pop();
      return;

    } on FirebaseAuthException catch (e) {
      String message;

      switch (e.code) {
        case 'email-already-in-use':
          message = 'This email already has an account.';
          break;
        case 'invalid-email':
          message = 'Please enter a valid email address.';
          break;
        case 'weak-password':
          message = 'Use a stronger password with at least 6 characters.';
          break;
        case 'operation-not-allowed':
          message = 'Enable Email/Password in Firebase Authentication.';
          break;
        default:
          message = e.message ?? 'Unable to create account.';
      }

      _message(message);
    } catch (e) {
      _message('Unable to create account. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.person_add_alt_1_rounded,
                      size: 68,
                      color: Color(0xFF1565C0),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Create your account',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Full name (optional)',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (email.isEmpty || !email.contains('@')) {
                          return 'Enter a valid email address.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.length < 6) {
                          return 'Password must be at least 6 characters.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm password',
                        prefixIcon: Icon(Icons.lock_reset_outlined),
                      ),
                      validator: (value) {
                        if (value != _passwordController.text) {
                          return 'Passwords do not match.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _loading ? null : _createAccount,
                        child: _loading
                            ? const CircularProgressIndicator()
                            : const Text('Create Account'),
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

// ============================================================
// FORGOT PASSWORD
// ============================================================

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetEmail() async {
    final email = _emailController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid email address.')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'If the account exists, a password reset email will be sent.',
          ),
        ),
      );
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      final message = e.code == 'invalid-email'
          ? 'Enter a valid email address.'
          : 'Unable to send reset email. Please try again.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot Password')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.mark_email_unread_outlined,
                  size: 75,
                  color: Color(0xFF1565C0),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Reset your password',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Enter the email address associated with your account.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email address',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _loading ? null : _sendResetEmail,
                    child: _loading
                        ? const CircularProgressIndicator()
                        : const Text('Send Reset Email'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// EMERGENCY CATEGORIES
// ============================================================

class AdminReportReviewPage extends StatelessWidget {
  const AdminReportReviewPage({super.key});

  Future<void> _setStatus(BuildContext context, String id, String status) async {
    try {
      await FirebaseFirestore.instance.collection('reports').doc(id).update({
        'status': status,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': FirebaseAuth.instance.currentUser?.uid,
      });
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Report marked $status.')));
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to update report. Check admin custom claim and Firestore rules.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin report review')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('reports').where('status', isEqualTo: 'pending').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Unable to load reports. Confirm admin access and Firestore rules.')));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('No pending reports.'));
          return ListView.separated(
            padding: const EdgeInsets.all(12), itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final doc = docs[index]; final data = doc.data();
              final location = data['location'] as Map<String, dynamic>?;
              return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((data['category'] ?? 'Report').toString(), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6), Text((data['description'] ?? '').toString()),
                const SizedBox(height: 6), Text('Area: ${(data['area'] ?? 'Not provided')}'),
                Text('Submitted by: ${(data['userEmail'] ?? 'Unknown')}'),
                if (location != null) Text('Coordinates: ${location['latitude']}, ${location['longitude']}'),
                const SizedBox(height: 12),
                Wrap(spacing: 8, children: [
                  OutlinedButton.icon(onPressed: () => _setStatus(context, doc.id, 'rejected'), icon: const Icon(Icons.close_rounded), label: const Text('Reject')),
                  FilledButton.icon(onPressed: () => _setStatus(context, doc.id, 'verified'), icon: const Icon(Icons.verified_rounded), label: const Text('Mark verified')),
                ]),
              ])));
            },
          );
        },
      ),
    );
  }
}

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final reports = FirebaseFirestore.instance.collection('reports');
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Dashboard')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: reports.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Unable to load report statistics. Check Firestore rules and admin permissions.')));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;
          int count(String status) => docs.where((d) => (d.data()['status'] ?? 'pending').toString().toLowerCase() == status).length;
          return ListView(padding: const EdgeInsets.all(16), children: [
            const Text('Community report overview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Counts update from Firestore. Keep admin access restricted and avoid exposing personal details.'),
            const SizedBox(height: 16),
            _AdminStatCard(title: 'All reports', count: docs.length, icon: Icons.assignment_outlined),
            _AdminStatCard(title: 'Pending', count: count('pending'), icon: Icons.hourglass_top, color: Colors.orange),
            _AdminStatCard(title: 'Verified', count: count('verified'), icon: Icons.verified_outlined, color: Colors.green),
            _AdminStatCard(title: 'Rejected', count: count('rejected'), icon: Icons.cancel_outlined, color: Colors.red),
            const SizedBox(height: 12),
            const Text('This dashboard summarizes report records only; it does not represent verified live incidents unless an authorized reviewer has checked them.'),
          ]);
        },
      ),
    );
  }
}

class _AdminStatCard extends StatelessWidget {
  const _AdminStatCard({required this.title, required this.count, required this.icon, this.color});
  final String title;
  final int count;
  final IconData icon;
  final Color? color;
  @override
  Widget build(BuildContext context) => Card(child: ListTile(leading: Icon(icon, color: color), title: Text(title), trailing: Text('$count', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold))));
}

class EmergencyCategory {
  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final String overpassFilter;

  const EmergencyCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.overpassFilter,
  });
}

const List<EmergencyCategory> emergencyCategories = [
  EmergencyCategory(
    id: 'hospital',
    name: 'Hospital',
    icon: Icons.local_hospital_rounded,
    color: Colors.red,
    overpassFilter: '["amenity"="hospital"]',
  ),
  EmergencyCategory(
    id: 'emergency',
    name: 'Emergency',
    icon: Icons.emergency_rounded,
    color: Colors.deepOrange,
    overpassFilter: '["emergency"="ambulance_station"]',
  ),
  EmergencyCategory(
    id: 'police',
    name: 'Police',
    icon: Icons.local_police_rounded,
    color: Colors.blue,
    overpassFilter: '["amenity"="police"]',
  ),
  EmergencyCategory(
    id: 'fire',
    name: 'Fire Station',
    icon: Icons.fire_truck_rounded,
    color: Colors.orange,
    overpassFilter: '["amenity"="fire_station"]',
  ),
  EmergencyCategory(
    id: 'hotel',
    name: 'Hotel',
    icon: Icons.hotel_rounded,
    color: Colors.purple,
    overpassFilter: '["tourism"="hotel"]',
  ),
  EmergencyCategory(
    id: 'evacuation',
    name: 'Evacuation',
    icon: Icons.shield_rounded,
    color: Colors.teal,
    overpassFilter: '["amenity"="shelter"]',
  ),
];

class EmergencyPlace {
  final String name;
  final String type;
  final LatLng point;

  const EmergencyPlace({
    required this.name,
    required this.type,
    required this.point,
  });
}

// ============================================================
// MAIN MAP PAGE
// ============================================================

class MainPage extends StatefulWidget {
  final bool darkMode;
  final ValueChanged<bool> onThemeChanged;

  const MainPage({
    super.key,
    required this.darkMode,
    required this.onThemeChanged,
  });

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  static const LatLng _bulacanCenter = LatLng(14.8430, 120.8110);

  LatLng _mapCenter = _bulacanCenter;
  EmergencyCategory _selectedCategory = emergencyCategories.first;

  List<EmergencyPlace> _places = [];
  bool _loading = false;
  bool _showSettings = false;
  String _area = 'Malolos, Bulacan';
  String _status = 'Search for nearby emergency locations.';
  Timer? _searchDebounce;
  final Set<String> _favoriteKeys = <String>{};
  bool _showFavoritesOnly = false;
  bool _sortNearestFirst = true;
  int _requestToken = 0;
  Position? _gpsPosition;
  EmergencyPlace? _emergencyTarget;
  bool _gpsLoading = false;
  String _gpsStatus = 'Location not checked yet';
  double? _gpsAccuracyMeters;
  bool _locationPermissionGranted = false;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _loadCachedPlaces();
    _searchPlaces();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  String _placeCacheKey() => 'cached_places_${_selectedCategory.id}';

  Future<void> _loadCachedPlaces() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_placeCacheKey());
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List<dynamic>;
      final cached = list.map((item) {
        final m = item as Map<String, dynamic>;
        return EmergencyPlace(
          name: m['name'] as String,
          type: m['type'] as String,
          point: LatLng((m['lat'] as num).toDouble(), (m['lon'] as num).toDouble()),
        );
      }).toList();
      if (!mounted || _places.isNotEmpty) return;
      setState(() {
        _places = cached;
        _status = 'Offline saved results shown. Connect to the internet to refresh facility data.';
      });
    } catch (_) {
      // A corrupt cache should never prevent the map from opening.
    }
  }

  Future<void> _saveCachedPlaces(List<EmergencyPlace> places) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_placeCacheKey(), jsonEncode(places.map((p) => {
        'name': p.name, 'type': p.type,
        'lat': p.point.latitude, 'lon': p.point.longitude,
      }).toList()));
      await prefs.setString('cached_places_last_updated', DateTime.now().toIso8601String());
    } catch (_) {}
  }

  Future<void> _refreshGpsLocation() async {
    if (_gpsLoading) return;
    setState(() { _gpsLoading = true; _gpsStatus = 'Checking GPS location...'; });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _gpsStatus = 'Location services are off. Turn on GPS in phone settings.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final accepted = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.location_on_rounded, size: 42, color: Color(0xFF1565C0)),
            title: const Text('Allow location access?'),
            content: const Text('Emergency Locator uses your location to center the map and help find nearby emergency facilities. Your location is not automatically sent to emergency services.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Not now')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Continue')),
            ],
          ),
        );
        if (accepted != true) {
          setState(() => _gpsStatus = 'Location permission was not granted. You can still search manually.');
          return;
        }
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        setState(() => _gpsStatus = 'Location permission denied. Search by municipality instead.');
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() => _gpsStatus = 'Location permission is blocked. Enable it in app settings.');
        if (mounted) {
          await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
            title: const Text('Location permission blocked'),
            content: const Text('Open app settings and allow location access to use GPS features.'),
            actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')), FilledButton(onPressed: () async { Navigator.pop(dialogContext); await Geolocator.openAppSettings(); }, child: const Text('Open settings'))],
          ));
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
      if (!mounted) return;
      setState(() {
        _gpsPosition = position;
        _gpsAccuracyMeters = position.accuracy;
        _mapCenter = LatLng(position.latitude, position.longitude);
        _gpsStatus = 'Location updated • ±${position.accuracy.toStringAsFixed(0)} m accuracy';
        _locationPermissionGranted = true;
      });
      _mapController.move(_mapCenter, 13);
      _showMessage('GPS location refreshed. Accuracy: ±${position.accuracy.toStringAsFixed(0)} m. Searching nearby facilities...');
      await _searchPlaces();
    } on TimeoutException {
      if (mounted) setState(() => _gpsStatus = 'GPS timed out. Move to an open area and refresh again.');
    } catch (_) {
      if (mounted) setState(() => _gpsStatus = 'Could not get GPS location. Check phone location settings.');
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  Future<void> _openOfflineContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    var contacts = prefs.getStringList('offline_emergency_contacts') ?? <String>[];
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 24),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Offline emergency contacts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6), const Text('These contacts are saved on this device and remain available offline.'),
          const SizedBox(height: 14),
          TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Contact name', prefixIcon: Icon(Icons.person_outline))),
          const SizedBox(height: 10),
          TextField(controller: phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number', prefixIcon: Icon(Icons.phone_outlined))),
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: () async {
            final name = nameController.text.trim(); final phone = phoneController.text.trim();
            if (name.isEmpty || phone.isEmpty) return;
            final next = [...contacts, '$name|$phone'];
            await prefs.setStringList('offline_emergency_contacts', next);
            setSheetState(() { contacts = next; nameController.clear(); phoneController.clear(); });
          }, icon: const Icon(Icons.add), label: const Text('Save contact')),
          const SizedBox(height: 12),
          if (contacts.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No contacts saved yet.')),
          ...contacts.asMap().entries.map((entry) {
            final parts = entry.value.split('|'); final name = parts.first; final phone = parts.length > 1 ? parts.sublist(1).join('|') : '';
            return ListTile(leading: const CircleAvatar(child: Icon(Icons.contact_phone)), title: Text(name), subtitle: Text(phone), trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { final next = [...contacts]..removeAt(entry.key); await prefs.setStringList('offline_emergency_contacts', next); setSheetState(() => contacts = next); }));
          }),
        ])),
      )),
    );
    nameController.dispose(); phoneController.dispose();
  }

  Future<void> _openReportForm() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !user.emailVerified) {
      _showMessage('Please sign in with a verified email to submit a report.');
      return;
    }
    final descriptionController = TextEditingController();
    var category = 'Incorrect facility information';
    var sending = false;
    await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: const Text('Report an issue'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Reports are reviewed before they are treated as verified information.'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: category, decoration: const InputDecoration(labelText: 'Report category'), items: const [
          DropdownMenuItem(value: 'Incorrect facility information', child: Text('Incorrect facility information')),
          DropdownMenuItem(value: 'Closed or moved facility', child: Text('Closed or moved facility')),
          DropdownMenuItem(value: 'Suspicious or abusive report', child: Text('Suspicious or abusive report')),
          DropdownMenuItem(value: 'Other', child: Text('Other')),
        ], onChanged: (value) { if (value != null) setDialogState(() => category = value); }),
        const SizedBox(height: 12),
        TextField(controller: descriptionController, minLines: 3, maxLines: 5, maxLength: 700, decoration: const InputDecoration(labelText: 'Details', hintText: 'Explain what should be checked')),
      ])),
      actions: [
        TextButton(onPressed: sending ? null : () => Navigator.pop(dialogContext), child: const Text('Cancel')),
        FilledButton(onPressed: sending ? null : () async {
          final description = descriptionController.text.trim();
          if (description.length < 10) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please provide at least 10 characters of detail.'))); return; }
          setDialogState(() => sending = true);
          try {
            await FirebaseFirestore.instance.collection('reports').add({
              'category': category, 'description': description,
              'userId': user.uid, 'userEmail': user.email,
              'status': 'pending', 'createdAt': FieldValue.serverTimestamp(),
              'area': _area,
              if (_gpsPosition != null) 'location': {'latitude': _gpsPosition!.latitude, 'longitude': _gpsPosition!.longitude},
            });
            if (dialogContext.mounted) Navigator.pop(dialogContext);
            _showMessage('Report submitted for review. Thank you.');
          } catch (_) {
            setDialogState(() => sending = false);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not submit report. Check Firestore setup and internet connection.')));
          }
        }, child: sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Submit for review')),
      ],
    )));
    descriptionController.dispose();
  }

  Future<void> _openAdminReview() async {
    final user = FirebaseAuth.instance.currentUser;
    final claims = await user?.getIdTokenResult(true);
    if (claims?.claims?['admin'] != true) {
      _showMessage('Admin access is not enabled for this account.');
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminReportReviewPage()));
  }

  Future<void> _openMyReports() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true, builder: (context) => SafeArea(child: SizedBox(height: MediaQuery.of(context).size.height * .65, child: Column(children: [
      const Padding(padding: EdgeInsets.all(16), child: Text('My submitted reports', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
      Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('reports').where('userId', isEqualTo: user.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Could not load reports. Check Firestore rules.')));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs.toList()..sort((a,b) => ((b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0).compareTo((a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
          if (docs.isEmpty) return const Center(child: Text('No reports submitted yet.'));
          return ListView.builder(itemCount: docs.length, itemBuilder: (context, index) { final data = docs[index].data(); final status = (data['status'] ?? 'pending').toString(); return ListTile(leading: Icon(status == 'verified' ? Icons.verified : status == 'rejected' ? Icons.cancel_outlined : Icons.hourglass_top_rounded), title: Text((data['category'] ?? 'Report').toString()), subtitle: Text((data['description'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis), trailing: Chip(label: Text(status))); });
        },
      )),
    ]))));
  }

  String _favoriteKey(EmergencyPlace place) =>
      '${place.name}|${place.point.latitude.toStringAsFixed(5)}|${place.point.longitude.toStringAsFixed(5)}';

  double _distanceKm(EmergencyPlace place) =>
      const Distance().as(LengthUnit.Kilometer, _mapCenter, place.point);

  List<EmergencyPlace> get _visiblePlaces {
    final visible = _places.where((place) =>
    !_showFavoritesOnly || _favoriteKeys.contains(_favoriteKey(place))).toList();
    if (_sortNearestFirst) {
      visible.sort((a, b) => _distanceKm(a).compareTo(_distanceKm(b)));
    }
    return visible;
  }

  Future<void> _loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() => _favoriteKeys.addAll(prefs.getStringList('favorite_places') ?? []));
    } catch (_) {
      // Favorites are optional; the map should still work if storage is unavailable.
    }
  }

  Future<void> _toggleFavorite(EmergencyPlace place) async {
    final key = _favoriteKey(place);
    setState(() {
      if (!_favoriteKeys.add(key)) _favoriteKeys.remove(key);
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('favorite_places', _favoriteKeys.toList());
    } catch (_) {}
    _showMessage(_favoriteKeys.contains(key) ? 'Added to favorites.' : 'Removed from favorites.');
  }

  Future<void> _openDirections(EmergencyPlace place) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${place.point.latitude},${place.point.longitude}',
    );
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) _showMessage('Could not open directions. Please try again.');
    } catch (_) {
      _showMessage('Could not open directions. Check that a browser is available.');
    }
  }

  void _showPlaceDetails(EmergencyPlace place) {
    final favorite = _favoriteKeys.contains(_favoriteKey(place));
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: false,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(
                  backgroundColor: _selectedCategory.color.withOpacity(.12),
                  child: Icon(_selectedCategory.icon, color: _selectedCategory.color),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(place.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
              ]),
              const SizedBox(height: 8),
              Text(place.type, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.near_me_outlined, size: 16),
                  const SizedBox(width: 6),
                  Text('${_distanceKm(place).toStringAsFixed(1)} km from map center'),
                ],
              ),
              const SizedBox(height: 5),
              Text('Coordinates: ${place.point.latitude.toStringAsFixed(5)}, ${place.point.longitude.toStringAsFixed(5)}', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFD92736),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _showFacilitySos(place);
                  },
                  icon: const Icon(Icons.sos_rounded),
                  label: const Text('SOS / Emergency options'),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: () { Navigator.pop(sheetContext); _toggleFavorite(place); },
                  icon: Icon(favorite ? Icons.favorite : Icons.favorite_border),
                  label: Text(favorite ? 'Saved' : 'Favorite'),
                )),
                const SizedBox(width: 10),
                Expanded(child: FilledButton.icon(
                  onPressed: () { Navigator.pop(sheetContext); _openDirections(place); },
                  icon: const Icon(Icons.directions),
                  label: const Text('Directions'),
                )),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    var isAdmin = false;
    try { isAdmin = (await user?.getIdTokenResult(true))?.claims?['admin'] == true; } catch (_) {}
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.82,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                20 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 34,
                    child: Text(
                      (user?.email?.isNotEmpty == true ? user!.email![0] : 'U').toUpperCase(),
                      style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    user?.displayName ?? 'My Profile',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(user?.email ?? 'Signed-in user', textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  Chip(
                    avatar: Icon(
                      user?.emailVerified == true ? Icons.verified_user : Icons.warning_amber_rounded,
                      size: 17,
                    ),
                    label: Text(user?.emailVerified == true ? 'Email verified' : 'Email not verified'),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.contacts_outlined),
                    title: const Text('Offline emergency contacts'),
                    onTap: () { Navigator.pop(sheetContext); _openOfflineContacts(); },
                  ),
                  ListTile(leading: const Icon(Icons.medical_services_outlined), title: const Text('First Aid Guide'), onTap: () { Navigator.pop(sheetContext); _openFirstAidGuide(); }),
                  ListTile(leading: const Icon(Icons.warning_amber_rounded), title: const Text('Disaster Alerts'), subtitle: const Text('Official alert sources'), onTap: () { Navigator.pop(sheetContext); _openDisasterAlerts(); }),
                  ListTile(leading: const Icon(Icons.history), title: const Text('Search History'), onTap: () { Navigator.pop(sheetContext); _openSearchHistory(); }),
                  ListTile(
                    leading: const Icon(Icons.report_outlined),
                    title: const Text('Report an issue'),
                    onTap: () { Navigator.pop(sheetContext); _openReportForm(); },
                  ),
                  ListTile(
                    leading: const Icon(Icons.assignment_outlined),
                    title: const Text('My reports'),
                    onTap: () { Navigator.pop(sheetContext); _openMyReports(); },
                  ),
                  if (isAdmin)
                    ListTile(
                      leading: const Icon(Icons.admin_panel_settings_outlined),
                      title: const Text('Admin report review'),
                      subtitle: const Text('Review pending community reports'),
                      onTap: () { Navigator.pop(sheetContext); _openAdminReview(); },
                    ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.favorite_outline),
                    title: const Text('Saved places'),
                    trailing: Text('${_favoriteKeys.length}'),
                  ),
                  ListTile(leading: const Icon(Icons.family_restroom), title: const Text('Family Safety Check-In'), onTap: () { Navigator.pop(sheetContext); _openFamilySafetyCheckIn(); }),
                  ListTile(leading: const Icon(Icons.location_city), title: const Text('Evacuation Center Locator'), subtitle: const Text('Search map data; verify with local authorities'), onTap: () { Navigator.pop(sheetContext); _openEvacuationCenters(); }),
                  ListTile(leading: const Icon(Icons.accessibility_new), title: const Text('Accessibility & Language'), onTap: () { Navigator.pop(sheetContext); _openAccessibilitySettings(); }),
                  ListTile(leading: const Icon(Icons.admin_panel_settings_outlined), title: const Text('Admin Dashboard'), onTap: () { Navigator.pop(sheetContext); _openAdminDashboard(); }),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.dark_mode_outlined),
                    title: const Text('Dark mode'),
                    value: widget.darkMode,
                    onChanged: (value) { Navigator.pop(sheetContext); widget.onThemeChanged(value); },
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text('Log out'),
                    onTap: () { Navigator.pop(sheetContext); _logout(); },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openFirstAidGuide() async {
    final guides = <Map<String, String>>[
      {
        'title': 'Severe bleeding / sugat at hiwa',
        'steps': '1. Siguraduhing ligtas ang lugar at magsuot ng gloves kung mayroon.\n2. Idiin nang tuloy-tuloy ang malinis na gauze o tela sa sugat.\n3. Kung may nakabaong bagay, huwag bunutin; idiin sa paligid nito.\n4. Tumawag sa emergency services kung malakas ang pagdurugo, malalim ang sugat, o hindi humihinto.\n5. Huwag maglagay ng alcohol o pulbos sa malalim na sugat.'
      },
      {
        'title': 'Burns / paso',
        'steps': '1. Ilayo sa pinagmumulan ng init.\n2. Palamigin sa malamig na umaagos na tubig nang 20 minuto kung kaya.\n3. Alisin ang alahas o masikip na bagay malapit sa paso bago mamaga.\n4. Takpan nang maluwag ng malinis na non-fluffy dressing.\n5. Huwag lagyan ng yelo, toothpaste, mantika o butter; huwag pumutok ng paltos. Magpa-emergency care kung malaki, malalim, o nasa mukha, kamay, ari, o daanan ng hangin.'
      },
      {
        'title': 'Hirap huminga / atake ng hika',
        'steps': '1. Paupuin nang tuwid at pakalmahin; huwag piliting humiga.\n2. Tulungan gamitin ang sariling prescribed reliever inhaler ayon sa action plan o label.\n3. Luwagan ang masikip na damit at ilayo sa usok o trigger.\n4. Tumawag agad sa emergency services kung hirap magsalita, nangingitim/asul ang labi, lumalala, o hindi gumagaan matapos ang reliever.\n5. Huwag magbigay ng pagkain o inumin habang hirap huminga.'
      },
      {
        'title': 'Heat exhaustion at heat stroke',
        'steps': '1. Ilipat sa lilim o malamig na lugar at alisin ang sobrang damit.\n2. Palamigin gamit ang basang malamig na tela, bentilador, at cold packs na nakabalot sa tela.\n3. Kung gising na gising at hindi nasusuka, painumin ng paunti-unting tubig.\n4. Ang pagkalito, kombulsyon, pagkawala ng malay, o sobrang init ng katawan ay posibleng heat stroke: emergency ito. Tumawag agad at mabilis na palamigin.\n5. Huwag painumin ang nalilito o walang malay.'
      },
      {
        'title': 'Pagkalunod',
        'steps': '1. Huwag tumalon sa tubig kung hindi ligtas o hindi trained; gumamit ng lubid, salbabida o mahabang bagay mula sa ligtas na lugar.\n2. Kapag nailabas, tumawag sa emergency services.\n3. Kung hindi responsive at hindi humihinga nang normal, simulan ang CPR/rescue breaths kung trained at sundin ang dispatcher.\n4. Kung humihinga, panatilihing mainit at bantayan ang paghinga.\n5. Kailangan ng agarang medical assessment kahit mukhang bumuti.'
      },
      {
        'title': 'Kagat ng aso / posibleng rabies',
        'steps': '1. Hugasan agad ang sugat sa umaagos na tubig at sabon nang 15 minuto.\n2. Kung mayroon, lagyan ng povidone-iodine pagkatapos maghugas.\n3. Huwag lagyan ng sili, bawang, langis o ibang home remedy at huwag takpan nang mahigpit.\n4. Pumunta agad sa Animal Bite Treatment Center/health facility para masuri ang rabies vaccine at immunoglobulin. Huwag hintayin ang sintomas.\n5. Kung malakas ang pagdurugo, idiin ng malinis na tela at magpa-emergency care.'
      },
      {
        'title': 'Kagat ng ahas',
        'steps': '1. Ilayo ang tao sa ahas; huwag subukang hulihin o patayin ito.\n2. Panatilihing kalmado at hindi gumagalaw ang biktima; suportahan at i-immobilize ang nakagat na bahagi.\n3. Alisin ang singsing o masikip na bagay bago mamaga.\n4. Dalhin agad sa ospital o tumawag sa emergency services.\n5. Huwag hiwain, sipsipin, lagyan ng yelo, itali nang mahigpit, o maglagay ng tourniquet.'
      },
      {
        'title': 'Pagkalason sa pagkain',
        'steps': '1. Painumin ng maliliit at madalas na lagok ng oral rehydration solution (ORS) kung gising at kayang lumunok.\n2. Iwasan ang alak at huwag piliting kumain.\n3. Huwag pasukahin o basta magbigay ng antibiotic/anti-diarrhea medicine nang walang payo ng health professional.\n4. Magpatingin agad kung may dugo sa dumi, mataas na lagnat, matinding sakit, tuloy-tuloy na pagsusuka, dehydration, o kung sanggol/matanda/buntis.\n5. Emergency kung nahihirapang huminga, nalilito, o walang malay.'
      },
      {
        'title': 'Dengue warning signs',
        'steps': '1. Magpatingin sa health facility kung may lagnat at pinaghihinalaang dengue; uminom ng fluids kung kaya.\n2. Babala: matinding sakit ng tiyan, tuloy-tuloy na pagsusuka, pagdurugo ng ilong/gilagid, dugo sa suka o dumi, mabilis na paghinga, matinding panghihina, malamig/maputlang balat, o pagiging balisa/antukin.\n3. Sa warning signs, mag-emergency care agad.\n4. Iwasan ang aspirin at ibuprofen maliban kung iniutos ng doktor dahil maaaring tumaas ang pagdurugo; itanong sa clinician ang ligtas na gamot sa lagnat.\n5. Huwag hintaying bumalik ang lagnat bago magpatingin.'
      },
      {
        'title': 'Lindol: bago, habang, pagkatapos',
        'steps': 'BAGO: ihanda ang go-bag, tubig, gamot, flashlight, at family meeting point; ikabit nang maayos ang mabibigat na gamit.\nHABANG: Duck, Cover, and Hold On—dumapa, sumilong sa matibay na mesa, at kumapit; lumayo sa bintana. Huwag gumamit ng elevator.\nPAGKATAPOS: asahan ang aftershocks, tingnan kung may sugatan at panganib ng sunog/gas, lumabas sa ligtas na ruta kung kailangan, at makinig sa opisyal na abiso. Huwag pumasok sa sirang gusali.'
      },
      {
        'title': 'Baha at bagyo',
        'steps': '1. Sundin ang evacuation order at opisyal na PAGASA/LGU advisories.\n2. Lumipat sa mataas at ligtas na lugar bago tumaas ang tubig.\n3. Huwag maglakad, lumangoy o magmaneho sa baha; maaaring malalim, mabilis, o may live electrical wires.\n4. Patayin ang kuryente lamang kung ligtas at tuyo ang lugar; huwag humawak ng basang electrical equipment.\n5. Magdala ng go-bag, gamot, tubig, ID at phone; iwasan ang baybayin at ilog kapag may babala.'
      },
      {
        'title': 'Sunog',
        'steps': '1. Sumigaw ng babala, lumabas agad gamit ang pinakamalapit na ligtas na exit at tumawag sa fire service mula sa ligtas na lugar.\n2. Manatiling mababa kung may usok; huwag gumamit ng elevator at huwag bumalik para sa gamit.\n3. Kung nasusunog ang damit, STOP, DROP, and ROLL; palamigin ang paso sa umaagos na tubig.\n4. Gumamit lamang ng fire extinguisher kung maliit ang apoy, trained ka, at may ligtas na exit sa likod mo.\n5. Huwag buhusan ng tubig ang grease o electrical fire.'
      },
      {
        'title': 'Atake sa puso',
        'steps': '1. Tumawag agad sa emergency services kung may pressure/sakit sa dibdib, hingal, malamig na pawis, pagduduwal, o sakit na kumakalat sa braso, likod, leeg o panga.\n2. Paupuin at ipahinga; luwagan ang damit at huwag hayaang maglakad.\n3. Huwag ihatid mag-isa kung maaaring dumating ang ambulance.\n4. Aspirin ay ibigay lamang kung inirerekomenda ng dispatcher/health professional at walang allergy o bawal na kondisyon.\n5. Kung mawalan ng malay at hindi humihinga nang normal, simulan ang CPR kung kaya at gumamit ng AED kung mayroon.'
      },
      {
        'title': 'Seizure / kombulsyon',
        'steps': '1. Ilayo ang matutulis at matitigas na bagay; lagyan ng malambot na suporta sa ulo.\n2. Huwag pigilan ang paggalaw at huwag maglagay ng kahit ano sa bibig.\n3. Orasan ang tagal. Kapag huminto, ihiga patagilid kung humihinga at bantayan.\n4. Tumawag sa emergency services kung lampas 5 minuto, paulit-ulit, unang seizure, may injury, buntis, nangyari sa tubig, o hirap huminga.\n5. Huwag magbigay ng pagkain, tubig o gamot sa bibig hanggang lubos na gising.'
      },
      {
        'title': 'Allergic reaction / anaphylaxis',
        'steps': '1. Kung may hirap huminga, pamamaga ng dila/lalamunan, pamamaos, panghihina o pagkahimatay pagkatapos ng allergen, tumawag agad sa emergency services.\n2. Tulungan gamitin ang sariling prescribed epinephrine auto-injector sa panlabas na hita ayon sa device instructions.\n3. Ihiga kung maaari; kung hirap huminga, maaaring umupo nang suportado. Huwag patayuin o palakarin.\n4. Kung hindi bumuti at may second prescribed injector, sundin ang emergency dispatcher/device instructions.\n5. Kailangan ng emergency assessment kahit bumuti na.'
      },
      {
        'title': 'Bali ng buto / sprain',
        'steps': '1. Huwag piliting ituwid o ibalik sa puwesto.\n2. Panatilihing hindi gumagalaw ang bahagi sa posisyong natagpuan; suportahan ng padding o splint kung marunong.\n3. Lagyan ng cold pack na nakabalot sa tela nang hanggang 20 minuto.\n4. Alisin ang singsing o relo bago mamaga.\n5. Emergency kung bukas ang bali, may deformity, pamamanhid, malamig/asul na daliri, o malubhang injury.'
      },
      {
        'title': 'Nosebleed / pagdurugo ng ilong',
        'steps': '1. Paupuin at iyuko nang bahagya ang ulo pasulong.\n2. Pisilin ang malambot na bahagi ng ilong nang tuloy-tuloy sa loob ng 10–15 minuto habang humihinga sa bibig.\n3. Huwag itingala ang ulo at huwag humiga.\n4. Mag-emergency care kung malakas ang dugo, hirap huminga, matapos ang injury sa ulo, o hindi humihinto matapos ang tuloy-tuloy na pressure.'
      },
      {
        'title': 'Nabulunan ang sanggol (wala pang 1 taon)',
        'steps': '1. Kung umuubo o umiiyak nang malakas, hayaan at bantayan; huwag magsagawa ng thrusts kung epektibo ang ubo.\n2. Kung hindi makahinga/umiiyak/umuubo nang epektibo, tumawag o magpatawag ng emergency help.\n3. Para sa trained rescuer: salit-salitang 5 back blows at 5 chest thrusts ayon sa infant choking first-aid training.\n4. Huwag magsagawa ng abdominal thrusts sa sanggol at huwag kapain nang bulag ang bibig.\n5. Kung mawalan ng malay, ibaba sa matigas na patungan at simulan ang infant CPR ayon sa training at dispatcher instructions.'
      },
      {
        'title': 'Pagkaputol ng bahagi ng katawan',
        'steps': '1. Tumawag agad sa emergency services at kontrolin ang pagdurugo sa natitirang bahagi gamit ang matatag na direktang pressure.\n2. I-wrap ang naputol na bahagi sa malinis na bahagyang basang gauze, ilagay sa selyadong plastic bag, at ilagay ang bag sa yelo/tubig na malamig—huwag direktang idikit sa yelo o ilubog sa tubig.\n3. Huwag kuskusin o linisin nang marahas.\n4. Dalhin ang bahagi kasama ng pasyente sa ospital; huwag ipagpaliban ang pagpunta.'
      },
      {
        'title': 'Electric shock',
        'steps': '1. Huwag hawakan ang biktima habang nakakabit pa sa kuryente. Patayin ang breaker/unplug lamang kung ligtas.\n2. Sa high-voltage wire o hindi ligtas na lugar, lumayo at tawagin ang emergency services.\n3. Kapag ligtas na at hindi responsive/hindi humihinga nang normal, tumawag, simulan ang CPR kung trained, at gumamit ng AED kung mayroon.\n4. Takpan nang maluwag ang paso gamit ang malinis na dressing.\n5. Kailangan ng medical assessment pagkatapos ng electric shock kahit mukhang maayos.'
      },
      {
        'title': 'Pagkalason sa kemikal o gamot',
        'steps': '1. Ilayo sa pinagmulan nang hindi inilalagay sa panganib ang sarili; sa gas/fumes, lumabas muna sa sariwang hangin kung ligtas.\n2. Tumawag agad sa emergency services o poison specialist/health facility at ibigay ang pangalan ng produkto, dami at oras kung alam.\n3. Huwag pasukahin at huwag magbigay ng gatas, pagkain, suka o gamot maliban kung iniutos ng eksperto.\n4. Kung nasa balat/mata ang kemikal, alisin ang kontaminadong damit at banlawan ng maraming umaagos na tubig habang humihingi ng tulong.\n5. Itabi ang lalagyan/label para sa medical team; huwag maghintay ng sintomas.'
      },
      {
        'title': 'Hypoglycemia / mababang blood sugar',
        'steps': '1. Kung gising, alerto at kayang lumunok, sundin ang sariling diabetes plan; karaniwang mabilis na asukal gaya ng glucose tablets o matamis na juice ang ginagamit.\n2. Suriin muli ang blood sugar pagkalipas ng 15 minuto kung may meter at ulitin ayon sa personal plan kung mababa pa.\n3. Huwag magbigay ng pagkain o inumin sa taong nalilito nang malala, may seizure, o walang malay.\n4. Tumawag sa emergency services kung hindi ligtas lumunok, nawalan ng malay, may seizure, o hindi bumubuti. Gamitin lamang ang prescribed glucagon kung available at marunong gumamit.'
      },
      {
        'title': 'Pagkahimatay',
        'steps': '1. Suriin kung ligtas ang paligid at kung responsive at normal ang paghinga.\n2. Kung humihinga nang normal, ihiga nang patihaya at itaas nang bahagya ang mga paa kung walang injury at hindi nahihirapang huminga.\n3. Luwagan ang masikip na damit at huwag agad patayuin.\n4. Huwag magbigay ng pagkain/inumin hanggang ganap na gising.\n5. Tumawag agad kung hindi mabilis magising, may chest pain, hirap huminga, seizure, injury, buntis, o hindi normal ang paghinga.'
      },
      {
        'title': 'Choking (adult o bata na higit 1 taon)',
        'steps': '1. Kung malakas ang ubo at nakakapagsalita, hikayating umubo.\n2. Kung hindi makahinga, makapagsalita o makaubo nang epektibo, tumawag sa emergency services.\n3. Magbigay ng choking first aid ayon sa iyong training at dispatcher instructions.\n4. Huwag kapain nang bulag ang bibig.\n5. Kung mawalan ng malay, ibaba sa sahig at simulan ang CPR ayon sa training/dispatcher.'
      },
      {
        'title': 'Unresponsive person / walang malay',
        'steps': '1. Tiyaking ligtas ang lugar; tapikin ang balikat at tawagin nang malakas.\n2. Tumawag sa emergency services at magpakuha ng AED kung mayroon.\n3. Tingnan kung normal ang paghinga; ang hingal na paimpis-impis ay hindi normal na paghinga.\n4. Kung hindi normal ang paghinga, simulan ang CPR kung kaya at sundin ang dispatcher.\n5. Kung normal ang paghinga, ihiga patagilid kung walang hinalang spinal injury at patuloy na bantayan.'
      },
      {
        'title': 'Possible stroke / posibleng stroke',
        'steps': 'Tandaan ang FAST: Face—tabingi ang mukha; Arms—panghihina ng braso; Speech—malabo o kakaiba ang pagsasalita; Time—tumawag agad sa emergency services.\n1. Itala kung kailan huling normal ang tao.\n2. Huwag magbigay ng pagkain, inumin o gamot.\n3. Huwag maghintay kung mawawala ang sintomas; mahalaga ang mabilis na hospital treatment.'
      },
    ];
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * .86,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const Text('First Aid Guide', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Gabay lamang ito at hindi kapalit ng training o doktor. Sa agarang panganib, tumawag sa lokal na emergency services at sundin ang dispatcher. Huwag ilagay sa panganib ang sarili. Para sa sanggol, pagkalason, rabies, kagat ng ahas, matinding hirap huminga, stroke o chest pain, humingi agad ng propesyonal na tulong.'),
              const SizedBox(height: 12),
              ...guides.map((g) => Card(
                child: ExpansionTile(
                  title: Text(g['title']!, style: const TextStyle(fontWeight: FontWeight.w600)),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [Align(alignment: Alignment.centerLeft, child: SelectableText(g['steps']!))],
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDisasterAlerts() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true, builder: (ctx) => SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Disaster Alerts', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      const Text('This version does not yet fetch live alerts automatically. Check official sources for current warnings:'),
      ListTile(leading: const Icon(Icons.public), title: const Text('PAGASA'), subtitle: const Text('Weather, tropical cyclones, rainfall'), onTap: () async { final u = Uri.parse('https://www.pagasa.dost.gov.ph/'); if (await canLaunchUrl(u)) await launchUrl(u, mode: LaunchMode.externalApplication); }),
      ListTile(leading: const Icon(Icons.flood), title: const Text('NDRRMC'), subtitle: const Text('National disaster updates'), onTap: () async { final u = Uri.parse('https://ndrrmc.gov.ph/'); if (await canLaunchUrl(u)) await launchUrl(u, mode: LaunchMode.externalApplication); }),
      ListTile(leading: const Icon(Icons.warning_amber), title: const Text('PHIVOLCS'), subtitle: const Text('Earthquake and volcano information'), onTap: () async { final u = Uri.parse('https://www.phivolcs.dost.gov.ph/'); if (await canLaunchUrl(u)) await launchUrl(u, mode: LaunchMode.externalApplication); }),
      const SizedBox(height: 8), const Text('If you are in immediate danger, move to a safer location and contact local responders.'),
    ]))));
  }

  Future<void> _openSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    var history = prefs.getStringList('search_history') ?? <String>[];
    if (!mounted) return;
    await showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (ctx) => StatefulBuilder(builder: (ctx, setSheetState) => SafeArea(child: SizedBox(height: MediaQuery.of(ctx).size.height * .65, child: Column(children: [
      const Padding(padding: EdgeInsets.all(16), child: Text('Search History', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
      if (history.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('Wala pang saved searches. Mag-search ng lugar sa map para makita rito.')),
      Expanded(child: ListView(children: history.map((item) => ListTile(leading: const Icon(Icons.history), title: Text(item), onTap: () { _searchController.text = item; Navigator.pop(ctx); _searchPlaces(); })).toList())),
      TextButton.icon(onPressed: () async { history = []; await prefs.setStringList('search_history', history); setSheetState(() {}); }, icon: const Icon(Icons.delete_outline), label: const Text('Clear history')),
    ])))));
  }

  Future<void> _saveSearchHistory(String query) async {
    final value = query.trim();
    if (value.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('search_history') ?? <String>[];
    history.remove(value);
    history.insert(0, value);
    await prefs.setStringList('search_history', history.take(20).toList());
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<LatLng?> _geocodeArea(String query) async {
    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/search',
      {
        'q': '$query, Bulacan, Philippines',
        'format': 'jsonv2',
        'limit': '1',
      },
    );

    final response = await http.get(
      uri,
      headers: {'User-Agent': 'EmergencyLocatorStudentApp/1.0'},
    ).timeout(const Duration(seconds: 18));

    if (response.statusCode != 200) {
      throw Exception('Unable to search for this area.');
    }

    final data = jsonDecode(response.body) as List;

    if (data.isEmpty) return null;

    final first = data.first as Map<String, dynamic>;

    return LatLng(
      double.parse(first['lat'].toString()),
      double.parse(first['lon'].toString()),
    );
  }

  Future<void> _searchPlaces() async {
    await _saveSearchHistory(_searchController.text);
    // A newer search supersedes an older one. This also lets category changes
    // start a fresh request instead of being silently ignored while loading.
    final requestToken = ++_requestToken;
    final category = _selectedCategory;

    if (mounted) {
      setState(() {
        _loading = true;
        _status = 'Searching for ${category.name.toLowerCase()}...';
      });
    }

    try {
      LatLng center = _mapCenter;
      final query = _searchController.text.trim();

      if (query.isNotEmpty) {
        final result = await _geocodeArea(query);

        if (result == null) {
          if (mounted) {
            setState(() {
              _places = [];
              _status = 'No matching area found in Bulacan.';
            });
          }
          return;
        }

        center = result;
        _mapCenter = result;
        _area = query;
        _mapController.move(center, 12);
      }

      // Search a wider area and include common OpenStreetMap tagging variants.
      // Many facilities are mapped as ways/relations, not just nodes, and
      // evacuation locations may be tagged as shelters or assembly points.
      const radiusMeters = 15000;
      final lat = center.latitude;
      final lon = center.longitude;
      final List<String> filters = switch (category.id) {
        'hospital' => <String>[
          r'["amenity"~"^(hospital|clinic)$"]',
          r'["healthcare"~"^(hospital|clinic)$"]',
        ],
        'police' => <String>['["amenity"="police"]'],
        'fire' => <String>['["amenity"="fire_station"]'],
        'hotel' => <String>[
          r'["tourism"~"^(hotel|motel|guest_house|hostel)$"]',
        ],
        'evacuation' => <String>[
          '["amenity"="shelter"]',
          '["emergency"="assembly_point"]',
          '["social_facility"="shelter"]',
        ],
        _ => <String>[category.overpassFilter],
      };
      final overpassBlocks = <String>[];
      for (final filter in filters) {
        overpassBlocks.add('''
  nwr(around:$radiusMeters,$lat,$lon)$filter;
''');
      }
      final overpassQuery = '''
[out:json][timeout:35];
(
${overpassBlocks.join()}
);
out center 100;
''';

      // Public Overpass instances sometimes get busy. Try alternate instances
      // before showing an error to the user.
      const endpoints = <String>[
        'https://overpass-api.de/api/interpreter',
        'https://overpass.kumi.systems/api/interpreter',
        'https://overpass.private.coffee/api/interpreter',
      ];
      http.Response? response;
      Object? lastSearchError;

      for (final endpoint in endpoints) {
        if (!mounted || requestToken != _requestToken) return;
        try {
          final candidate = await http
              .post(
            Uri.parse(endpoint),
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'User-Agent': 'EmergencyLocatorStudentApp/1.0',
            },
            body: {'data': overpassQuery},
          )
              .timeout(const Duration(seconds: 32));

          if (candidate.statusCode == 200) {
            response = candidate;
            break;
          }
          lastSearchError = Exception('Map service returned ${candidate.statusCode}.');
        } on TimeoutException catch (e) {
          lastSearchError = e;
        } catch (e) {
          lastSearchError = e;
        }
      }

      if (!mounted || requestToken != _requestToken) return;
      if (response == null) {
        if (lastSearchError is TimeoutException) {
          throw TimeoutException('All map search servers timed out.');
        }
        throw Exception('Map search services are temporarily unavailable.');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = decoded['elements'] as List<dynamic>? ?? [];

      final results = <EmergencyPlace>[];

      final seenCoordinates = <String>{};
      for (final item in elements) {
        if (results.length >= 100) break;
        final element = item as Map<String, dynamic>;
        final tags = element['tags'] as Map<String, dynamic>? ?? {};

        final lat = element['lat'] ?? element['center']?['lat'];
        final lon = element['lon'] ?? element['center']?['lon'];

        if (lat == null || lon == null) continue;

        final name = (tags['name'] ??
            tags['name:en'] ??
            tags['operator'] ??
            category.name)
            .toString();

        final latitude = double.parse(lat.toString());
        final longitude = double.parse(lon.toString());
        final coordinateKey =
            '${latitude.toStringAsFixed(4)},${longitude.toStringAsFixed(4)}';
        if (!seenCoordinates.add(coordinateKey)) continue;

        results.add(
          EmergencyPlace(
            name: name,
            type: category.name,
            point: LatLng(latitude, longitude),
          ),
        );
      }

      if (!mounted || requestToken != _requestToken) return;

      setState(() {
        _places = results;
        _status = results.isEmpty
            ? 'No ${category.name.toLowerCase()} locations found nearby. Try another area.'
            : 'Found ${results.length} location(s) near $_area.';
      });
      if (results.isNotEmpty) await _saveCachedPlaces(results);
    } on TimeoutException {
      if (mounted && requestToken == _requestToken) {
        setState(() {
          _status = 'Search servers are slow. Your previous markers are kept; tap Search to retry.';
        });
      }
    } catch (e, stackTrace) {
      debugPrint('SEARCH LOCATIONS ERROR: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted && requestToken == _requestToken) {
        setState(() {
          _status = 'Could not load locations. Check internet, then tap Search to retry.';
        });
      }
    } finally {
      if (mounted && requestToken == _requestToken) {
        setState(() => _loading = false);
      }
    }
  }

  void _selectCategory(EmergencyCategory category) {
    if (_selectedCategory.id == category.id) return;
    setState(() => _selectedCategory = category);
    _searchPlaces();
  }

  void _moveToPlace(EmergencyPlace place) {
    _mapController.move(place.point, 16);
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => LoginPage(
            darkMode: widget.darkMode,
            onThemeChanged: widget.onThemeChanged,
          ),
        ),
            (_) => false,
      );
    } catch (e) {
      _showMessage('Unable to log out. Please try again.');
    }
  }

  Future<void> _openFamilySafetyCheckIn() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('family_safety_status') ?? 'Not checked in';
    final checkedAt = prefs.getString('family_safety_time') ?? '';
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Family Safety Check-In'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Current status: $saved'),
        if (checkedAt.isNotEmpty) Text('Last update: $checkedAt'),
        const SizedBox(height: 8),
        const Text('This check-in is saved on this device. It does not automatically notify family members.'),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        FilledButton.icon(onPressed: () async {
          final now = DateTime.now().toLocal().toString().substring(0, 16);
          await prefs.setString('family_safety_status', 'I am safe');
          await prefs.setString('family_safety_time', now);
          if (ctx.mounted) Navigator.pop(ctx);
          if (mounted) _showMessage('Safety status saved on this device. Share it with a contact separately.');
        }, icon: const Icon(Icons.check_circle_outline), label: const Text("I'm safe")),
        OutlinedButton.icon(onPressed: () async {
          final contacts = prefs.getStringList('offline_emergency_contacts') ?? <String>[];
          if (contacts.isEmpty) { if (ctx.mounted) Navigator.pop(ctx); _openOfflineContacts(); return; }
          final first = contacts.first.split('|');
          final phone = first.length > 1 ? first.sublist(1).join('|') : '';
          final uri = Uri(scheme: 'sms', path: phone, queryParameters: {'body': 'Emergency Locator check-in: I am safe. Time: ${DateTime.now().toLocal()}'});
          final launched = await launchUrl(uri);
          if (!launched && mounted) _showMessage('Could not open SMS.');
        }, icon: const Icon(Icons.sms_outlined), label: const Text('Text first contact')),
      ],
    ));
  }

  Future<void> _openEvacuationCenters() async {
    _searchController.text = 'evacuation center';
    _showMessage('Searching map data for evacuation centers. Results may be incomplete; follow local government instructions.');
    await _searchPlaces();
  }

  Future<void> _openAccessibilitySettings() async {
    final prefs = await SharedPreferences.getInstance();
    var language = prefs.getString('preferred_language') ?? 'English';
    var largeText = prefs.getBool('accessibility_large_text') ?? false;
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
      title: const Text('Accessibility & Language'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: language, decoration: const InputDecoration(labelText: 'Preferred language'), items: const [DropdownMenuItem(value: 'English', child: Text('English')), DropdownMenuItem(value: 'Filipino', child: Text('Filipino'))], onChanged: (v) { if (v != null) setDialogState(() => language = v); }),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Large text preference'), subtitle: const Text('Saved preference; full app-wide scaling is not yet applied.'), value: largeText, onChanged: (v) => setDialogState(() => largeText = v)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () async { await prefs.setString('preferred_language', language); await prefs.setBool('accessibility_large_text', largeText); if (ctx.mounted) Navigator.pop(ctx); if (mounted) _showMessage('Preferences saved. Some screens may not yet be translated or resized.'); }, child: const Text('Save'))],
    )));
  }

  Future<void> _openAdminDashboard() async {
    final user = FirebaseAuth.instance.currentUser;
    var isAdmin = false;
    try { isAdmin = (await user?.getIdTokenResult(true))?.claims?['admin'] == true; } catch (_) {}
    if (!mounted) return;
    if (!isAdmin) { _showMessage('Admin access is required.'); return; }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminDashboardPage()));
  }

  Future<void> _showFacilitySos(EmergencyPlace selected) async {
    setState(() => _emergencyTarget = selected);
    // Immediately focus the map on the selected facility and highlight its marker.
    _mapController.move(selected.point, 16);
    final detailsController = TextEditingController();
    final origin = _gpsPosition == null
        ? _mapCenter
        : LatLng(_gpsPosition!.latitude, _gpsPosition!.longitude);
    final candidates = _places.where((p) => p.type == selected.type || p.type == _selectedCategory.name).toList();
    candidates.sort((a, b) => const Distance().as(LengthUnit.Meter, origin, a.point)
        .compareTo(const Distance().as(LengthUnit.Meter, origin, b.point)));
    final nearest = candidates.take(3).toList();
    if (!nearest.any((p) => _favoriteKey(p) == _favoriteKey(selected))) {
      nearest.insert(0, selected);
      if (nearest.length > 3) nearest.removeLast();
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        icon: const Icon(Icons.sos_rounded, color: Colors.red, size: 42),
        title: const Text('Emergency SOS'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Selected facility: ${selected.name}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Nearby facilities (estimated straight-line distance):'),
            const SizedBox(height: 6),
            if (nearest.isEmpty) const Text('No nearby facilities loaded. Try searching the map again.'),
            for (var i = 0; i < nearest.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
                title: Text(nearest[i].name, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('${const Distance().as(LengthUnit.Kilometer, origin, nearest[i].point).toStringAsFixed(1)} km away'),
                trailing: IconButton(
                  tooltip: 'Directions',
                  icon: const Icon(Icons.directions),
                  onPressed: () { Navigator.pop(ctx); _openDirections(nearest[i]); },
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: detailsController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Emergency details (optional)',
                hintText: 'e.g. chest pain, accident, exact landmark',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text('This form does not automatically dispatch an ambulance or send your location to responders.', style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          OutlinedButton.icon(
            onPressed: () {
              final details = detailsController.text;
              Navigator.pop(ctx);
              _shareEmergencyLocation(details: details);
            },
            icon: const Icon(Icons.share_location),
            label: const Text('Share location'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final uri = Uri(scheme: 'tel', path: '911');
              try { await launchUrl(uri); } catch (_) {}
            },
            icon: const Icon(Icons.call), label: const Text('Call 911'),
          ),
          FilledButton.icon(
            onPressed: () { Navigator.pop(ctx); _openDirections(selected); },
            icon: const Icon(Icons.navigation), label: const Text('Directions'),
          ),
        ],
      ),
    );
    detailsController.dispose();
  }

  Future<void> _shareEmergencyLocation({String details = ''}) async {
    final origin = _gpsPosition == null
        ? _mapCenter
        : LatLng(_gpsPosition!.latitude, _gpsPosition!.longitude);
    final prefs = await SharedPreferences.getInstance();
    final contacts = prefs.getStringList('offline_emergency_contacts') ?? <String>[];
    var phone = '';
    if (contacts.isNotEmpty) {
      final parts = contacts.first.split('|');
      if (parts.length > 1) phone = parts.sublist(1).join('|').trim();
    }
    final mapLink = 'https://maps.google.com/?q=${origin.latitude},${origin.longitude}';
    final source = _gpsPosition == null ? 'Map center (GPS not confirmed)' : 'GPS location';
    final message = 'EMERGENCY ALERT - Emergency Locator\n'
        'Location source: $source\n'
        'Coordinates: ${origin.latitude.toStringAsFixed(6)}, ${origin.longitude.toStringAsFixed(6)}\n'
        'Map: $mapLink'
        '${details.trim().isEmpty ? '' : '\nDetails: ${details.trim()}'}\n'
        'Please contact me or emergency services.';
    final uri = Uri(scheme: 'sms', path: phone, queryParameters: {'body': message});
    try {
      final launched = await launchUrl(uri);
      if (!launched && mounted) _showMessage('Could not open SMS. You can copy the coordinates from the map.');
    } catch (_) {
      if (mounted) _showMessage('Could not open SMS. Check the messaging app on your phone.');
    }
  }

  void _showSosDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.sos_rounded, color: Colors.red, size: 58),
        title: const Text('Emergency SOS'),
        content: const Text(
          'If you are in immediate danger, contact local emergency services. '
              'This app does not automatically send your location or dispatch help. '
              'You can open directions to a facility from its map marker. Verify '
              'emergency numbers for your municipality before relying on them.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(dialogContext);
              final uri = Uri(scheme: 'tel', path: '911');
              try {
                await launchUrl(uri);
              } catch (_) {
                _showMessage('If this is an emergency, call your local emergency number directly.');
              }
            },
            icon: const Icon(Icons.call),
            label: const Text('Call 911'),
          ),
        ],
      ),
    );
  }

  Widget _categoryButton(EmergencyCategory category) {
    final selected = _selectedCategory.id == category.id;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected,
        avatar: Icon(
          category.icon,
          size: 18,
          color: selected ? Colors.white : category.color,
        ),
        label: Text(category.name),
        onSelected: (_) => _selectCategory(category),
        selectedColor: const Color(0xFF1565C0),
        labelStyle: TextStyle(
          color: selected ? Colors.white : null,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  void _zoomMap(double amount) {
    final camera = _mapController.camera;
    final nextZoom = (camera.zoom + amount).clamp(7.0, 18.0).toDouble();
    _mapController.move(camera.center, nextZoom);
  }

  void _resetMapView() {
    _mapCenter = _bulacanCenter;
    _mapController.move(_bulacanCenter, 10.5);
  }

  Widget _buildMap() {
    final theme = Theme.of(context);

    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _bulacanCenter,
              initialZoom: 10.5,
              minZoom: 7,
              maxZoom: 18,
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) _mapCenter = camera.center;
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.emergency_locator',
                maxNativeZoom: 19,
              ),
              MarkerLayer(
                markers: [
                  for (final place in _visiblePlaces)
                    Marker(
                      point: place.point,
                      width: 56,
                      height: 64,
                      child: Tooltip(
                        message: place.name,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.72, end: 1.0),
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutBack,
                          builder: (context, scale, child) => Transform.scale(
                            scale: scale,
                            child: child,
                          ),
                          child: GestureDetector(
                            onTap: () {
                              _mapController.move(place.point, 16);
                              _showPlaceDetails(place);
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: _emergencyTarget != null &&
                                        _favoriteKey(place) == _favoriteKey(_emergencyTarget!)
                                        ? Colors.red
                                        : _selectedCategory.color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 3,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 8,
                                        offset: Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    _selectedCategory.icon,
                                    color: Colors.white,
                                    size: 23,
                                  ),
                                ),
                                Container(
                                  width: 3,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: _emergencyTarget != null &&
                                        _favoriteKey(place) == _favoriteKey(_emergencyTarget!)
                                        ? Colors.red
                                        : _selectedCategory.color,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_gpsPosition != null)
                    Marker(
                      point: LatLng(_gpsPosition!.latitude, _gpsPosition!.longitude),
                      width: 52,
                      height: 52,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1565C0).withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF1565C0), width: 2),
                        ),
                        child: const Center(
                          child: Icon(Icons.my_location, color: Color(0xFF1565C0), size: 26),
                        ),
                      ),
                    ),
                ],
              ),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    'OpenStreetMap contributors',
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),
        ),

        // Floating map controls
        Positioned(
          right: 16,
          bottom: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MapControlButton(
                icon: Icons.add_rounded,
                tooltip: 'Zoom in',
                onPressed: () => _zoomMap(1),
              ),
              const SizedBox(height: 10),
              _MapControlButton(
                icon: Icons.remove_rounded,
                tooltip: 'Zoom out',
                onPressed: () => _zoomMap(-1),
              ),
              const SizedBox(height: 10),
              _MapControlButton(
                icon: Icons.my_location_rounded,
                tooltip: 'Return to Bulacan',
                onPressed: _resetMapView,
              ),
            ],
          ),
        ),

        // Search result count badge
        if (_places.isNotEmpty)
          Positioned(
            left: 14,
            top: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 13,
                vertical: 9,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _selectedCategory.icon,
                    size: 17,
                    color: _selectedCategory.color,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    '${_visiblePlaces.length} found',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCompactSearchPanel() {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Icon(Icons.health_and_safety_rounded, color: Color(0xFF1565C0)),
            const SizedBox(width: 7),
            const Expanded(child: Text('Emergency Locator', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            IconButton(
              tooltip: _showSettings ? 'Hide settings' : 'Settings',
              onPressed: () => setState(() => _showSettings = !_showSettings),
              icon: Icon(_showSettings ? Icons.close : Icons.settings_outlined),
            ),
          ]),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: emergencyCategories.map(_categoryButton).toList(),
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: SizedBox(
              height: 42,
              child: TextField(
                controller: _searchController,
                onSubmitted: (_) => _searchPlaces(),
                decoration: const InputDecoration(
                  hintText: 'Search area in Bulacan',
                  prefixIcon: Icon(Icons.search),
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(),
                ),
              ),
            )),
            const SizedBox(width: 6),
            IconButton.filled(
              tooltip: 'Search facilities',
              onPressed: _loading ? null : _searchPlaces,
              icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.arrow_forward),
            ),
            IconButton(
              tooltip: 'Refresh GPS',
              onPressed: _gpsLoading ? null : _refreshGpsLocation,
              icon: const Icon(Icons.my_location),
            ),
          ]),
          if (_status.isNotEmpty)
            Align(alignment: Alignment.centerLeft, child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_status, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
            )),
        ]),
      ),
    );
  }

  Widget _buildSearchPanel() {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final isError = !_loading && (_status.toLowerCase().contains('timed out') ||
        _status.toLowerCase().contains('unable to load') ||
        _status.toLowerCase().contains('busy'));

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .16 : .07),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 15, 18, 18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0D47A1), Color(0xFF1688F8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .16),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Icon(Icons.health_and_safety_rounded,
                          color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Emergency Locator', style: TextStyle(
                            color: Colors.white, fontSize: 19,
                            fontWeight: FontWeight.w800, letterSpacing: -.3,
                          )),
                          SizedBox(height: 3),
                          Row(children: [
                            Icon(Icons.location_on_rounded, color: Colors.white70, size: 14),
                            SizedBox(width: 3),
                            Text('BULACAN, PHILIPPINES', style: TextStyle(
                              color: Colors.white70, fontSize: 10,
                              letterSpacing: 1.1, fontWeight: FontWeight.w700,
                            )),
                          ]),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Profile and settings',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: .16),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _showProfile,
                      icon: const Icon(Icons.person_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 17),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(17),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 4))],
                  ),
                  child: Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: 14),
                        child: Icon(Icons.search_rounded, color: Color(0xFF54708F), size: 24),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => _searchPlaces(),
                          style: const TextStyle(color: Color(0xFF17324F), fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Search municipality or city',
                            hintStyle: const TextStyle(color: Color(0xFF8A9BB0), fontSize: 13),
                            border: InputBorder.none,
                            filled: false,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
                            suffixIcon: _searchController.text.isEmpty ? null : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () { _searchController.clear(); setState(() {}); },
                              icon: const Icon(Icons.close_rounded, color: Color(0xFF54708F)),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(5),
                        child: FilledButton(
                          onPressed: _loading ? null : _searchPlaces,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0877E8),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(46, 46),
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                          ),
                          child: _loading
                              ? const SizedBox(width: 19, height: 19, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.arrow_forward_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('Find nearby help', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
                    if (_places.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(20)),
                        child: Text('${_places.length} places', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: theme.colorScheme.onPrimaryContainer)),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 43,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: emergencyCategories.map(_categoryButton).toList(),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _utilityChip(
                      icon: _showFavoritesOnly ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      label: _showFavoritesOnly ? 'Saved only' : 'Saved places',
                      selected: _showFavoritesOnly,
                      onTap: () => setState(() => _showFavoritesOnly = !_showFavoritesOnly),
                    ),
                    _utilityChip(
                      icon: _sortNearestFirst ? Icons.near_me_rounded : Icons.sort_rounded,
                      label: _sortNearestFirst ? 'Nearest first' : 'Default order',
                      selected: _sortNearestFirst,
                      onTap: () => setState(() => _sortNearestFirst = !_sortNearestFirst),
                    ),
                    _utilityChip(
                      icon: Icons.my_location_rounded,
                      label: 'Reset map',
                      selected: false,
                      onTap: _resetMapView,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  ActionChip(avatar: const Icon(Icons.my_location_rounded, size: 17), label: Text(_gpsLoading ? 'Refreshing GPS...' : 'Refresh GPS'), onPressed: _gpsLoading ? null : _refreshGpsLocation),
                  ActionChip(avatar: const Icon(Icons.contacts_outlined, size: 17), label: const Text('Offline contacts'), onPressed: _openOfflineContacts),
                  ActionChip(avatar: const Icon(Icons.medical_services_outlined, size: 17), label: const Text('First Aid'), onPressed: _openFirstAidGuide),
                  ActionChip(avatar: const Icon(Icons.warning_amber_rounded, size: 17), label: const Text('Disaster alerts'), onPressed: _openDisasterAlerts),
                  ActionChip(avatar: const Icon(Icons.history, size: 17), label: const Text('History'), onPressed: _openSearchHistory),
                  ActionChip(avatar: const Icon(Icons.report_outlined, size: 17), label: const Text('Report issue'), onPressed: _openReportForm),
                  ActionChip(avatar: const Icon(Icons.assignment_outlined, size: 17), label: const Text('My reports'), onPressed: _openMyReports),
                  ActionChip(avatar: const Icon(Icons.family_restroom, size: 17), label: const Text('Family check-in'), onPressed: _openFamilySafetyCheckIn),
                  ActionChip(avatar: const Icon(Icons.location_city, size: 17), label: const Text('Evacuation centers'), onPressed: _openEvacuationCenters),
                  ActionChip(avatar: const Icon(Icons.accessibility_new, size: 17), label: const Text('Accessibility'), onPressed: _openAccessibilitySettings),
                  ActionChip(avatar: const Icon(Icons.admin_panel_settings_outlined, size: 17), label: const Text('Admin dashboard'), onPressed: _openAdminDashboard),
                ]),
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerLeft, child: Text(_gpsStatus, style: theme.textTheme.bodySmall?.copyWith(color: _gpsAccuracyMeters != null && _gpsAccuracyMeters! > 100 ? Colors.orange : theme.colorScheme.onSurfaceVariant))),
                const SizedBox(height: 9),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isError
                        ? (dark ? Colors.red.withValues(alpha: .13) : const Color(0xFFFFF0EF))
                        : (dark ? Colors.white.withValues(alpha: .045) : const Color(0xFFF3F7FC)),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isError ? Colors.red.withValues(alpha: .25) : theme.dividerColor.withValues(alpha: .35)),
                  ),
                  child: Row(
                    children: [
                      if (_loading)
                        const SizedBox(width: 19, height: 19, child: CircularProgressIndicator(strokeWidth: 2.2))
                      else
                        Icon(isError ? Icons.cloud_off_rounded : Icons.info_outline_rounded,
                            size: 19, color: isError ? Colors.red : theme.colorScheme.primary),
                      const SizedBox(width: 9),
                      Expanded(child: Text(_status, style: theme.textTheme.bodySmall?.copyWith(height: 1.25))),
                      if (isError)
                        IconButton(
                          tooltip: 'Retry search',
                          visualDensity: VisualDensity.compact,
                          onPressed: _loading ? null : _searchPlaces,
                          icon: const Icon(Icons.refresh_rounded, color: Colors.red),
                        ),
                    ],
                  ),
                ),
                if (_loading) ...[
                  const SizedBox(height: 8),
                  const ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(5)),
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _utilityChip({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest.withValues(alpha: .65),
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: selected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: selected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }

  Widget _buildSettingsPanel() {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.favorite_outline),
                title: const Text('Favorites'),
                subtitle: Text(_showFavoritesOnly ? 'Showing saved facilities only' : 'Show saved facilities on the map'),
                trailing: Switch(value: _showFavoritesOnly, onChanged: (v) => setState(() { _showFavoritesOnly = v; _showSettings = false; })),
              ),
              ListTile(
                leading: const Icon(Icons.sort),
                title: const Text('Sort nearest first'),
                trailing: Switch(value: _sortNearestFirst, onChanged: (v) => setState(() => _sortNearestFirst = v)),
              ),
              ListTile(
                leading: const Icon(Icons.accessibility_new),
                title: const Text('Accessibility & language'),
                onTap: _openAccessibilitySettings,
              ),
              ListTile(
                leading: const Icon(Icons.medical_services_outlined),
                title: const Text('First aid guide'),
                onTap: _openFirstAidGuide,
              ),
              ListTile(
                leading: const Icon(Icons.contacts_outlined),
                title: const Text('Offline emergency contacts'),
                onTap: _openOfflineContacts,
              ),
              SwitchListTile(
                title: const Text('Dark mode'),
                secondary: const Icon(Icons.dark_mode_outlined),
                value: widget.darkMode,
                onChanged: widget.onThemeChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Column(
          children: [
            _buildCompactSearchPanel(),
            if (_showSettings)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.42),
                child: _buildSettingsPanel(),
              ),
            Expanded(child: _buildMap()),
          ],
        ),
      ),
    );
  }
}


// ============================================================
// FLOATING MAP CONTROL
// ============================================================

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface,
      elevation: 5,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(17),
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 26),
        style: IconButton.styleFrom(
          minimumSize: const Size(54, 54),
          maximumSize: const Size(54, 54),
          foregroundColor: colorScheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
        ),
      ),
    );
  }
}


// ============================================================
// LIGHTWEIGHT ANIMATIONS (kept subtle to preserve performance)
// ============================================================

class _AnimatedSplashLogo extends StatefulWidget {
  const _AnimatedSplashLogo();

  @override
  State<_AnimatedSplashLogo> createState() => _AnimatedSplashLogoState();
}

class _AnimatedSplashLogoState extends State<_AnimatedSplashLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _scale = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: 124,
          height: 124,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.13),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.5),
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 24, spreadRadius: 2),
            ],
          ),
          child: const Icon(
            Icons.health_and_safety_rounded,
            color: Colors.white,
            size: 78,
          ),
        ),
      ),
    );
  }
}

