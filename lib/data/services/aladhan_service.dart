import 'dart:convert';
import 'package:http/http.dart' as http;

class AladhanService {
  static const String _baseUrl = 'https://api.aladhan.com/v1';

  /// Fetch prayer times from Aladhan API.
  /// [method]    — Aladhan API code: 1=Karachi, 2=ISNA, 3=MWL, 4=UmmAlQura, 5=Egyptian
  /// [asrMethod] — 0=Shafi (standard), 1=Hanafi
  static Future<Map<String, String>?> getPrayerTimes({
    required double latitude,
    required double longitude,
    required DateTime date,
    int method = 3,
    int asrMethod = 0,
  }) async {
    try {
      final dateStr = '${date.day}-${date.month}-${date.year}';
      // The Aladhan `school` param: 0=Shafi, 1=Hanafi
      final url = Uri.parse(
        '$_baseUrl/timings/$dateStr'
        '?latitude=$latitude'
        '&longitude=$longitude'
        '&method=$method'
        '&school=$asrMethod',
      );

      final response =
          await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final timings = data['data']['timings'] as Map<String, dynamic>;
        return {
          'Fajr': timings['Fajr'] as String,
          'Dhuhr': timings['Dhuhr'] as String,
          'Asr': timings['Asr'] as String,
          'Maghrib': timings['Maghrib'] as String,
          'Isha': timings['Isha'] as String,
        };
      }
    } catch (e) {
      // Will fall back to local calculation
    }
    return null;
  }

  /// Parse "HH:MM" string to DateTime on a specific date
  static DateTime parseTimeString(String timeStr, DateTime date) {
    final parts = timeStr.split(':');
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1].substring(0, 2)) ?? 0;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }
}
