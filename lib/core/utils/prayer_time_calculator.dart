import 'dart:math';

/// Calculates Islamic prayer times based on geographic coordinates
class PrayerTimeCalculator {
  final double latitude;
  final double longitude;
  final double timezone;
  final DateTime date;
  /// 0 = Standard Shafi (shadow factor 1), 1 = Hanafi (shadow factor 2)
  final int asrMethod;

  PrayerTimeCalculator({
    required this.latitude,
    required this.longitude,
    required this.timezone,
    required this.date,
    this.asrMethod = 0,
  });

  // Calculation constants
  static const double _fajrAngle = 18.0;
  static const double _ishaAngle = 17.0;

  Map<String, DateTime> getPrayerTimes() {
    final jd = _julianDay(date.year, date.month, date.day);
    final d = jd - 2451545.0;

    final g = _sunMeanAnomaly(d);
    final q = _sunMeanLongitude(d);
    final l = _sunTrueLongitude(g, q);
    final e = _obliquityEcliptic(d);
    final ra = _rightAscension(l, e);
    final dec = _sunDeclination(l, e);
    final eq = _equationOfTime(g, q, l, ra);

    final transit = _getTransit(eq);
    final sunrise = _getSunriseTime(dec, transit);
    final sunset = _getSunsetTime(dec, transit);

    final fajrTime = _getAngleTime(dec, transit, _fajrAngle, true);
    final ishaTime = _getAngleTime(dec, transit, _ishaAngle, false);
    final asrTime = _getAsrTime(dec, transit);
    final maghribTime = sunset;

    return {
      'Fajr': _timeToDateTime(fajrTime),
      'Sunrise': _timeToDateTime(sunrise),
      'Dhuhr': _timeToDateTime(transit),
      'Asr': _timeToDateTime(asrTime),
      'Maghrib': _timeToDateTime(maghribTime),
      'Isha': _timeToDateTime(ishaTime),
    };
  }

  double _julianDay(int year, int month, int day) {
    if (month <= 2) {
      year -= 1;
      month += 12;
    }
    final a = (year / 100).floor();
    final b = 2 - a + (a / 4).floor();
    return (365.25 * (year + 4716)).floor() +
        (30.6001 * (month + 1)).floor() +
        day +
        b -
        1524.5;
  }

  double _sunMeanAnomaly(double d) {
    return _fixAngle(357.529 + 0.98560028 * d);
  }

  double _sunMeanLongitude(double d) {
    return _fixAngle(280.459 + 0.98564736 * d);
  }

  double _sunTrueLongitude(double g, double q) {
    final gRad = _degreesToRadians(g);
    return _fixAngle(
        q + 1.915 * sin(gRad) + 0.020 * sin(2 * gRad));
  }

  double _obliquityEcliptic(double d) {
    return 23.439 - 0.0000004 * d;
  }

  double _rightAscension(double l, double e) {
    final lRad = _degreesToRadians(l);
    final eRad = _degreesToRadians(e);
    return _radiansToDegrees(atan2(cos(eRad) * sin(lRad), cos(lRad)));
  }

  double _sunDeclination(double l, double e) {
    final lRad = _degreesToRadians(l);
    final eRad = _degreesToRadians(e);
    return _radiansToDegrees(asin(sin(eRad) * sin(lRad)));
  }

  double _equationOfTime(double g, double q, double l, double ra) {
    return q - 0.0057183 - ra + 0.00478 * sin(_degreesToRadians(2 * q - 2 * l)) -
        0.00045 * sin(_degreesToRadians(2 * q));
  }

  double _getTransit(double eq) {
    return 12 + timezone - longitude / 15 - eq;
  }

  double _getSunriseTime(double dec, double transit) {
    final latRad = _degreesToRadians(latitude);
    final decRad = _degreesToRadians(dec);
    final h0 = acos(-tan(latRad) * tan(decRad) -
        sin(_degreesToRadians(0.833)) / (cos(latRad) * cos(decRad)));
    return transit - _radiansToDegrees(h0) / 15;
  }

  double _getSunsetTime(double dec, double transit) {
    final latRad = _degreesToRadians(latitude);
    final decRad = _degreesToRadians(dec);
    final h0 = acos(-tan(latRad) * tan(decRad) -
        sin(_degreesToRadians(0.833)) / (cos(latRad) * cos(decRad)));
    return transit + _radiansToDegrees(h0) / 15;
  }

  double _getAngleTime(double dec, double transit, double angle, bool isBefore) {
    final latRad = _degreesToRadians(latitude);
    final decRad = _degreesToRadians(dec);
    final cosH = (sin(_degreesToRadians(-angle)) -
        sin(latRad) * sin(decRad)) /
        (cos(latRad) * cos(decRad));
    if (cosH.abs() > 1) return isBefore ? transit - 1 : transit + 1;
    final h = _radiansToDegrees(acos(cosH));
    return isBefore ? transit - h / 15 : transit + h / 15;
  }

  double _getAsrTime(double dec, double transit) {
    final latRad = _degreesToRadians(latitude);
    final decRad = _degreesToRadians(dec);
    // 0 = Shafi shadow factor 1, 1 = Hanafi shadow factor 2
    final shadowFactor = asrMethod == 1 ? 2.0 : 1.0;
    final midnoonAlt = 90 - (latitude - dec).abs();
    final asrAlt = _radiansToDegrees(
        atan(1.0 / (shadowFactor + tan(_degreesToRadians(midnoonAlt.abs())))));
    final cosH = (sin(_degreesToRadians(asrAlt)) -
        sin(latRad) * sin(decRad)) /
        (cos(latRad) * cos(decRad));
    if (cosH.abs() > 1) return transit + 4;
    final h = _radiansToDegrees(acos(cosH));
    return transit + h / 15;
  }

  DateTime _timeToDateTime(double time) {
    final totalMinutes = (time * 60).round();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return DateTime(date.year, date.month, date.day, hours.clamp(0, 23), minutes.clamp(0, 59));
  }

  double _fixAngle(double a) {
    a = a % 360;
    if (a < 0) a += 360;
    return a;
  }

  double _degreesToRadians(double d) => d * pi / 180;
  double _radiansToDegrees(double r) => r * 180 / pi;
}
