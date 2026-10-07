/// Converts Gregorian dates to Hijri calendar dates
class HijriConverter {
  static Map<String, dynamic> toHijri(DateTime gregorian) {
    int gy = gregorian.year;
    int gm = gregorian.month;
    int gd = gregorian.day;

    // Convert to Julian Day Number (a unique number)
    int jd = _gregorianToJD(gy, gm, gd);

    // Convert Julian Day to Hijri
    return _jdToHijri(jd);
  }

  static int _gregorianToJD(int y, int m, int d) {
    if (m <= 2) {
      y--;
      m += 12;
    }
    int a = y ~/ 100; //int (only the floor)
    int b = 2 - a + a ~/ 4;
    return (365.25 * (y + 4716)).toInt() +
        (30.6001 * (m + 1)).toInt() +
        d +
        b -
        1524;
  }

  static Map<String, dynamic> _jdToHijri(int jd) {
    jd = jd - 1948440 + 10632;
    int n = (jd - 1) ~/ 10631;
    jd = jd - 10631 * n + 354;
    int j = ((10985 - jd) ~/ 5316) * ((50 * jd) ~/ 17719) +
        (jd ~/ 5670) * ((43 * jd) ~/ 15238);
    jd = jd - ((30 - j) ~/ 15) * ((17719 * j) ~/ 50) - (j ~/ 16) * ((15238 * j) ~/ 43) + 29;
    int m = (24 * jd) ~/ 709;
    int d = jd - (709 * m) ~/ 24;
    int y = 30 * n + j - 30;

    return {'year': y, 'month': m, 'day': d};
  }

  static String getHijriMonthName(int month) {
    const months = [
      'Muharram', 'Safar', "Rabi' al-Awwal", "Rabi' al-Thani",
      'Jumada al-Awwal', 'Jumada al-Thani', 'Rajab', "Sha'ban",
      'Ramadan', 'Shawwal', "Dhu al-Qi'dah", 'Dhu al-Hijjah'
    ];
    if (month < 1 || month > 12) return '';
    return months[month - 1];
  }

  static String formatHijri(DateTime gregorian) {
    final h = toHijri(gregorian);
    return '${h['day']} ${getHijriMonthName(h['month'])} ${h['year']}'; //value to string
  }

  static String formatHijriShort(DateTime gregorian) {
    final h = toHijri(gregorian);
    return '${h['day']} ${getHijriMonthName(h['month'])}';
  }
}
