import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class LocationService {
  /// Returns true if the device's location (GPS) service is switched on.
  static Future<bool> isGpsEnabled() =>
      Geolocator.isLocationServiceEnabled();

  static Future<Position?> getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }

    if (permission == LocationPermission.deniedForever) return null;

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (e) {
      return null;
    }
  }


  /// Reverse geocode using OpenStreetMap Nominatim (free, no API key)
  static Future<String> getCityName(double lat, double lon) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=$lat&lon=$lon&format=json&accept-language=en',
      );
      final response = await http
          .get(url, headers: {'User-Agent': 'MySalahApp/1.0'})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>?;
        if (address != null) {
          final city = address['city'] as String? ??
              address['town'] as String? ??
              address['village'] as String? ??
              address['county'] as String?;
          final country = address['country'] as String?;
          if (city != null && country != null) return '$city, $country';
          if (city != null) return city;
        }
      }
    } catch (_) {
      // Fall through to default
    }
    return 'Your Location';
  }

  static double getTimezoneOffset() {
    return DateTime.now().timeZoneOffset.inMinutes / 60.0;
  }
}
