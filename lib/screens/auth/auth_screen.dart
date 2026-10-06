import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../../core/constants/app_colors.dart';
import '../../data/services/supabase_service.dart';
import '../../data/services/connectivity_service.dart';
import 'otp_screen.dart';

class AuthScreen extends StatefulWidget {
  /// Set to true when navigating here from the logout flow.
  /// Hides the "Continue as Guest" button so the user is forced to sign in.
  final bool fromLogout;
  const AuthScreen({super.key, this.fromLogout = false});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with TickerProviderStateMixin {
  bool _isLogin = true;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _errorMsg;
  String _selectedGender = 'Male';

  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  final _supabase = SupabaseService.instance;
  final _connectivity = ConnectivityService.instance;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isLogin = !_isLogin;
      _errorMsg = null;
    });
    _fadeCtrl.reset();
    _fadeCtrl.forward();
  }

  // ── SIGN UP ───────────────────────────────────────────────
  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() { _isLoading = true; _errorMsg = null; });

    // 1. Check internet — auth is always online
    final online = await _connectivity.isOnline();
    if (!mounted) return;
    if (!online) {
      setState(() {
        _isLoading = false;
        _errorMsg = 'No internet connection.\nSign Up requires internet access.';
      });
      return;
    }

    // 2. Check if email already exists
    final email = _emailCtrl.text.trim().toLowerCase();
    final exists = await _supabase.checkEmailExists(email);
    if (!mounted) return;
    if (exists) {
      setState(() {
        _isLoading = false;
        _errorMsg = 'This email is already registered. Please sign in instead.';
      });
      return;
    }

    // 3. Send OTP via Brevo (through Supabase Edge Function)
    final otpError = await _supabase.sendOtp(email);
    if (!mounted) return;
    if (otpError != null) {
      setState(() { _isLoading = false; _errorMsg = otpError; });
      return;
    }

    setState(() => _isLoading = false);

    // 3. Navigate to OTP screen — account is created there after verification
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OtpScreen(
        email: _emailCtrl.text.trim().toLowerCase(),
        password: _passwordCtrl.text,
        name: _nameCtrl.text.trim(),
        gender: _selectedGender,
        age: _ageCtrl.text.trim(),
      ),
    ));
  }

  // ── SIGN IN ───────────────────────────────────────────────
  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _errorMsg = null; });

    // 1. Check internet — sign in is always online
    final online = await _connectivity.isOnline();
    if (!mounted) return;
    if (!online) {
      setState(() {
        _isLoading = false;
        _errorMsg = 'No internet connection.\nSign In requires internet access.';
      });
      return;
    }

    try {
      // 2. Validate credentials FIRST before sending OTP
      // We do a dry-run sign-in to ensure password is correct.
      final userData = await _supabase.signIn(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      if (!mounted) return;
      if (userData == null) {
        setState(() {
          _isLoading = false;
          _errorMsg = 'Incorrect email or password.\nNot registered? Switch to Sign Up.';
        });
        return;
      }

      // 3. Send OTP via Brevo
      final otpError = await _supabase.sendOtp(_emailCtrl.text.trim());
      if (!mounted) return;
      if (otpError != null) {
        setState(() {
          _isLoading = false;
          _errorMsg = otpError;
        });
        return;
      }

      setState(() => _isLoading = false);

      // 4. Navigate to OTP screen for verification
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => OtpScreen(
          email: _emailCtrl.text.trim().toLowerCase(),
          password: _passwordCtrl.text,
          isSignIn: true, // Tell OtpScreen to log in instead of sign up
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMsg = e.toString();
      });
    }
  }

  // ── GUEST ─────────────────────────────────────────────────
  Future<void> _guestLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_logged_in', true);
    await prefs.setString('user_name', 'Guest');
    await prefs.setString('user_email', '');
    await prefs.setString('user_age', '');
    await prefs.setString('userGender', 'Male');
    await prefs.setBool('is_guest', true);

    if (mounted) {
      await Provider.of<SettingsProvider>(context, listen: false)
          .updateProfile('Guest', '');
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    }
  }

  Future<void> _submit() async {
    _isLogin ? await _signIn() : await _signUp();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1A1008) : const Color(0xFFFAF6F0);
    final cardColor = isDark ? const Color(0xFF2C1F11) : Colors.white;
    final borderColor =
        isDark ? const Color(0xFF3D2E1A) : const Color(0xFFE8DDD0);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1008);
    final subColor =
        isDark ? const Color(0xFFA08060) : const Color(0xFF8B6914);

    return Scaffold(
      backgroundColor: bgColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [const Color(0xFF0D0805), const Color(0xFF1A1008)]
                : [const Color(0xFFFAF6F0), const Color(0xFFF0E8DC)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    const SizedBox(height: 40),

                    // Logo
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(colors: [
                          Color(0xFFD4A96A),
                          Color(0xFF8B6914),
                        ]),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.gold.withValues(alpha: 0.4),
                            blurRadius: 24,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/images/app_logo.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('My Salah',
                        style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: AppColors.gold,
                            letterSpacing: 1.5)),
                    Text('Track Your Prayers Daily',
                        style: TextStyle(fontSize: 13, color: subColor)),
                    const SizedBox(height: 36),

                    // Mode toggle
                    Container(
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(children: [
                        _modeTab('Sign In', _isLogin, cardColor, borderColor),
                        _modeTab('Sign Up', !_isLogin, cardColor, borderColor),
                      ]),
                    ),
                    const SizedBox(height: 24),

                    // Error message
                    if (_errorMsg != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                color: Colors.redAccent, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_errorMsg!,
                                  style: const TextStyle(
                                      color: Colors.redAccent, fontSize: 13)),
                            ),
                          ],
                        ),
                      ),

                    // ── SIGN UP ONLY fields ──
                    if (!_isLogin) ...[
                      _field(
                        controller: _nameCtrl,
                        label: 'Full Name',
                        icon: Icons.person_outline_rounded,
                        textColor: textColor,
                        subColor: subColor,
                        cardColor: cardColor,
                        borderColor: borderColor,
                        validator: (v) =>
                            v!.trim().isEmpty ? 'Enter your full name' : null,
                      ),
                      const SizedBox(height: 14),
                      _field(
                        controller: _ageCtrl,
                        label: 'Age',
                        icon: Icons.cake_outlined,
                        keyboardType: TextInputType.number,
                        textColor: textColor,
                        subColor: subColor,
                        cardColor: cardColor,
                        borderColor: borderColor,
                        validator: (v) {
                          if (v!.trim().isEmpty) return 'Enter your age';
                          final age = int.tryParse(v.trim());
                          if (age == null || age < 5 || age > 120) {
                            return 'Enter a valid age (5–120)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      _genderDropdown(
                        textColor: textColor,
                        subColor: subColor,
                        cardColor: cardColor,
                        borderColor: borderColor,
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Email
                    _field(
                      controller: _emailCtrl,
                      label: 'Email Address',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      textColor: textColor,
                      subColor: subColor,
                      cardColor: cardColor,
                      borderColor: borderColor,
                      validator: (v) {
                        if (v!.trim().isEmpty) return 'Enter your email';
                        if (!RegExp(r'^[^@]+@[^@]+\.[^@]+')
                            .hasMatch(v.trim())) {
                          return 'Enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // Password
                    _field(
                      controller: _passwordCtrl,
                      label: 'Password',
                      icon: Icons.lock_outline_rounded,
                      obscure: _obscurePassword,
                      textColor: textColor,
                      subColor: subColor,
                      cardColor: cardColor,
                      borderColor: borderColor,
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: subColor,
                          size: 20,
                        ),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                      validator: (v) =>
                          v!.length < 6 ? 'Minimum 6 characters' : null,
                    ),

                    // Confirm Password (sign up only)
                    if (!_isLogin) ...[
                      const SizedBox(height: 14),
                      _field(
                        controller: _confirmCtrl,
                        label: 'Confirm Password',
                        icon: Icons.lock_outline_rounded,
                        obscure: _obscureConfirm,
                        textColor: textColor,
                        subColor: subColor,
                        cardColor: cardColor,
                        borderColor: borderColor,
                        suffix: IconButton(
                          icon: Icon(
                            _obscureConfirm
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: subColor,
                            size: 20,
                          ),
                          onPressed: () => setState(
                              () => _obscureConfirm = !_obscureConfirm),
                        ),
                        validator: (v) {
                          if (v!.isEmpty) return 'Confirm your password';
                          if (v != _passwordCtrl.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),
                    ],

                    const SizedBox(height: 28),

                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.gold,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 6,
                          shadowColor: AppColors.gold.withValues(alpha: 0.4),
                        ),
                        onPressed: _isLoading ? null : _submit,
                        child: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    color: Colors.black, strokeWidth: 2.5),
                              )
                            : Text(
                                _isLogin ? 'Sign In' : 'Create Account',
                                style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5),
                              ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Internet note banner
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.gold.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.wifi_rounded,
                              color: AppColors.gold.withValues(alpha: 0.7), size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Internet is required for Sign In & Sign Up. Guest mode works offline.',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: subColor,
                                  height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Guest button — hidden after logout so user must sign in
                    if (!widget.fromLogout)
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        icon: Icon(Icons.person_rounded,
                            size: 18, color: subColor),
                        label:
                            Text('Continue as Guest',
                                style: TextStyle(color: subColor)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: borderColor),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _guestLogin,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Toggle link
                    GestureDetector(
                      onTap: _toggleMode,
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(fontSize: 14, color: subColor),
                          children: [
                            TextSpan(
                                text: _isLogin
                                    ? "Don't have an account? "
                                    : 'Already have an account? '),
                            TextSpan(
                              text: _isLogin ? 'Sign Up' : 'Sign In',
                              style: const TextStyle(
                                  color: AppColors.gold,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeTab(
      String label, bool active, Color cardColor, Color borderColor) {
    return Expanded(
      child: GestureDetector(
        onTap: active ? null : _toggleMode,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: active ? AppColors.gold : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? Colors.black : const Color(0xFFA08060),
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color textColor,
    required Color subColor,
    required Color cardColor,
    required Color borderColor,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffix,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      style: TextStyle(color: textColor),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: subColor, fontSize: 14),
        prefixIcon: Icon(icon, color: subColor, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _genderDropdown({
    required Color textColor,
    required Color subColor,
    required Color cardColor,
    required Color borderColor,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: _selectedGender,
      dropdownColor: cardColor,
      style: TextStyle(color: textColor),
      decoration: InputDecoration(
        labelText: 'Gender',
        labelStyle: TextStyle(color: subColor, fontSize: 14),
        prefixIcon: Icon(Icons.people_outline, color: subColor, size: 20),
        filled: true,
        fillColor: cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      items: const [
        DropdownMenuItem(value: 'Male', child: Text('Male')),
        DropdownMenuItem(value: 'Female', child: Text('Female')),
      ],
      onChanged: (val) {
        if (val != null) {
          setState(() => _selectedGender = val);
        }
      },
    );
  }
}
