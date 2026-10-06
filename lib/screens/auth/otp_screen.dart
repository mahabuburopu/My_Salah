import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/services/supabase_service.dart';
import '../../data/services/sync_service.dart';
import '../../data/services/database_service.dart';
import '../../providers/settings_provider.dart';
import '../../core/constants/app_colors.dart';

/// OTP verification screen shown after Sign Up OR Sign In.
/// [isSignIn] = true → verifies OTP then signs in with email+password.
/// [isSignIn] = false (default) → verifies OTP then creates a new account.
class OtpScreen extends StatefulWidget {
  final String email;
  final String password;
  final String name;
  final String gender;
  final String age;
  final bool isSignIn;

  const OtpScreen({
    super.key,
    required this.email,
    required this.password,
    this.name = '',
    this.gender = 'Male',
    this.age = '',
    this.isSignIn = false,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _supabase = SupabaseService.instance;
  String _otp = '';
  bool _isVerifying = false;
  bool _isSendingOtp = false;
  String? _errorMsg;

  // Resend cooldown
  int _resendCooldown = 60;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _startCooldown(); // OTP was already sent from AuthScreen
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _resendCooldown = 60;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        if (_resendCooldown > 0) {
          _resendCooldown--;
        } else {
          t.cancel();
        }
      });
    });
  }

  Future<void> _resendOtp() async {
    if (_resendCooldown > 0) return;
    setState(() { _isSendingOtp = true; _errorMsg = null; });
    final error = await _supabase.sendOtp(widget.email);
    if (!mounted) return;
    if (error != null) {
      setState(() { _errorMsg = error; _isSendingOtp = false; });
    } else {
      setState(() { _isSendingOtp = false; });
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OTP resent! Check your inbox.')),
      );
    }
  }

  Future<void> _verifyAndProceed() async {
    if (_otp.length < 6) {
      setState(() => _errorMsg = 'Please enter the 6-digit code.');
      return;
    }
    setState(() { _isVerifying = true; _errorMsg = null; });

    // 1. Verify OTP via Edge Function
    final otpError = await _supabase.verifyOtp(widget.email, _otp);
    if (!mounted) return;
    if (otpError != null) {
      setState(() { _isVerifying = false; _errorMsg = otpError; });
      return;
    }

    if (widget.isSignIn) {
      // ── SIGN IN mode: OTP verified → now sign in with email+password ──
      try {
        final userData = await _supabase.signIn(
          email: widget.email,
          password: widget.password,
        );
        if (!mounted) return;
        if (userData == null) {
          setState(() {
            _isVerifying = false;
            _errorMsg = 'Incorrect email or password.';
          });
          return;
        }

        // Persist session locally
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_logged_in', true);
        await prefs.setString('user_name', userData['name']);
        await prefs.setString('user_email', userData['email']);
        await prefs.setString('user_age', userData['age'] ?? '');
        await prefs.setString('userGender', userData['gender'] ?? 'Male');
        await prefs.setBool('is_guest', false);

        if (!mounted) return;
        await Provider.of<SettingsProvider>(context, listen: false)
            .updateProfile(userData['name'], userData['email'],
                gender: userData['gender'] ?? 'Male');

        // Wipe local DB before restoring so Guest data doesn't bleed into new account
        await DatabaseService().clearAllRecords();

        // Restore prayer history from cloud
        await SyncService.instance.restoreFromCloud();

        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
      } catch (e) {
        if (!mounted) return;
        setState(() { _isVerifying = false; _errorMsg = e.toString(); });
      }
    } else {
      // ── SIGN UP mode: OTP verified → create account ──
      final signUpError = await _supabase.signUpAfterOtp(
        email: widget.email,
        password: widget.password,
        name: widget.name,
        gender: widget.gender,
        age: widget.age,
      );
      if (!mounted) return;
      if (signUpError != null) {
        setState(() { _isVerifying = false; _errorMsg = signUpError; });
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', true);
      await prefs.setString('user_name', widget.name);
      await prefs.setString('user_email', widget.email);
      await prefs.setString('user_age', widget.age);
      await prefs.setString('userGender', widget.gender);
      await prefs.setBool('is_guest', false);

      if (!mounted) return;
      await Provider.of<SettingsProvider>(context, listen: false)
          .updateProfile(widget.name, widget.email, gender: widget.gender);

      // Wipe local DB so Guest data doesn't bleed into new account
      await DatabaseService().clearAllRecords();

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1A1008) : const Color(0xFFFAF6F0);
    final cardColor = isDark ? const Color(0xFF2C1F11) : Colors.white;
    final borderColor = isDark ? const Color(0xFF3D2E1A) : const Color(0xFFE8DDD0);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1008);
    final subColor = isDark ? const Color(0xFFA08060) : const Color(0xFF8B6914);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: subColor, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // Icon
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.gold.withValues(alpha: 0.12),
                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.4), width: 1.5),
                ),
                child: const Icon(Icons.mark_email_read_outlined,
                    color: AppColors.gold, size: 32),
              ),
              const SizedBox(height: 24),

              Text(
                'Verify Your Email',
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    letterSpacing: 0.3),
              ),
              const SizedBox(height: 10),
              RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: 14, color: subColor, height: 1.5),
                  children: [
                    const TextSpan(text: 'We sent a 6-digit code to\n'),
                    TextSpan(
                      text: widget.email,
                      style: const TextStyle(
                          color: AppColors.gold, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // Error box
              if (_errorMsg != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 20),
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

              // OTP input
              PinCodeTextField(
                appContext: context,
                length: 6,
                onChanged: (v) => _otp = v,
                onCompleted: (_) => _verifyAndProceed(),
                keyboardType: TextInputType.number,
                animationType: AnimationType.fade,
                enableActiveFill: true,
                autoFocus: true,
                pinTheme: PinTheme(
                  shape: PinCodeFieldShape.box,
                  borderRadius: BorderRadius.circular(12),
                  fieldHeight: 56,
                  fieldWidth: 46,
                  activeFillColor: cardColor,
                  inactiveFillColor: cardColor,
                  selectedFillColor: cardColor,
                  activeColor: AppColors.gold,
                  inactiveColor: borderColor,
                  selectedColor: AppColors.gold,
                ),
                textStyle: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: textColor),
              ),

              const SizedBox(height: 28),

              // Verify button
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
                  onPressed: _isVerifying ? null : _verifyAndProceed,
                  child: _isVerifying
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              color: Colors.black, strokeWidth: 2.5))
                      : Text(
                          widget.isSignIn ? 'Verify & Sign In' : 'Verify & Create Account',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),

              const SizedBox(height: 20),

              // Resend row
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Didn't receive it? ",
                        style: TextStyle(fontSize: 13, color: subColor)),
                    GestureDetector(
                      onTap: _resendCooldown == 0 && !_isSendingOtp
                          ? _resendOtp
                          : null,
                      child: _isSendingOtp
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  color: AppColors.gold, strokeWidth: 2))
                          : Text(
                              _resendCooldown > 0
                                  ? 'Resend in ${_resendCooldown}s'
                                  : 'Resend OTP',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _resendCooldown > 0
                                      ? subColor
                                      : AppColors.gold),
                            ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
