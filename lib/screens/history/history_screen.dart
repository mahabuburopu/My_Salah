import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../providers/history_provider.dart';
import '../../providers/settings_provider.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/prayer.dart';
import '../../data/models/prayer_record.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AC.bg(context),
      body: SafeArea(
        child: Consumer2<HistoryProvider, SettingsProvider>(
          builder: (context, history, settings, _) {
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(context, settings)),
                SliverToBoxAdapter(child: _buildCalendar(context, history)),
                SliverToBoxAdapter(
                  child: _buildDayDetail(context, history, settings),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, SettingsProvider settings) {
    final userName = settings.userName.isNotEmpty ? settings.userName : 'You';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'History of',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AC.textSub(context),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            userName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AC.gold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar(BuildContext context, HistoryProvider history) {
    final isDark = AC.isDark(context);
    final textColor = AC.text(context);
    final subColor = AC.textSub(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: AC.card(context),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TableCalendar(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          focusedDay: history.focusedMonth,
          selectedDayPredicate: (day) =>
              isSameDay(day, history.selectedDate),
          onDaySelected: (selected, focused) {
            history.selectDate(selected);
          },
          onPageChanged: (focused) {
            history.changeMonth(focused);
          },
          calendarStyle: CalendarStyle(
            outsideDaysVisible: false,
            selectedDecoration: const BoxDecoration(
              color: AppColors.onTime,
              shape: BoxShape.circle,
            ),
            todayDecoration: BoxDecoration(
              color: AppColors.onTime.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            todayTextStyle: const TextStyle(
              color: AC.gold,
              fontWeight: FontWeight.bold,
            ),
            weekendTextStyle: TextStyle(color: textColor),
            defaultTextStyle: TextStyle(color: textColor),
            outsideTextStyle: TextStyle(color: subColor),
          ),
          headerStyle: HeaderStyle(
            formatButtonVisible: false,
            titleCentered: false,
            leftChevronIcon: Icon(Icons.chevron_left,
                color: subColor, size: 20),
            rightChevronIcon: Icon(Icons.chevron_right,
                color: subColor, size: 20),
            titleTextStyle: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: textColor,
              letterSpacing: 1,
            ),
            headerPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          calendarBuilders: CalendarBuilders(
            markerBuilder: (context, day, events) {
              final status = history.getDayStatus(day);
              if (status['onTime'] == 0 &&
                  status['qaza'] == 0 &&
                  status['missed'] == 0) {
                return const SizedBox.shrink();
              }
              return Positioned(
                bottom: 4,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if ((status['onTime'] ?? 0) > 0)
                      _dot(AppColors.onTime),
                    if ((status['qaza'] ?? 0) > 0)
                      _dot(AppColors.qaza),
                    if ((status['missed'] ?? 0) > 0)
                      _dot(AppColors.missed),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _dot(Color color) {
    return Container(
      width: 6,
      height: 6,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _buildDayDetail(BuildContext context, HistoryProvider history, SettingsProvider settings) {
    final records = history.selectedDateRecords;
    final dateLabel = DateFormat('EEEE, MMMM d').format(history.selectedDate).toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Text(
            dateLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AC.textSub(context),
              letterSpacing: 1.2,
            ),
          ),
        ),
        if (records.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Center(
              child: Text(
                'No prayer records for this day.',
                style: TextStyle(color: AC.textSub(context)),
              ),
            ),
          )
        else
          ...records.map((record) => _HistoryPrayerTile(
                record: record,
                settings: settings,
                date: history.selectedDate,
              )),
      ],
    );
  }
}

class _HistoryPrayerTile extends StatelessWidget {
  final PrayerRecord record;
  final SettingsProvider settings;
  final DateTime date;

  const _HistoryPrayerTile({
    required this.record,
    required this.settings,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(record.status);
    final label = _statusLabel(record.status);
    final icon = _statusIcon(record.status);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Container(
        decoration: BoxDecoration(
          color: AC.card(context),
          borderRadius: BorderRadius.circular(16),
          border: Border(
            left: BorderSide(color: color, width: 4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: AC.isDark(context) ? 0.2 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.prayerName.localizedName(settings.userGender, date),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AC.text(context),
                      ),
                    ),
                    if (record.prayedAt != null)
                      Text(
                        DateFormat('h:mm a').format(record.prayedAt!),
                        style: TextStyle(
                            fontSize: 13, color: AC.textSub(context)),
                      ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(icon, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(PrayerStatus status) {
    switch (status) {
      case PrayerStatus.onTime:
        return AppColors.onTime;
      case PrayerStatus.qaza:
        return AppColors.qaza;
      case PrayerStatus.missed:
        return AppColors.missed;
      case PrayerStatus.pending:
        return const Color(0xFFE0A020); // amber
      default:
        return AppColors.upcoming;
    }
  }

  String _statusLabel(PrayerStatus status) {
    switch (status) {
      case PrayerStatus.onTime:
        return 'On Time';
      case PrayerStatus.qaza:
        return 'Qaza';
      case PrayerStatus.missed:
        return 'Missed';
      case PrayerStatus.pending:
        return 'Pending';
      default:
        return 'Upcoming';
    }
  }

  IconData _statusIcon(PrayerStatus status) {
    switch (status) {
      case PrayerStatus.onTime:
        return Icons.check_circle_outline_rounded;
      case PrayerStatus.qaza:
        return Icons.access_time_rounded;
      case PrayerStatus.missed:
        return Icons.cancel_outlined;
      case PrayerStatus.pending:
        return Icons.hourglass_bottom_rounded;
      default:
        return Icons.radio_button_unchecked;
    }
  }

}
