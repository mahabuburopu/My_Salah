import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/prayer.dart';
import '../data/models/prayer_record.dart';
import '../data/services/aladhan_service.dart';
import '../data/services/database_service.dart';
import '../data/services/location_service.dart';
import '../data/services/notification_service.dart';
import '../data/services/sync_service.dart';
import '../core/utils/prayer_time_calculator.dart';

class PrayerProvider extends ChangeNotifier with WidgetsBindingObserver {
  final DatabaseService _db = DatabaseService();

  List<Prayer> _todayPrayers = [];
  Prayer? _nextPrayer;
  DateTime _now = DateTime.now();
  Timer? _timer;
  Timer? _syncTimer;
  Timer? _midnightTimer;
  Duration _timeToNextPrayer = Duration.zero;

  // Tracks the last calendar date on which _markPendingAsMissed ran.
  // Only re-run when the date has actually changed (i.e., midnight passed).
  String _lastMissedCheckDate = '';

  double _latitude = 23.8103;
  double _longitude = 90.4125;
  String _cityName = 'Dhaka, Bangladesh';
  bool _isLoading = false;
  String? _error;

  // Incremented whenever a prayer is marked — used by HistoryProvider to
  // know when to refresh, avoiding a refresh on every 1-second timer tick.
  int _markCount = 0;
  int get markCount => _markCount;

  // Calculation settings (kept in sync from SettingsProvider)
  int _calculationMethod = 3; // settings index (0-4)
  int _asrMethod = 0;         // 0=Shafi, 1=Hanafi

  /// Maps settings UI index → Aladhan API method code:
  /// 0=MWL(3), 1=ISNA(2), 2=Egyptian(5), 3=UmmAlQura(4), 4=Karachi(1)
  static int _toApiMethod(int settingsIndex) {
    const map = {0: 3, 1: 2, 2: 5, 3: 4, 4: 1};
    return map[settingsIndex] ?? 3;
  }

  // Raw prayer times (DateTime) for notification scheduling
  Map<String, DateTime> _rawPrayerTimes = {};

  List<Prayer> get todayPrayers => _todayPrayers;
  Prayer? get nextPrayer => _nextPrayer;
  DateTime get now => _now;
  Duration get timeToNextPrayer => _timeToNextPrayer;
  double get latitude => _latitude;
  double get longitude => _longitude;
  String get cityName => _cityName;
  bool get isLoading => _isLoading;
  String? get error => _error;

  PrayerProvider() {
    WidgetsBinding.instance.addObserver(this);
    _loadLocalImmediate();
    _startTimer();
    _scheduleMidnightTask();
    _loadLocationInBackground();
    // Only mark missed if the date changed since last check (i.e., midnight
    // passed before the app was opened). Safe to call on cold start.
    _markPendingAsMissedIfDateChanged();
  }

