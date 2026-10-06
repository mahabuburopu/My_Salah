import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/prayer_provider.dart';
import '../../providers/settings_provider.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/prayer.dart';
import '../../core/utils/hijri_converter.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AC.bg(context),
      body: SafeArea(
        child: Consumer2<PrayerProvider, SettingsProvider>(
          builder: (context, prayers, settings, _) {
            return RefreshIndicator(
              color: AC.gold,
              backgroundColor: AC.card(context),
              onRefresh: prayers.refresh,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader(context, settings)),
                  SliverToBoxAdapter(child: _buildDateRow(context)),
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  if (prayers.isLoading)
                    const SliverToBoxAdapter(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: CircularProgressIndicator(
                            color: AC.gold,
                          ),
                        ),
                      ),
                    )
                  else ...[
                    SliverToBoxAdapter(
                      child: _buildNextPrayerCard(context, prayers, settings),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    SliverToBoxAdapter(child: _buildScheduleHeader(context)),
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final prayer = prayers.todayPrayers[index];
                          return _PrayerTile(
                            prayer: prayer,
                            isNext: prayers.nextPrayer?.name == prayer.name,
                            isWindowOpen: prayers.isPrayerWindowOpen(prayer),
                            isWindowExpired:
                                prayers.isPrayerWindowExpired(prayer),
                            onMark: (status) =>
                                prayers.markPrayer(prayer, status),
                            settings: settings,
                          );
                        },
                        childCount: prayers.todayPrayers.length,
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, SettingsProvider settings) {
    // SettingsProvider is already loaded — no FutureBuilder needed
    final userName = settings.userName.isNotEmpty ? settings.userName : 'Muslim';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'السلام عليكم',
            style: TextStyle(
              fontSize: 18,
              color: AC.gold,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            userName,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: AC.text(context),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateRow(BuildContext context) {
    final now = DateTime.now();
    final englishDate = DateFormat('EEEE, d MMMM yyyy').format(now);
    final hijri = HijriConverter.formatHijriShort(now);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    englishDate,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AC.text(context),
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hijri,
                    style: TextStyle(
                      fontSize: 13,
                      color: AC.textSub(context),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Location — full line so city name is never truncated
          Consumer<PrayerProvider>(
            builder: (_, prayers, __) => Row(
              children: [
                Icon(Icons.location_on_outlined,
                    size: 14, color: AC.textSub(context)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    prayers.cityName,
                    style: TextStyle(
                      fontSize: 13,
                      color: AC.textSub(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildNextPrayerCard(BuildContext context, PrayerProvider prayers, SettingsProvider settings) {
    final next = prayers.nextPrayer;
    if (next == null) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: Text(
            "All prayers completed for today! 🌙",
            style: TextStyle(color: AC.gold, fontSize: 16),
          ),
        ),
      );
    }

    final dur = prayers.timeToNextPrayer;
    final hours = dur.inHours.toString().padLeft(2, '0');
    final mins = (dur.inMinutes % 60).toString().padLeft(2, '0');
    final secs = (dur.inSeconds % 60).toString().padLeft(2, '0');
    final timeStr = '$hours:$mins:$secs';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AC.card(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AC.border(context)),
          boxShadow: [
            BoxShadow(
              color: AC.gold.withValues(alpha: 0.07),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'NEXT PRAYER',
                      style: TextStyle(
                        fontSize: 11,
                        color: AC.textSub(context),
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      next.name.localizedName(settings.userGender, DateTime.now()),
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: AC.text(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('h:mm a').format(next.time),
                      style: TextStyle(
                          fontSize: 14, color: AC.textSub(context)),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AC.gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AC.gold.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'TIME LEFT',
                        style: TextStyle(
                          fontSize: 10,
                          color: AC.gold,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AC.text(context),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: prayers.progressToNextPrayer,
                backgroundColor: AC.border(context),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AC.gold),
                minHeight: 5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        "TODAY'S SCHEDULE",
        style: TextStyle(
          fontSize: 12,
          color: AC.textSub(context),
          letterSpacing: 1.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }


}

// ─────────────────────────────────────────────────────────────────────────────
//  Prayer Tile
// ─────────────────────────────────────────────────────────────────────────────

class _PrayerTile extends StatelessWidget {
  final Prayer prayer;
  final bool isNext;
  final bool isWindowOpen;   // prayer time started, next prayer not yet
  final bool isWindowExpired; // prayer time passed, window closed
  final Function(PrayerStatus) onMark;
  final SettingsProvider settings;

  const _PrayerTile({
    required this.prayer,
    required this.isNext,
    required this.isWindowOpen,
    required this.isWindowExpired,
    required this.onMark,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getPrayerColor(prayer.name);
    final bool isActionable = !prayer.isLocked &&
        (isWindowOpen || isWindowExpired);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: isNext
              ? AC.gold.withValues(alpha: 0.08)
              : AC.card(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isNext ? AC.gold.withValues(alpha: 0.4) : AC.border(context),
            width: isNext ? 1.5 : 1,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, isActionable ? 12 : 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top row: icon + name/time + status badge ──
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_getPrayerIcon(prayer.name),
                        color: color, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          prayer.name.localizedName(settings.userGender, DateTime.now()),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: prayer.status == PrayerStatus.upcoming &&
                                    !isNext
                                ? AC.textSub(context)
                                : AC.text(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('h:mm a').format(prayer.time),
                          style: TextStyle(
                              fontSize: 13, color: AC.textSub(context)),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusBadge(context),
                ],
              ),

              // ── Action buttons (only when actionable) ──
              if (isActionable) ...[
                const SizedBox(height: 12),
                _buildActionButtons(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Status badge (shown on the right of the name row) ──
  Widget _buildStatusBadge(BuildContext context) {
    switch (prayer.status) {
      case PrayerStatus.onTime:
        return Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.onTime.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded,
              color: AppColors.onTimeLight, size: 18),
        );

      case PrayerStatus.qaza:
        return const _Badge(
          label: 'Qaza',
          color: AppColors.qaza,
        );

      case PrayerStatus.missed:
        return const _Badge(
          label: 'Missed',
          color: AppColors.missed,
        );

      case PrayerStatus.pending:
        return _Badge(
          label: 'Pending',
          color: AC.textSub(context),
        );

      case PrayerStatus.upcoming:
        // Show "Upcoming" label only when prayer hasn't started yet
        if (prayer.time.isAfter(DateTime.now())) {
          return Text(
            'Upcoming',
            style: TextStyle(fontSize: 13, color: AC.textSub(context)),
          );
        }
        return const SizedBox.shrink();

      default:
        return const SizedBox.shrink();
    }
  }

  // ── Two action buttons ──
  Widget _buildActionButtons(BuildContext context) {
    if (isWindowOpen) {
      // Prayer is in active window → Yes, Prayed / No (Pending)
      return Row(
        children: [
          Expanded(
            child: _ActionButton(
              label: ' Yes, Prayed',
              color: AppColors.onTimeLight,
              onTap: () => onMark(PrayerStatus.onTime),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ActionButton(
              label: 'No  (Pending)',
              color: AC.textSub(context),
              outlined: true,
              onTap: () => onMark(PrayerStatus.pending),
            ),
          ),
        ],
      );
    } else {
      // Window expired → Qaza / No (Pending)
      return Row(
        children: [
          Expanded(
            child: _ActionButton(
              label: ' Prayed (Qaza)',
              color: AppColors.qaza,
              onTap: () => onMark(PrayerStatus.qaza),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ActionButton(
              label: 'No  (Pending)',
              color: AC.textSub(context),
              outlined: true,
              onTap: () => onMark(PrayerStatus.pending),
            ),
          ),
        ],
      );
    }
  }

  Color _getPrayerColor(PrayerName name) {
    switch (name) {
      case PrayerName.fajr:
        return AppColors.fajrColor;
      case PrayerName.dhuhr:
        return AppColors.dhuhrColor;
      case PrayerName.asr:
        return AppColors.asrColor;
      case PrayerName.maghrib:
        return AppColors.maghribColor;
      case PrayerName.isha:
        return AppColors.ishaColor;
    }
  }

  IconData _getPrayerIcon(PrayerName name) {
    switch (name) {
      case PrayerName.fajr:
        return Icons.wb_twilight_rounded;
      case PrayerName.dhuhr:
        return Icons.wb_sunny_rounded;
      case PrayerName.asr:
        return Icons.wb_sunny_outlined;
      case PrayerName.maghrib:
        return Icons.wb_twilight_outlined;
      case PrayerName.isha:
        return Icons.nights_stay_rounded;
    }
  }

}

// ─────────────────────────────────────────────────────────────────────────────
//  Reusable Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool outlined;

  const _ActionButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: outlined ? color.withValues(alpha: 0.4) : color.withValues(alpha: 0.35),
            width: 1.2,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
