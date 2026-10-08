import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

//Central service for all Supabase operations.
//Auth requires internet — all methods throw [SupabaseAuthException] or
//return a descriptive error string when offline or credentials fail.
class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  // Found at: Supabase Dashboard → Settings → API
  static const String _supabaseUrl = 'https://qrwrtgaerpivibeqkygj.supabase.co';
  static const String _supabaseAnonKey = 'sb_publishable__YSUGBezpkjqH6B5uOoeMg_tK0McElA';


  static SupabaseClient get _client => Supabase.instance.client;

  // Must be called once in main() before runApp.
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabaseAnonKey,
    );
  }

  //Session

  User? get currentUser => _client.auth.currentUser;
  bool get isSignedIn => _client.auth.currentUser != null;

  /// The currently signed-in user's UUID, or null for guest.
  String? get userId => _client.auth.currentUser?.id;

  // OTP & User Checks

  /// Checks if an email is already registered using the custom RPC function.
  Future<bool> checkEmailExists(String email) async {
    try {
      final res = await _client.rpc(
        'check_email_exists',
        params: {'lookup_email': email.trim().toLowerCase()},
      );
      return res == true;
    } catch (e) {
      debugPrint('checkEmailExists error: $e');
      // On error, default to false so we don't block legitimate signups if network fails.
      // Or throw to handle it in the UI. Let's return false to allow the attempt.
      return false;
    }
  }

  /// Sends a 6-digit OTP email via Brevo (through the Supabase Edge Function).
  /// Returns null on success, or an error message string on failure.
  Future<String?> sendOtp(String email) async {
    try {
      final response = await _client.functions.invoke(
        'Send-OTP',
        body: {'action': 'send', 'email': email.trim().toLowerCase()},
      );
      if (response.status != 200) {
        final data = response.data;
        return data is Map ? (data['error'] ?? 'Failed to send OTP') : 'Failed to send OTP';
      }
      return null; // success
    } catch (e) {
      debugPrint('sendOtp error: $e');
      final msg = e.toString();
      if (msg.contains('SocketException') || msg.contains('NetworkException')) {
        return 'No internet connection. Please check your network.';
      }
      return 'Server error. Please try again later. ($e)';
    }
  }

  /// Verifies the OTP entered by the user.
  /// Returns null on success, or an error message string on failure.
  Future<String?> verifyOtp(String email, String otp) async {
    try {
      final response = await _client.functions.invoke(
        'Send-OTP',
        body: {
          'action': 'verify',
          'email': email.trim().toLowerCase(),
          'otp': otp.trim(),
        },
      );
      if (response.status != 200) {
        final data = response.data;
        return data is Map
            ? (data['error'] ?? 'Invalid or expired OTP')
            : 'Invalid or expired OTP';
      }
      return null; // success
    } catch (e) {
      debugPrint('verifyOtp error: $e');
      final msg = e.toString();
      if (msg.contains('SocketException') || msg.contains('NetworkException')) {
        return 'No internet connection. Please check your network.';
      }
      return 'Server error. Please try again later. ($e)';
    }
  }

  // Sign Up

  /// Creates a Supabase Auth user + profile row after OTP is already verified.
  /// Returns null on success, or an error message string on failure.
  Future<String?> signUpAfterOtp({
    required String email,
    required String password,
    required String name,
    required String gender,
    required String age,
  }) async {
    try {
      // 1. Create auth user
      final res = await _client.auth.signUp(
        email: email.trim().toLowerCase(),
        password: password,
      );

      if (res.user == null) return 'Sign up failed. Please try again.';

      // 2. Insert profile row
      await _client.from('profiles').upsert({
        'id': res.user!.id,
        'name': name.trim(),
        'gender': gender,
        'age': age.trim(),
      });

      return null; // success
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      debugPrint('signUpAfterOtp error: $e');
      return 'Sign up failed. Please check your connection.';
    }
  }

  // Sign In

  /// Signs in an existing user with email + password.
  /// Returns a map with user data on success, or throws [String] error message.
  Future<Map<String, dynamic>?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _client.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );

      if (res.user == null) return null;

      // Fetch profile to get name, gender, age
      final profile = await _client
          .from('profiles')
          .select()
          .eq('id', res.user!.id)
          .maybeSingle();

      return {
        'id': res.user!.id,
        'email': res.user!.email ?? '',
        'name': profile?['name'] ?? 'User',
        'gender': profile?['gender'] ?? 'Male',
        'age': profile?['age'] ?? '',
      };
    } on AuthException catch (e) {
      throw e.message;
    } catch (e) {
      debugPrint('signIn error: $e');
      final msg = e.toString();
      if (msg.contains('SocketException') || msg.contains('NetworkException')) {
        throw 'No internet connection. Please check your network.';
      }
      throw 'Sign in failed. Please try again. ($e)';
    }
  }

  //Sign Out

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      debugPrint('signOut error: $e');
    }
  }

  //Cloud Prayer Records

  /// Upserts a batch of prayer records to Supabase.
  /// [records] is a list of maps matching the prayer_records schema.
  /// Returns true on success, false on failure.
  Future<bool> upsertPrayerRecords(
      List<Map<String, dynamic>> records) async {
    if (records.isEmpty) return true;
    try {
      await _client.from('prayer_records').upsert(
        records,
        onConflict: 'user_id,date,prayer_name',
      );
      return true;
    } catch (e) {
      debugPrint('upsertPrayerRecords error: $e');
      return false;
    }
  }

  /// Fetches ALL prayer records for the current user from Supabase.
  /// Used when signing in on a new device to restore history.
  Future<List<Map<String, dynamic>>> fetchAllPrayerRecords() async {
    try {
      final uid = userId;
      if (uid == null) return [];
      final data = await _client
          .from('prayer_records')
          .select('date, prayer_name, status, prayed_at')
          .eq('user_id', uid);
      return List<Map<String, dynamic>>.from(data as List);
    } catch (e) {
      debugPrint('fetchAllPrayerRecords error: $e');
      return [];
    }
  }
}
