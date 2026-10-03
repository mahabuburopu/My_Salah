import 'package:flutter/foundation.dart';
import '../data/models/prayer.dart';
import '../data/models/prayer_record.dart';
import '../data/services/database_service.dart';

class HistoryProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();

  DateTime _selectedDate = DateTime.now();
  DateTime _focusedMonth = DateTime.now();
  final Map<DateTime, List<PrayerRecord>> _recordsCache = {};
  List<PrayerRecord> _selectedDateRecords = [];
  bool _isLoading = false;

  // Tracks the last markCount seen from PrayerProvider.
  // Refresh only fires when this changes — not on every 1-second tick.
  int _lastMarkCount = 0;

  DateTime get selectedDate => _selectedDate;
  DateTime get focusedMonth => _focusedMonth;
  List<PrayerRecord> get selectedDateRecords => _selectedDateRecords;
  bool get isLoading => _isLoading;

  HistoryProvider() {
    loadMonth(_focusedMonth);
  }

  /// Called by ProxyProvider every time PrayerProvider notifies.
  /// Only does real DB work when markCount actually increased.
  void onMarkCountChanged(int markCount) {
    if (_lastMarkCount != markCount) {
      _lastMarkCount = markCount;
      refresh();
    }
  }

  Future<void> loadMonth(DateTime month) async {
    _isLoading = true;
    notifyListeners();

    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 0);

    final records = await _db.getPrayerRecordsInRange(start, end);

    _recordsCache.clear();
    for (final record in records) {
      final key =
          DateTime(record.date.year, record.date.month, record.date.day);
      _recordsCache[key] ??= [];
      _recordsCache[key]!.add(record);
    }

    _isLoading = false;
    await _loadSelectedDate();
  }

  Future<void> _loadSelectedDate() async {
    final key =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    if (_recordsCache.containsKey(key)) {
      _selectedDateRecords = _recordsCache[key]!;
    } else {
      _selectedDateRecords = await _db.getPrayerRecordsForDate(_selectedDate);
    }
    notifyListeners();
  }

  void selectDate(DateTime date) {
    _selectedDate = date;
    _loadSelectedDate();
  }

  void changeMonth(DateTime month) {
    _focusedMonth = month;
    loadMonth(month);
  }

  /// Returns color marker info for a day (used by calendar builder).
  Map<String, int> getDayStatus(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    final records = _recordsCache[key] ?? [];
    int onTime = 0, qaza = 0, missed = 0;
    for (final r in records) {
      if (r.status == PrayerStatus.onTime) onTime++;
      if (r.status == PrayerStatus.qaza) qaza++;
      if (r.status == PrayerStatus.missed) missed++;
    }
    return {'onTime': onTime, 'qaza': qaza, 'missed': missed};
  }

  bool hasRecordsForDay(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return _recordsCache.containsKey(key) && _recordsCache[key]!.isNotEmpty;
  }

  Future<void> refresh() async {
    await loadMonth(_focusedMonth);
  }

  void clear() {
    _recordsCache.clear();
    _selectedDateRecords.clear();
    notifyListeners();
  }
}
