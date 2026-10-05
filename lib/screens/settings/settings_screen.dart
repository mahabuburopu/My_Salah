import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../providers/prayer_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/history_provider.dart';
import '../../core/constants/app_colors.dart';
import '../../data/services/location_service.dart';
import '../../data/services/notification_service.dart';
import '../../data/services/database_service.dart';
import '../auth/auth_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AC.bg(context),
      body: SafeArea(
        child: Consumer2<SettingsProvider, ThemeProvider>(
          builder: (context, settings, theme, _) {
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(context)),
                SliverToBoxAdapter(
                    child: _buildProfileCard(context, settings)),
                SliverToBoxAdapter(
                    child: _buildAppearanceSection(context, theme)),
                SliverToBoxAdapter(
                    child: _buildPrayerSection(context, settings)),
                SliverToBoxAdapter(
                    child: _buildNotificationsSection(context, settings)),
                SliverToBoxAdapter(child: _buildLogOut(context)),
                SliverToBoxAdapter(child: _buildAbout(context)),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Text(
        'Settings',
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.bold,
          color: AC.gold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context, SettingsProvider settings) {
    // SettingsProvider is already loaded — read directly, no FutureBuilder needed
    final name = settings.userName.isNotEmpty ? settings.userName : 'User';
    final email = settings.userEmail;
    final gender = settings.userGender;
    return _Card(
      context: context,
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFFD4A96A), Color(0xFF8B6914)],
              ),
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'U',
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AC.text(context))),
                if (email.isNotEmpty)
                  Text(email,
                      style: TextStyle(
                          fontSize: 13, color: AC.textSub(context))),
                Text('Gender: $gender',
                    style: TextStyle(
                        fontSize: 13, color: AC.textSub(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Appearance Section (Dark/Light Mode) ────────────────
  Widget _buildAppearanceSection(BuildContext context, ThemeProvider theme) {
    return _SectionCard(
      context: context,
      title: 'Appearance',
      icon: Icons.palette_outlined,
      children: [
        // Light / Dark quick select buttons only
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: _ThemeButton(
                  label: '☀️  Light',
                  isActive: !theme.isDark,
                  onTap: () => theme.setDark(false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ThemeButton(
                  label: '🌙  Dark',
                  isActive: theme.isDark,
                  onTap: () => theme.setDark(true),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Prayer Settings ─────────────────────────────────────
  Widget _buildPrayerSection(BuildContext context, SettingsProvider settings) {
    return _SectionCard(
      context: context,
      title: 'Prayer Times',
      icon: Icons.access_time_rounded,
      children: [
        _SettingRow(
          context: context,
          icon: Icons.my_location_rounded,
          iconColor: Colors.blueAccent,
          label: 'Update Location',
          subtitle: context.watch<PrayerProvider>().cityName,
          onTap: () async {
            // 1. Check GPS first
            final gpsOn = await LocationService.isGpsEnabled();
            if (!context.mounted) return;
            if (!gpsOn) {
              // Show dialog to enable GPS
              await showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isDismissible: true,
                builder: (sheetCtx) => Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                  decoration: BoxDecoration(
                    color: AC.card(context),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                        color: AC.gold.withValues(alpha: 0.25), width: 1),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AC.gold.withValues(alpha: 0.12),
                          border: Border.all(
                              color: AC.gold.withValues(alpha: 0.35), width: 1.5),
                        ),
                        child: const Icon(Icons.gps_off_rounded,
                            color: AC.gold, size: 30),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'GPS is Turned Off',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AC.text(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please enable GPS / Location Services\nto update your prayer location.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13,
                            color: AC.textSub(context),
                            height: 1.5),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            Navigator.pop(sheetCtx);
                            await Geolocator.openLocationSettings();
                          },
                          icon: const Icon(Icons.settings_rounded, size: 18),
                          label: const Text('Open Location Settings'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AC.gold,
                            foregroundColor: Colors.black,
                            padding:
                                const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        child: Text('Cancel',
                            style: TextStyle(
                                color: AC.textSub(context), fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              );
              return; // Don't update until user enables GPS
            }
            // 2. GPS is on — proceed with update
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Updating location...')),
            );
            await context.read<PrayerProvider>().updateLocationFromGPS();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Location updated successfully')),
              );
            }
          },
        ),
        _Divider(context),
        _SettingRow(
          context: context,
          icon: Icons.calculate_outlined,
          iconColor: AC.gold,
          label: 'Calculation Method',
          subtitle: _calcMethodName(settings.calculationMethod),
          onTap: () => _showMethodPicker(context, settings),
        ),
        _Divider(context),
        _SettingRow(
          context: context,
          icon: Icons.school_outlined,
          iconColor: const Color(0xFF8FAF6B),
          label: 'Asr Juristic Method',
          subtitle: settings.asrMethod == 0 ? 'Standard (Shafi)' : 'Hanafi',
          onTap: () => _showAsrPicker(context, settings),
        ),
      ],
    );
  }

  // ── Notifications Section ────────────────────────────────
  Widget _buildNotificationsSection(
      BuildContext context, SettingsProvider settings) {
    return _SectionCard(
      context: context,
      title: 'Notifications',
      icon: Icons.notifications_outlined,
      children: [
        _SettingRow(
          context: context,
          icon: Icons.notifications_active_rounded,
          iconColor: const Color(0xFFE87B4B),
          label: 'Prayer Alerts',
          subtitle: 'Get notified before each prayer',
          trailing: Switch(
            value: settings.notificationsEnabled,
            onChanged: (v) => settings.setNotifications(v),
            activeThumbColor: AC.gold,
          ),
        ),
      ],
    );
  }

  // ── Logout ───────────────────────────────────────────────
  Widget _buildLogOut(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
          label: const Text('Log Out',
              style: TextStyle(
                  color: Colors.redAccent, fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.redAccent, width: 1.2),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: () => _confirmLogout(context),
        ),
      ),
    );
  }

  // ── About the App ─────────────────────────────────────────
  Widget _buildAbout(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showAboutSheet(context),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: AC.card(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AC.border(context)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AC.gold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.info_outline_rounded,
                      color: AC.gold, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('About the App',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AC.text(context))),
                      Text('My Salah — Version 1.0.0',
                          style: TextStyle(
                              fontSize: 12, color: AC.textSub(context))),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: AC.textSub(context), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAboutSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.88,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: BoxDecoration(
            color: AC.card(context),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AC.border(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                  children: [
                    // App logo + name + version
                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: AC.gold.withValues(alpha: 0.4), width: 1.5),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.asset('assets/images/app_logo.png',
                                  fit: BoxFit.cover),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'My Salah',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AC.gold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Version 1.0.0',
                            style: TextStyle(
                                fontSize: 13, color: AC.textSub(context)),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Your personal Islamic prayer companion',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: AC.textSub(context),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // About text — friendly paragraphs
                    // About text — detailed paragraphs
                    Text(
                      'Welcome to My Salah, your comprehensive and reliable Islamic prayer tracking companion. Maintaining consistency in the five daily prayers (Salah) is fundamental to a Muslim\'s life, and this application is designed specifically to help you build and maintain that vital habit without judgement or complicated interfaces.',
                      style: TextStyle(
                        fontSize: 14.5,
                        color: AC.text(context),
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'With My Salah, every prayer is accounted for. The app automatically determines your exact location to calculate the most accurate prayer times for your city using established methods (such as Karachi, Umm Al-Qura, or Muslim World League). You don\'t need to manually input times or update them when you travel; the app handles it all seamlessly in the background.',
                      style: TextStyle(
                        fontSize: 14.5,
                        color: AC.text(context),
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Our intelligent notification system ensures you never miss a prayer. At the start of each prayer time, you will receive a gentle reminder asking "Have you prayed?". You can easily respond directly from your lock screen or notification panel by tapping "Yes" or "Not Yet". If you don\'t respond, the app will continue to gently remind you at regular intervals throughout the prayer window.',
                      style: TextStyle(
                        fontSize: 14.5,
                        color: AC.text(context),
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'My Salah provides a complete tracking system. If you pray on time, it\'s marked in green. If you miss a prayer and perform it later, the app intelligently prompts you to mark it as Qaza (made up). At midnight, any unprayed prayers are automatically recorded as Missed. This gives you a brutally honest, 100% accurate record of your worship.',
                      style: TextStyle(
                        fontSize: 14.5,
                        color: AC.text(context),
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'To help you stay motivated, the built-in Statistics dashboard provides beautiful visual graphs of your weekly performance, letting you quickly spot which prayers you struggle with most. The interactive Calendar History allows you to look back at any previous day to see exactly how you performed, fostering personal growth and consistency.',
                      style: TextStyle(
                        fontSize: 14.5,
                        color: AC.text(context),
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'When you are away from home, the integrated Mosque Finder utilizes Google Maps to instantly locate the nearest Masjids around you, making it easy to join congregational prayers (Jama\'ah) wherever you are.',
                      style: TextStyle(
                        fontSize: 14.5,
                        color: AC.text(context),
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Privacy and reliability are at the core of My Salah. The app is built with an "Offline-First" architecture. Your entire prayer history, statistics, and settings are stored locally and securely on your device. You can track your prayers and receive notifications perfectly even without an internet connection.',
                      style: TextStyle(
                        fontSize: 14.5,
                        color: AC.text(context),
                        height: 1.6,
                      ),
                    ),

                    const SizedBox(height: 32),
                    Divider(color: AC.border(context)),
                    const SizedBox(height: 24),

                    // Footer
                    Center(
                      child: Column(
                        children: [
                          const SizedBox(height: 24),
                          Text(
                            'Developed by',
                            style: TextStyle(
                                fontSize: 12, color: AC.textSub(context)),
                          ),
                          const SizedBox(height: 5),
                          const Column(
                            children: [
                              Text(
                                'MD. Mahabubur Rahman Raihan',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AC.gold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'MD. Ashif Arafat Shitul',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AC.gold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'MD. Shahareer Abdullah Seam',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AC.gold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'CSE • RUET (2024–25)',
                            style: TextStyle(
                                fontSize: 13, color: AC.textSub(context)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AC.card(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Log Out',
            style: TextStyle(
                color: AC.text(context), fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to log out?',
            style: TextStyle(color: AC.textSub(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: AC.textSub(context))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log Out',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      // Capture providers and navigator before async gaps
      final nav = Navigator.of(context);
      final settingsProv = context.read<SettingsProvider>();
      final historyProv = context.read<HistoryProvider>();
      final prayerProv = context.read<PrayerProvider>();

      // Cancel all scheduled prayer notifications
      await NotificationService.cancelAll();
      // Clear today's prayer status cache so the next user starts clean
      await NotificationService.clearTodayStatuses();
      
      // Wipe the local database to prevent Account A's records from bleeding into Account B
      await DatabaseService().clearAllRecords();

      // Clear in-memory caches
      historyProv.clear();
      prayerProv.clear();

      // Sign out from Supabase + clear all local auth state
      await settingsProv.logout();

      nav.push(MaterialPageRoute(
        builder: (_) => const AuthScreen(fromLogout: true),
      ));
    }
  }

  String _calcMethodName(int method) {
    const names = {
      0: 'Muslim World League',
      1: 'Islamic Society of North America',
      2: 'Egyptian Authority',
      3: 'Umm Al-Qura (Mecca)',
      4: 'University of Islamic Sciences, Karachi',
    };
    return names[method] ?? 'Standard';
  }

  Future<void> _showMethodPicker(
      BuildContext context, SettingsProvider settings) async {
    final methods = [
      'Muslim World League',
      'ISNA (North America)',
      'Egyptian Authority',
      "Umm Al-Qura (Mecca)",
      'Karachi (Pakistan)',
    ];
    await showModalBottomSheet(
      context: context,
      backgroundColor: AC.card(context),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Calculation Method',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: AC.text(context))),
          ),
          ...List.generate(
            methods.length,
            (i) => Material(
              color: Colors.transparent,
              child: ListTile(
                title: Text(methods[i],
                    style: TextStyle(color: AC.text(context))),
                trailing: settings.calculationMethod == i
                    ? const Icon(Icons.check_rounded, color: AppColors.gold)
                    : null,
                onTap: () {
                  settings.setCalculationMethod(i);
                  Navigator.pop(ctx);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _showAsrPicker(
      BuildContext context, SettingsProvider settings) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: AC.card(context),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Asr Method',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: AC.text(context))),
          ),
          Material(
            color: Colors.transparent,
            child: ListTile(
              title: Text('Standard (Shafi, Maliki, Hanbali)',
                  style: TextStyle(color: AC.text(context))),
              trailing: settings.asrMethod == 0
                  ? const Icon(Icons.check_rounded, color: AppColors.gold)
                  : null,
              onTap: () {
                settings.setAsrMethod(0);
                Navigator.pop(ctx);
              },
            ),
          ),
          Material(
            color: Colors.transparent,
            child: ListTile(
              title: Text('Hanafi', style: TextStyle(color: AC.text(context))),
              trailing: settings.asrMethod == 1
                  ? const Icon(Icons.check_rounded, color: AppColors.gold)
                  : null,
              onTap: () {
                settings.setAsrMethod(1);
                Navigator.pop(ctx);
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Reusable Widgets ─────────────────────────────────────────

class _Card extends StatelessWidget {
  final BuildContext context;
  final Widget child;
  const _Card({required this.context, required this.child});

  @override
  Widget build(BuildContext ctx) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AC.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AC.border(context)),
      ),
      child: child,
    );
  }
}

class _SectionCard extends StatelessWidget {
  final BuildContext context;
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _SectionCard({
    required this.context,
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext ctx) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color: AC.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AC.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Icon(icon, color: AC.gold, size: 18),
                const SizedBox(width: 8),
                Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AC.textSub(context),
                        letterSpacing: 0.5)),
              ],
            ),
          ),
          ...children,
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final BuildContext context;
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingRow({
    required this.context,
    required this.icon,
    required this.iconColor,
    required this.label,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext ctx) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(label,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AC.text(context))),
        subtitle: subtitle != null
            ? Text(subtitle!,
                style: TextStyle(fontSize: 12, color: AC.textSub(context)))
            : null,
        trailing: trailing ??
            (onTap != null
                ? Icon(Icons.chevron_right_rounded,
                    color: AC.textSub(context), size: 20)
                : null),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final BuildContext context;
  const _Divider(this.context);

  @override
  Widget build(BuildContext ctx) {
    return Divider(
      height: 1,
      indent: 68,
      color: AC.border(context),
    );
  }
}

class _ThemeButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  const _ThemeButton(
      {required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? AC.gold.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? AC.gold : AC.border(context),
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isActive ? AC.gold : AC.textSub(context),
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

