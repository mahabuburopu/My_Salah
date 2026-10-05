import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';
import 'providers/prayer_provider.dart';
import 'providers/history_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/theme_provider.dart';
import 'data/services/notification_service.dart';
import 'data/services/supabase_service.dart';
import 'data/services/sync_service.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/auth/auth_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize notifications
  await NotificationService.initialize();

  // Initialize Supabase (required for auth + cloud sync)
  await SupabaseService.initialize();

  // Start background connectivity listener for automatic sync
  SyncService.instance.startListening();

  // Pre-load theme so ThemeProvider starts with the right value (no flash)
  final prefs = await SharedPreferences.getInstance();
  final initialIsDark = prefs.getBool('is_dark_mode') ?? true;

  runApp(MySalahApp(initialIsDark: initialIsDark));
}

class MySalahApp extends StatelessWidget {
  final bool initialIsDark;
  const MySalahApp({super.key, required this.initialIsDark});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
            create: (_) => ThemeProvider(initialIsDark: initialIsDark)),
        ChangeNotifierProvider(create: (_) => SettingsProvider()..init()),
        ChangeNotifierProxyProvider<SettingsProvider, PrayerProvider>(
          create: (_) => PrayerProvider(),
          update: (_, settings, prayer) {
            prayer!.updateSettings(
              lat: settings.latitude,
              lon: settings.longitude,
              calculationMethod: settings.calculationMethod,
              asrMethod: settings.asrMethod,
            );
            return prayer;
          },
        ),
        ChangeNotifierProxyProvider<PrayerProvider, HistoryProvider>(
          create: (_) => HistoryProvider(),
          update: (_, prayer, history) {
            // Only refreshes DB when a prayer is actually marked (not every second)
            history!.onMarkCountChanged(prayer.markCount);
            return history;
          },
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'My Salah',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const SplashScreen(),
            routes: {
              '/home': (context) => const HomeScreen(),
              '/auth': (context) => const AuthScreen(),
            },
          );
        },
      ),
    );
  }
}
