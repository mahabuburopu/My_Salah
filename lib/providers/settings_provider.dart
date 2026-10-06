import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/services/location_service.dart';
import '../data/services/supabase_service.dart';

class SettingsProvider extends ChangeNotifier {
  late SharedPreferences _prefs;

  // Profile
  String _userName = 'Muslim User';
  String _userEmail = 'user@example.com';
  String _userGender = 'Male';

  // Location
  bool _autoLocation = true;
  double _latitude = 23.8103;  // Default: Dhaka, Bangladesh
  double _longitude = 90.4125;
  String _cityName = 'Dhaka, Bangladesh';

  // Notifications
  bool _masterReminders = true;
  final Map<String, int> _reminderMinutes = {
    'Fajr': 30,
    'Dhuhr': 15,
    'Asr': 15,
    'Maghrib': 0,
    'Isha': 15,
  };

  // Calculation method
  int _calculationMethod = 3;
  int _asrMethod = 0; // 0=Standard(Shafi), 1=Hanafi
  bool _notificationsEnabled = true;

  // Getters
  String get userName => _userName;
  String get userEmail => _userEmail;
  String get userGender => _userGender;
  bool get autoLocation => _autoLocation;
  double get latitude => _latitude;
  double get longitude => _longitude;
  String get cityName => _cityName;
  bool get masterReminders => _masterReminders;
  bool get notificationsEnabled => _notificationsEnabled;
  Map<String, int> get reminderMinutes => _reminderMinutes;
  int get calculationMethod => _calculationMethod;
  int get asrMethod => _asrMethod;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _loadPrefs();
    if (_autoLocation) await _fetchLocation();
    notifyListeners();
  }

  void _loadPrefs() {
    _userName = _prefs.getString('user_name') ?? 'Muslim User';
    _userEmail = _prefs.getString('user_email') ?? 'user@example.com';
    _userGender = _prefs.getString('userGender') ?? 'Male';
    _autoLocation = _prefs.getBool('autoLocation') ?? true;
    _latitude = _prefs.getDouble('latitude') ?? 23.8103;
    _longitude = _prefs.getDouble('longitude') ?? 90.4125;
    _cityName = _prefs.getString('cityName') ?? 'Dhaka, Bangladesh';
    _masterReminders = _prefs.getBool('masterReminders') ?? true;
    _notificationsEnabled = _prefs.getBool('notificationsEnabled') ?? true;
    _calculationMethod = _prefs.getInt('calculationMethod') ?? 3;
    _asrMethod = _prefs.getInt('asrMethod') ?? 0;

    for (final prayer in ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha']) {
      _reminderMinutes[prayer] =
          _prefs.getInt('reminder_$prayer') ?? _reminderMinutes[prayer]!;
    }
  }

  Future<void> _fetchLocation() async {
    final position = await LocationService.getCurrentLocation();
    if (position != null) {
      _latitude = position.latitude;
      _longitude = position.longitude;
      _cityName = await LocationService.getCityName(_latitude, _longitude);
      await _prefs.setDouble('latitude', _latitude);
      await _prefs.setDouble('longitude', _longitude);
      await _prefs.setString('cityName', _cityName);
      notifyListeners();
    }
  }

  Future<void> updateProfile(String name, String email, {String? gender}) async {
    // Guard: ensure _prefs is initialized even if called before init() completes
    _prefs = await SharedPreferences.getInstance();
    _userName = name;
    _userEmail = email;
    if (gender != null) _userGender = gender;
    await _prefs.setString('user_name', name);
    await _prefs.setString('user_email', email);
    if (gender != null) await _prefs.setString('userGender', gender);
    notifyListeners();
  }

  Future<void> setAutoLocation(bool value) async {
    _autoLocation = value;
    await _prefs.setBool('autoLocation', value);
    if (value) await _fetchLocation();
    notifyListeners();
  }

  Future<void> setManualLocation(double lat, double lon, String city) async {
    _latitude = lat;
    _longitude = lon;
    _cityName = city;
    await _prefs.setDouble('latitude', lat);
    await _prefs.setDouble('longitude', lon);
    await _prefs.setString('cityName', city);
    notifyListeners();
  }

  Future<void> setMasterReminders(bool value) async {
    _masterReminders = value;
    await _prefs.setBool('masterReminders', value);
    notifyListeners();
  }

  Future<void> setReminderMinutes(String prayer, int minutes) async {
    _reminderMinutes[prayer] = minutes;
    await _prefs.setInt('reminder_$prayer', minutes);
    notifyListeners();
  }

  Future<void> setCalculationMethod(int method) async {
    _calculationMethod = method;
    await _prefs.setInt('calculationMethod', method);
    notifyListeners();
  }

  Future<void> setAsrMethod(int method) async {
    _asrMethod = method;
    await _prefs.setInt('asrMethod', method);
    notifyListeners();
  }

  Future<void> setNotifications(bool value) async {
    _notificationsEnabled = value;
    await _prefs.setBool('notificationsEnabled', value);
    notifyListeners();
  }

  String getReminderLabel(String prayer) {
    final mins = _reminderMinutes[prayer] ?? 0;
    if (mins == 0) return 'At Adhan';
    return '$mins min before';
  }

  /// Signs out from Supabase and clears all auth-related local data.
  /// Called from SettingsScreen logout button.
  Future<void> logout() async {
    // Sign out from Supabase (no-op for guests)
    await SupabaseService.instance.signOut();

    // Clear auth fields in SharedPreferences
    await _prefs.setBool('is_logged_in', false);
    await _prefs.remove('user_name');
    await _prefs.remove('user_email');
    await _prefs.remove('user_age');
    await _prefs.remove('userGender');
    await _prefs.remove('is_guest');

    // Reset in-memory profile
    _userName = 'Muslim User';
    _userEmail = 'user@example.com';
    _userGender = 'Male';
    notifyListeners();
  }
}