  //AppLifecycleObserver: sync notification responses on app resume
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Sync notification button actions from background
      _refreshStatusesFromNotificationService();
      // Only mark missed if midnight passed while app was backgrounded
      _markPendingAsMissedIfDateChanged();
    }
  }

  /// Calls _markPendingAsMissed only when the calendar date has advanced
  /// since the last time it ran. Prevents marking today's prayers as missed
  /// on every hot-restart or app resume.
  void _markPendingAsMissedIfDateChanged() {
    final todayKey = _dateKey(DateTime.now());
    if (todayKey != _lastMissedCheckDate) {
      _lastMissedCheckDate = todayKey;
      _markPendingAsMissed();
    }
  }

  void _loadLocalImmediate() {
    final today = DateTime.now();
    _loadCachedLocationAndBuild(today);
  }

  Future<void> _loadCachedLocationAndBuild(DateTime today) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedLat = prefs.getDouble('latitude');
    final cachedLon = prefs.getDouble('longitude');
    final cachedCity = prefs.getString('cityName');
    if (cachedLat != null && cachedLon != null) {
      _latitude = cachedLat;
      _longitude = cachedLon;
    }
    if (cachedCity != null && cachedCity.isNotEmpty) {
      _cityName = cachedCity;
    }

    final calc = PrayerTimeCalculator(
      latitude: _latitude,
      longitude: _longitude,
      timezone: LocationService.getTimezoneOffset(),
      date: today,
    );
    final localTimes = calc.getPrayerTimes();
    _rawPrayerTimes = {
      'Fajr': localTimes['Fajr']!,
      'Dhuhr': localTimes['Dhuhr']!,
      'Asr': localTimes['Asr']!,
      'Maghrib': localTimes['Maghrib']!,
      'Isha': localTimes['Isha']!,
    };

    // Read statuses right away — don't wait for location load to show correct state
    final notifStatuses = await NotificationService.loadTodayStatuses();
    final savedRecords = await _db.getPrayerRecordsForDate(today);
    final dbMap = {for (var r in savedRecords) r.prayerName: r.status};
    _buildPrayerList(_rawPrayerTimes, notifStatuses: notifStatuses, dbMap: dbMap);

    notifyListeners();
    _scheduleNotifications();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _now = DateTime.now();
      _updateNextPrayerCountdown();
      notifyListeners();
    });

    // Every 15 seconds: sync notification button responses into the UI
    _syncTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      await _refreshStatusesFromNotificationService();
      _autoMarkExpiredAsPending();
    });
  }

  /// When a prayer's window expires, update the in-memory list to `pending`
  /// for visual display only — NO DB write happens here.
  /// Only at midnight does `_markPendingAsMissed()` write `missed` to the DB.
  void _autoMarkExpiredAsPending() {
    bool changed = false;

    for (int i = 0; i < _todayPrayers.length; i++) {
      final prayer = _todayPrayers[i];

      // Only act on unlocked prayers whose window has expired
      if (prayer.status == PrayerStatus.upcoming &&
          !prayer.isLocked &&
          isPrayerWindowExpired(prayer)) {
        // Update in-memory only — do NOT persist to DB.
        // The midnight timer is the sole trigger for writing missed/pending
        // to the permanent record.
        _todayPrayers[i] = prayer.copyWith(status: PrayerStatus.pending);
        changed = true;
      }
    }

    if (changed) {
      _updateNextPrayer();
      notifyListeners();
    }
  }

  /// Schedule a timer to fire at the next midnight to auto-mark pending → missed
  void _scheduleMidnightTask() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 0, 0, 5);
    final durationToMidnight = tomorrow.difference(now);

    _midnightTimer?.cancel();
    _midnightTimer = Timer(durationToMidnight, () async {
      // Midnight has genuinely passed — reset the check date so the guard
      // allows the next call through, then run immediately.
      _lastMissedCheckDate = '';
      _markPendingAsMissedIfDateChanged();
      await _fetchPrayerTimes();
      _scheduleMidnightTask();
    });
  }

  /// At midnight: find yesterday's prayers that are still pending/upcoming → mark as missed
  Future<void> _markPendingAsMissed() async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yesterdayKey = _dateKey(yesterday);

    final savedRecords = await _db.getPrayerRecordsForDate(yesterday);
    final dbMap = {for (var r in savedRecords) r.prayerName: r.status};

    for (final name in PrayerName.values) {
      final prayerKey = name.displayName;

      // Check both DB and SharedPreferences (notifications save to prefs)
      final dbStatus = dbMap[name];
      final prefsStatusStr =
          await NotificationService.getPrayerStatus(prayerKey, yesterdayKey);

      // A prayer is "finalized" only if a real (non-upcoming, non-pending)
      // status was explicitly stored. We must check the raw string for the
      // prefs side — toPrayerStatus(null) returns `upcoming`, so checking
      // the enum alone would incorrectly treat a missing entry as finalized.
      final isDbFinalized = dbStatus != null &&
          dbStatus != PrayerStatus.upcoming &&
          dbStatus != PrayerStatus.pending;

      final isPrefsFinalized = prefsStatusStr != null &&
          prefsStatusStr != 'upcoming' &&
          prefsStatusStr != 'pending';

      final isFinalized = isDbFinalized || isPrefsFinalized;

      if (!isFinalized) {
        await _db.savePrayerRecord(PrayerRecord(
          date: yesterday,
          prayerName: name,
          status: PrayerStatus.missed,
          prayedAt: null,
        ));
        await NotificationService.savePrayerStatus(
            prayerKey, yesterdayKey, 'missed');
      }
    }
  }

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  void updateLocation(double lat, double lon) {
    if ((lat - _latitude).abs() > 0.01 || (lon - _longitude).abs() > 0.01) {
      _latitude = lat;
      _longitude = lon;
      _fetchPrayerTimes();
    }
  }

  void clear() {
    _fetchPrayerTimes();
  }


  /// Called by ProxyProvider when settings change (calc method, asr method, or location).
  void updateSettings({
    required double lat,
    required double lon,
    required int calculationMethod,
    required int asrMethod,
  }) {
    bool needsRefetch = false;

    if ((lat - _latitude).abs() > 0.01 || (lon - _longitude).abs() > 0.01) {
      _latitude = lat;
      _longitude = lon;
      needsRefetch = true;
    }
    if (_calculationMethod != calculationMethod) {
      _calculationMethod = calculationMethod;
      needsRefetch = true;
    }
    if (_asrMethod != asrMethod) {
      _asrMethod = asrMethod;
      needsRefetch = true;
    }

    if (needsRefetch) _fetchPrayerTimes();
  }

  Future<void> updateLocationFromGPS() async {
    _isLoading = true;
    notifyListeners();
    await _loadLocationInBackground();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadLocationInBackground() async {
    final position = await LocationService.getCurrentLocation();
    if (position != null) {
      _latitude = position.latitude;
      _longitude = position.longitude;
      _cityName = await LocationService.getCityName(_latitude, _longitude);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('latitude', _latitude);
      await prefs.setDouble('longitude', _longitude);
      await prefs.setString('cityName', _cityName);

      await _fetchPrayerTimes();
    }
  }

  Future<void> _fetchPrayerTimes() async {
    final today = DateTime.now();

    final apiTimes = await AladhanService.getPrayerTimes(
      latitude: _latitude,
      longitude: _longitude,
      date: today,
      method: _toApiMethod(_calculationMethod),
      asrMethod: _asrMethod,
    );

    Map<String, DateTime> times;
    if (apiTimes != null) {
      times = {
        'Fajr': AladhanService.parseTimeString(apiTimes['Fajr']!, today),
        'Dhuhr': AladhanService.parseTimeString(apiTimes['Dhuhr']!, today),
        'Asr': AladhanService.parseTimeString(apiTimes['Asr']!, today),
        'Maghrib': AladhanService.parseTimeString(apiTimes['Maghrib']!, today),
        'Isha': AladhanService.parseTimeString(apiTimes['Isha']!, today),
      };
    } else {
      final calc = PrayerTimeCalculator(
        latitude: _latitude,
        longitude: _longitude,
        timezone: LocationService.getTimezoneOffset(),
        date: today,
        asrMethod: _asrMethod,
      );
      final localTimes = calc.getPrayerTimes();
      times = {
        'Fajr': localTimes['Fajr']!,
        'Dhuhr': localTimes['Dhuhr']!,
        'Asr': localTimes['Asr']!,
        'Maghrib': localTimes['Maghrib']!,
        'Isha': localTimes['Isha']!,
      };
    }

    _rawPrayerTimes = times;

    final notifStatuses = await NotificationService.loadTodayStatuses();
    final savedRecords = await _db.getPrayerRecordsForDate(today);
    final dbMap = {for (var r in savedRecords) r.prayerName: r.status};

    _buildPrayerList(times, notifStatuses: notifStatuses, dbMap: dbMap);
    notifyListeners();

    await _scheduleNotifications();
  }


  void _buildPrayerList(
    Map<String, DateTime> times, {
    required Map<String, PrayerStatus> notifStatuses,
    required Map<PrayerName, PrayerStatus> dbMap,
  }) {
    _todayPrayers = [
      Prayer(
        name: PrayerName.fajr,
        time: times['Fajr']!,
        status: _resolveStatus(
            PrayerName.fajr, 'Fajr', times['Fajr']!, notifStatuses, dbMap),
      ),
      Prayer(
        name: PrayerName.dhuhr,
        time: times['Dhuhr']!,
        status: _resolveStatus(
            PrayerName.dhuhr, 'Dhuhr', times['Dhuhr']!, notifStatuses, dbMap),
      ),
      Prayer(
        name: PrayerName.asr,
        time: times['Asr']!,
        status: _resolveStatus(
            PrayerName.asr, 'Asr', times['Asr']!, notifStatuses, dbMap),
      ),
      Prayer(
        name: PrayerName.maghrib,
        time: times['Maghrib']!,
        status: _resolveStatus(PrayerName.maghrib, 'Maghrib', times['Maghrib']!,
            notifStatuses, dbMap),
      ),
      Prayer(
        name: PrayerName.isha,
        time: times['Isha']!,
        status: _resolveStatus(
            PrayerName.isha, 'Isha', times['Isha']!, notifStatuses, dbMap),
      ),
    ];
    _updateNextPrayer();
  }

  PrayerStatus _resolveStatus(
    PrayerName name,
    String key,
    DateTime prayerTime,
    Map<String, PrayerStatus> notifStatuses,
    Map<PrayerName, PrayerStatus> dbMap,
  ) {
    final dbStatus = dbMap[name];
    final notifStatus = notifStatuses[key];

    // 1. DB finalized status always wins — but only for user-confirmed statuses.
    //    `missed` is excluded here: it is written by the midnight timer for the
    //    PREVIOUS day's records, so if it appears for today it is stale/corrupt.
    //    The midnight timer will correctly write `missed` at day-end.
    final isDbFinalized = dbStatus != null &&
        dbStatus != PrayerStatus.upcoming &&
        dbStatus != PrayerStatus.pending &&
        dbStatus != PrayerStatus.missed; // ← never trust today's missed from DB
    if (isDbFinalized) return dbStatus;

    // 2. Notification service has a finalized status → use it and it will be
    //    persisted to DB on the next 15-second sync
    final isNotifFinalized = notifStatus != null &&
        notifStatus != PrayerStatus.upcoming &&
        notifStatus != PrayerStatus.pending;
    if (isNotifFinalized) return notifStatus;

    // 3. Pending from either source
    if (dbStatus == PrayerStatus.pending) return PrayerStatus.pending;
    if (notifStatus == PrayerStatus.pending) return PrayerStatus.pending;

    // 4. Default: upcoming
    return PrayerStatus.upcoming;
  }

  /// Refresh statuses from notification service (called on resume + every minute)
  Future<void> _refreshStatusesFromNotificationService() async {
    final notifStatuses = await NotificationService.loadTodayStatuses();
    bool changed = false;
    for (int i = 0; i < _todayPrayers.length; i++) {
      final prayer = _todayPrayers[i];
      final key = prayer.name.displayName;
      final newStatus = notifStatuses[key] ?? PrayerStatus.upcoming;
      if (newStatus != prayer.status && newStatus != PrayerStatus.upcoming) {
        _todayPrayers[i] = prayer.copyWith(status: newStatus);
        changed = true;
        // Persist to DB
        await _db.savePrayerRecord(PrayerRecord(
          date: DateTime.now(),
          prayerName: prayer.name,
          status: newStatus,
          prayedAt: newStatus == PrayerStatus.pending ? null : DateTime.now(),
        ));
      }
    }
    if (changed) {
      _updateNextPrayer();
      notifyListeners();
    }
  }

  Future<void> _scheduleNotifications() async {
    if (_rawPrayerTimes.isNotEmpty) {
      await NotificationService.scheduleTodayNotifications(_rawPrayerTimes);
    }
  }

  void _updateNextPrayer() {
    final now = DateTime.now();
    _nextPrayer = null;
    for (final prayer in _todayPrayers) {
      if (prayer.time.isAfter(now)) {
        _nextPrayer = prayer;
        break;
      }
    }
    if (_nextPrayer == null && _todayPrayers.isNotEmpty) {
      _nextPrayer = _todayPrayers.first;
    }
    _updateNextPrayerCountdown();
  }

  void _updateNextPrayerCountdown() {
    if (_nextPrayer != null) {
      final remaining = _nextPrayer!.time.difference(DateTime.now());
      _timeToNextPrayer = remaining.isNegative ? Duration.zero : remaining;
    }
  }

  /// Returns true if a prayer is currently in its active window.
  ///
  /// Special rules:
  /// • Fajr  — window = [Fajr time .. Fajr time + 90 min] (before sunrise)
  /// • Maghrib — window = [Maghrib time .. Isha time]  (already handled by idx logic)
  /// • Dhuhr / Asr — window = [prayer time .. next prayer time]
  /// • Isha  — window = [Isha time .. midnight]
  bool isPrayerWindowOpen(Prayer prayer) {
    final now = DateTime.now();
    if (prayer.time.isAfter(now)) return false; // hasn't started yet

    // ── Fajr special case: window closes 90 minutes after Fajr ──
    if (prayer.name == PrayerName.fajr) {
      final fajrDeadline = prayer.time.add(const Duration(minutes: 90));
      return now.isBefore(fajrDeadline);
    }

    // ── All other prayers: window = prayer time → next prayer time ──
    final idx = _todayPrayers.indexOf(prayer);
    if (idx < _todayPrayers.length - 1) {
      final nextPrayerTime = _todayPrayers[idx + 1].time;
      return now.isBefore(nextPrayerTime);
    }

    // Isha: window is open until midnight
    final midnight = DateTime(now.year, now.month, now.day + 1, 0, 0);
    return now.isBefore(midnight);
  }

  /// Returns true if the prayer time has passed AND the window is closed
  bool isPrayerWindowExpired(Prayer prayer) {
    final now = DateTime.now();
    if (prayer.time.isAfter(now)) return false;
    return !isPrayerWindowOpen(prayer);
  }

  /// Mark prayer from UI — respects lock (returns false if already locked)
  Future<bool> markPrayer(Prayer prayer, PrayerStatus status) async {
    final index = _todayPrayers.indexOf(prayer);
    if (index == -1) return false;

    if (_todayPrayers[index].isLocked) return false;

    final success = await NotificationService.markFromUI(
        prayer.name.displayName, status);
    if (!success) return false;

    _todayPrayers[index] = prayer.copyWith(status: status);

    final record = PrayerRecord(
      date: DateTime.now(),
      prayerName: prayer.name,
      status: status,
      prayedAt: status == PrayerStatus.pending ? null : DateTime.now(),
    );
    await _db.savePrayerRecord(record);

    // Background sync to Supabase (fire-and-forget — does not block UI)
    SyncService.instance.syncIfOnline();

    _updateNextPrayer();
    _markCount++;
    notifyListeners();
    return true;
  }

  Future<void> refresh() async {
    await _fetchPrayerTimes();
  }

  double get progressToNextPrayer {
    if (_nextPrayer == null || _todayPrayers.isEmpty) return 0;
    final idx = _todayPrayers.indexOf(_nextPrayer!);
    final prevPrayer = idx > 0 ? _todayPrayers[idx - 1] : null;
    final from =
        prevPrayer?.time ?? DateTime(_now.year, _now.month, _now.day, 0, 0);
    final to = _nextPrayer!.time;
    final totalDuration = to.difference(from).inSeconds;
    if (totalDuration <= 0) return 0;
    final elapsed = _now.difference(from).inSeconds;
    return (elapsed / totalDuration).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _syncTimer?.cancel();
    _midnightTimer?.cancel();
    super.dispose();
  }
}
