import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../../data/models/prayer.dart';


@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse response) async {
  // Initialize bindings & plugin so SharedPreferences writes and
  // notification cancels complete before the background isolate exits.
  WidgetsFlutterBinding.ensureInitialized();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await NotificationService._plugin.initialize(
    const InitializationSettings(android: androidInit),
  );
  await NotificationService._handleActionBackground(response);
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // Notification IDs per prayer
  // Main at base, reminders at base+1..base+8, qaza at base+50..base+58
  static const Map<String, int> _baseIds = {
    'Fajr': 100,
    'Dhuhr': 200,
    'Asr': 300,
    'Maghrib': 400,
    'Isha': 500,
  };

  // Reminder intervals (minutes)
  static const Map<String, int> _intervalMin = {
    'Fajr': 5,
    'Dhuhr': 15,
    'Asr': 15,
    'Maghrib': 5,
    'Isha': 15,
  };

  static const int _maxReminders = 6; // how many reminder pings per prayer

  // Prayer order for Qaza lookups
  static const List<String> _prayerOrder = [
    'Fajr',
    'Dhuhr',
    'Asr',
    'Maghrib',
    'Isha'
  ];

  // Initialization 
  static Future<void> initialize() async {
    // Setup timezone using system UTC offset — no extra plugin needed
    tz_data.initializeTimeZones();
    try {
      final location = _guessTimezone(
          DateTime.now().timeZoneOffset.inMinutes);
      tz.setLocalLocation(tz.getLocation(location));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    // Android initialization
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleActionForeground,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    // Request permission on Android 13+
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }

    // Create notification channel
    await _createChannel();
  }

  static Future<void> _createChannel() async {
    const channel = AndroidNotificationChannel(
      'salah_prayer_channel',
      'Prayer Notifications',
      description: 'Notifications for prayer times and reminders',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  // Schedule all today's notifications
  static Future<void> scheduleTodayNotifications(
      Map<String, DateTime> prayerTimes) async {
    final now = DateTime.now();
    final todayKey = _dateKey(now);
    
    final prefs = await SharedPreferences.getInstance();
    final gender = prefs.getString('userGender') ?? 'Male';

    for (int i = 0; i < _prayerOrder.length; i++) {
      final prayerName = _prayerOrder[i];
      final prayerTime = prayerTimes[prayerName];
      if (prayerTime == null) continue;

      // Skip if status is already locked
      final status = await getPrayerStatus(prayerName, todayKey);
      if (_isLocked(status)) continue;

      // Schedule Qaza check (when this prayer begins → check prev prayer) 
      if (i > 0 && prayerTime.isAfter(now)) {
        final prevPrayer = _prayerOrder[i - 1];
        final prevStatus = await getPrayerStatus(prevPrayer, todayKey);
        if (prevStatus == 'pending') {
          await _scheduleQazaCheck(
            prayerName: prevPrayer,
            atTime: prayerTime,
            dateKey: todayKey,
          );
        }
      }

      // Schedule main prayer notification + reminders
      if (prayerTime.isAfter(now)) {
        await _schedulePrayerSeries(
          prayerName: prayerName,
          displayPrayerName: _getDisplayPrayerName(prayerName, now, gender),
          prayerTime: prayerTime,
          dateKey: todayKey,
        );
      }
    }

    // Schedule end-of-day processing (just after Isha + 3 hours)
    final isha = prayerTimes['Isha'];
    if (isha != null) {
      final eod = isha.add(const Duration(hours: 3));
      if (eod.isAfter(now)) {
        await _scheduleEOD(eod, todayKey, prayerTimes);
      }
    }
  }

  // Schedule main prayer notification + reminders
  static Future<void> _schedulePrayerSeries({
    required String prayerName,
    required String displayPrayerName,
    required DateTime prayerTime,
    required String dateKey,
  }) async {
    final baseId = _baseIds[prayerName]!;
    final interval = _intervalMin[prayerName]!;
    final payload = '$prayerName|ontime|$dateKey';

    final notifDetails = _buildNotificationDetails(
      title: '🔔 $displayPrayerName Prayer Time',
      body: 'Have you prayed $displayPrayerName?',
      payload: payload,
    );

    // Main notification at prayer time
    await _scheduleAt(
      id: baseId,
      title: '🔔 $displayPrayerName Prayer Time',
      body: 'Have you prayed $displayPrayerName?',
      scheduledTime: prayerTime,
      details: notifDetails,
      payload: payload,
    );

    // Reminders at intervals
    for (int r = 1; r <= _maxReminders; r++) {
      final reminderTime =
          prayerTime.add(Duration(minutes: interval * r));
      if (reminderTime.isBefore(DateTime.now())) continue;

      await _scheduleAt(
        id: baseId + r,
        title: '🔔 $displayPrayerName Reminder',
        body: 'Have you prayed $displayPrayerName yet?',
        scheduledTime: reminderTime,
        details: notifDetails,
        payload: payload,
      );
    }
  }

  // Schedule Qaza check notification 
  static Future<void> _scheduleQazaCheck({
    required String prayerName,
    required DateTime atTime,
    required String dateKey,
  }) async {
    final baseId = _baseIds[prayerName]! + 50;
    final payload = '$prayerName|qaza|$dateKey';

    final details = _buildNotificationDetails(
      title: '⚠️ Missed $prayerName',
      body: 'You missed $prayerName. Have you prayed it as Qaza?',
      payload: payload,
    );

    // Slightly after the new prayer starts
    final checkTime = atTime.add(const Duration(minutes: 1));
    if (checkTime.isBefore(DateTime.now())) return;

    await _scheduleAt(
      id: baseId,
      title: '⚠️ Missed $prayerName',
      body: 'You missed $prayerName. Have you prayed it as Qaza?',
      scheduledTime: checkTime,
      details: details,
      payload: payload,
    );

    // One reminder for Qaza check
    final reminderTime = checkTime.add(const Duration(minutes: 30));
    await _scheduleAt(
      id: baseId + 1,
      title: '⚠️ $prayerName Still Pending',
      body:
          'You still have a pending $prayerName prayer. Have you made it up?',
      scheduledTime: reminderTime,
      details: details,
      payload: payload,
    );
  }

  static String _getDisplayPrayerName(String prayerName, DateTime date, String gender) {
    if (prayerName == 'Dhuhr' && date.weekday == DateTime.friday && gender == 'Male') {
      return 'Jumah';
    }
    return prayerName;
  }

  // Schedule end-of-day processing
  static Future<void> _scheduleEOD(
      DateTime eodTime, String dateKey, Map<String, DateTime> times) async {
    // This notification triggers a silent check — any still-pending prayers
    // get marked as 'missed'. We use ID 999 for EOD.
    await _scheduleAt(
      id: 999,
      title: 'My Salah',
      body: 'Tap to review today\'s prayer record',
      scheduledTime: eodTime,
      details: const AndroidNotificationDetails(
        'salah_prayer_channel',
        'Prayer Notifications',
        channelDescription: 'Prayer reminders',
        importance: Importance.low,
        priority: Priority.low,
        icon: '@mipmap/ic_launcher',
      ),
      payload: 'eod|$dateKey',
    );
  }

  // Core: schedule a single notification
  static Future<void> _scheduleAt({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    required dynamic details,
    required String payload,
  }) async {
    if (scheduledTime.isBefore(DateTime.now())) return;

    final tzTime = tz.TZDateTime.from(scheduledTime, tz.local);

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tzTime,
        details is AndroidNotificationDetails
            ? NotificationDetails(android: details)
            : details as NotificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } catch (e) {
      debugPrint('NotificationService: failed to schedule $id: $e');
    }
  }

  // Build notification details (no action buttons)
  static NotificationDetails _buildNotificationDetails({
    required String title,
    required String body,
    required String payload,
  }) {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        'salah_prayer_channel',
        'Prayer Notifications',
        channelDescription: 'Prayer time notifications',
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        color: Color(0xFFC9A87C),
        enableVibration: true,
        playSound: true,
        ongoing: false,
        autoCancel: true,
      ),
    );
  }

  //Handle action (foreground)
  static void _handleActionForeground(NotificationResponse response) {
    _handleActionBackground(response);
  }

  // Handle action (background/killed app)
  static Future<void> _handleActionBackground(
      NotificationResponse response) async {
    final payload = response.payload;
    final actionId = response.actionId;
    if (payload == null || actionId == null) return;

    final parts = payload.split('|');
    if (parts.length < 3) return;

    final prayerName = parts[0]; // e.g. 'Fajr'
    final type = parts[1]; // 'ontime' or 'qaza' or 'eod'
    final dateKey = parts[2]; // e.g. '2024-08-27'

    if (type == 'eod') {
      await _processEndOfDay(dateKey);
      return;
    }

    final currentStatus = await getPrayerStatus(prayerName, dateKey);
    if (_isLocked(currentStatus)) return; // Already finalized — ignore

    String newStatus;
    if (type == 'ontime') {
      newStatus = actionId == 'yes' ? 'ontime' : 'pending';
    } else {
      // type == 'qaza'
      newStatus = actionId == 'yes' ? 'qaza' : 'pending';
    }

    await savePrayerStatus(prayerName, dateKey, newStatus);

    // Cancel all remaining notifications for this prayer
    await cancelPrayerNotifications(prayerName);

    debugPrint(
        'NotificationService: $prayerName [$type] → $newStatus');
  }

  //  Endofday mark all still-pending prayers as 'missed'
  static Future<void> _processEndOfDay(String dateKey) async {
    for (final prayer in _prayerOrder) {
      final status = await getPrayerStatus(prayer, dateKey);
      if (status == 'pending') {
        await savePrayerStatus(prayer, dateKey, 'missed');
      }
    }
  }

  // Cancel all notifications for a specific prayer
  static Future<void> cancelPrayerNotifications(String prayerName) async {
    final baseId = _baseIds[prayerName];
    if (baseId == null) return;

    // Cancel main + reminders (base to base+8)
    for (int i = 0; i <= _maxReminders; i++) {
      await _plugin.cancel(baseId + i);
    }
    // Cancel qaza notifications
    for (int i = 0; i <= 2; i++) {
      await _plugin.cancel(baseId + 50 + i);
    }
  }

  // Cancel ALL scheduled notifications
  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  // Prayer status persistence
  static String _statusKey(String prayer, String dateKey) =>
      'prayer_status_${dateKey}_$prayer';

  static String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static String get todayKey => _dateKey(DateTime.now());

  static Future<String?> getPrayerStatus(
      String prayer, String dateKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Force fresh read — background isolate may have written since last cache
    return prefs.getString(_statusKey(prayer, dateKey));
  }

  static Future<void> savePrayerStatus(
      String prayer, String dateKey, String status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_statusKey(prayer, dateKey), status);
  }

  // Convert string status → PrayerStatus enum
  static PrayerStatus toPrayerStatus(String? status) {
    switch (status) {
      case 'ontime':
        return PrayerStatus.onTime;
      case 'qaza':
        return PrayerStatus.qaza;
      case 'missed':
        return PrayerStatus.missed;
      case 'pending':
        return PrayerStatus.pending;
      default:
        return PrayerStatus.upcoming;
    }
  }

  // Convert PrayerStatus enum → string
  static String fromPrayerStatus(PrayerStatus status) {
    switch (status) {
      case PrayerStatus.onTime:
        return 'ontime';
      case PrayerStatus.qaza:
        return 'qaza';
      case PrayerStatus.missed:
        return 'missed';
      case PrayerStatus.pending:
        return 'pending';
      default:
        return 'upcoming';
    }
  }

  static bool _isLocked(String? status) =>
      status == 'ontime' || status == 'qaza' || status == 'missed';

  //Manually mark a prayer (from UI)
  /// Returns false if prayer is already locked (can't change)
  static Future<bool> markFromUI(String prayerName, PrayerStatus status) async {
    final dateKey = todayKey;
    final current = await getPrayerStatus(prayerName, dateKey);
    if (_isLocked(current)) return false; // Locked — reject

    await savePrayerStatus(
        prayerName, dateKey, fromPrayerStatus(status));
    await cancelPrayerNotifications(prayerName);
    return true;
  }

  /// Load today's statuses as a Map<String, PrayerStatus>
  static Future<Map<String, PrayerStatus>> loadTodayStatuses() async {
    final dateKey = todayKey;
    // Single reload — ensures we pick up any writes from background isolates
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final Map<String, PrayerStatus> result = {};
    for (final prayer in _prayerOrder) {
      final raw = prefs.getString(_statusKey(prayer, dateKey));
      result[prayer] = toPrayerStatus(raw);
    }
    return result;
  }

  /// Map common UTC offset in minutes to IANA timezone name
  static String _guessTimezone(int offsetMinutes) {
    const map = {
      360: 'Asia/Dhaka',       // UTC+6  Bangladesh
      330: 'Asia/Kolkata',     // UTC+5:30 India
      300: 'Asia/Karachi',     // UTC+5  Pakistan
      210: 'Asia/Tehran',      // UTC+3:30 Iran
      180: 'Asia/Riyadh',      // UTC+3  Saudi Arabia
      120: 'Asia/Jerusalem',   // UTC+2
      60: 'Europe/London',     // UTC+1
      0: 'UTC',
      -300: 'America/New_York', // UTC-5
      -360: 'America/Chicago',  // UTC-6
      -420: 'America/Denver',   // UTC-7
      -480: 'America/Los_Angeles', // UTC-8
      480: 'Asia/Shanghai',    // UTC+8
      540: 'Asia/Tokyo',       // UTC+9
      600: 'Australia/Sydney', // UTC+10
    };
    return map[offsetMinutes] ?? 'Asia/Dhaka';
  }

  //Logout helpers

  /// Clear today's prayer status cache from SharedPreferences (called on logout).
  /// Prevents the next user from inheriting the previous user's prayer marks.
  /// cancelAll() for notifications already exists above.
  static Future<void> clearTodayStatuses() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final dateKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    for (final prayer in ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha']) {
      await prefs.remove('prayer_status_${prayer}_$dateKey');
    }
  }
}
