import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/prayer.dart';
import '../../data/services/database_service.dart';
import '../../providers/prayer_provider.dart';
import '../../providers/settings_provider.dart';
import 'package:intl/intl.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  final DatabaseService _db = DatabaseService();

  int _totalPrayers = 0;
  int _totalThisWeek = 0;
  double _onTimePercent = 0;
  double _qazaPercent = 0;
  double _missedPercent = 0;
  int _streak = 0;
  /// Each entry: {date, onTime, qaza}
  List<Map<String, dynamic>> _last7Days = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
    // Listen to PrayerProvider.markCount so stats refresh when a prayer is marked
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PrayerProvider>().addListener(_onPrayerChanged);
    });
  }

  int _lastMarkCount = 0;
  void _onPrayerChanged() {
    final markCount = context.read<PrayerProvider>().markCount;
    if (_lastMarkCount != markCount) {
      _lastMarkCount = markCount;
      _loadStats();
    }
  }

  @override
  void dispose() {
    context.read<PrayerProvider>().removeListener(_onPrayerChanged);
    super.dispose();
  }

  Future<void> _loadStats() async {
    final stats = await _db.getPrayerStats();
    final last7 = await _db.getLast7DaysCountsSeparate();
    final streak = await _db.getCurrentStreak();

    final onTime = stats['onTime'] ?? 0;
    final qaza = stats['qaza'] ?? 0;
    final missed = stats['missed'] ?? 0;
    final total = onTime + qaza + missed;

    // This week
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekRecords = await _db.getPrayerRecordsInRange(weekStart, now);
    final thisWeek = weekRecords
        .where((r) =>
            r.status == PrayerStatus.onTime || r.status == PrayerStatus.qaza)
        .length;

    if (mounted) {
      setState(() {
        _totalPrayers = total;
        _totalThisWeek = thisWeek;
        _onTimePercent = total > 0 ? (onTime / total) * 100 : 0;
        _qazaPercent = total > 0 ? (qaza / total) * 100 : 0;
        _missedPercent = total > 0 ? (missed / total) * 100 : 0;
        _streak = streak;
        _last7Days = last7;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AC.bg(context),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AC.gold))
            : RefreshIndicator(
                color: AC.gold,
                onRefresh: _loadStats,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader(context)),
                    SliverToBoxAdapter(child: _buildTotalPrayersCard(context)),
                    SliverToBoxAdapter(child: _buildOnTimeAndStreak(context)),
                    SliverToBoxAdapter(child: _buildBarChart(context)),
                    SliverToBoxAdapter(child: _buildDonutChart(context)),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final userName = context.read<SettingsProvider>().userName;
    final displayName = userName.isNotEmpty ? userName : 'You';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Statistics of',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AC.textSub(context),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            displayName,
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

  Widget _buildTotalPrayersCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AC.card(context),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: AC.isDark(context) ? 0.25 : 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.access_time_rounded,
                    size: 16, color: AC.textSub(context)),
                const SizedBox(width: 6),
                Text(
                  'TOTAL PRAYERS',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.2,
                    color: AC.textSub(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$_totalPrayers',
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: AC.gold,
              ),
            ),
            Row(
              children: [
                const Icon(Icons.trending_up_rounded,
                    size: 16, color: AC.gold),
                const SizedBox(width: 4),
                Text(
                  '+$_totalThisWeek this week',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AC.gold,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOnTimeAndStreak(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              icon: Icons.check_circle_outline_rounded,
              label: 'ON-TIME',
              value: '${_onTimePercent.round()}%',
              color: const Color(0xFF1B5E3B),
              progress: _onTimePercent / 100,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              icon: Icons.local_fire_department_rounded,
              label: 'STREAK',
              value: '$_streak days',
              color: AppColors.qaza,
              progress: (_streak / 30).clamp(0.0, 1.0),
              isDashed: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart(BuildContext context) {
    final now = DateTime.now();
    final dayLabels = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return DateFormat('EEE').format(d).substring(0, 3);
    });

    // Pre-build a lookup: date string → row map (avoids firstWhere type issues)
    final dayLookup = <String, Map<String, dynamic>>{
      for (final m in _last7Days) m['date'] as String: m,
    };

    // Separate onTime and qaza per day
    final onTimeCounts = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      final dateStr = d.toIso8601String().substring(0, 10);
      final row = dayLookup[dateStr];
      return (row?['onTime'] as int? ?? 0).toDouble();
    });

    final qazaCounts = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      final dateStr = d.toIso8601String().substring(0, 10);
      final row = dayLookup[dateStr];
      return (row?['qaza'] as int? ?? 0).toDouble();
    });

    final subColor = AC.textSub(context);
    final isDark = AC.isDark(context);
    const onTimeColor = Color(0xFF1B5E3B);
    const qazaColor = AppColors.qaza;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AC.card(context),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Prayers Completed',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AC.text(context),
              ),
            ),
            Text(
              '(Last 7 Days)',
              style: TextStyle(fontSize: 13, color: subColor),
            ),
            const SizedBox(height: 12),
            // Legend
            const Row(
              children: [
                _ChartLegend(color: onTimeColor, label: 'On Time'),
                SizedBox(width: 16),
                _ChartLegend(color: qazaColor, label: 'Qaza'),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 170,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: 5,
                  groupsSpace: 6,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final label = rodIndex == 0 ? 'On Time' : 'Qaza';
                        return BarTooltipItem(
                          '$label: ${rod.toY.toInt()}',
                          TextStyle(
                            color: rod.color,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= dayLabels.length) {
                            return const SizedBox.shrink();
                          }
                          final isToday = idx == 6;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              dayLabels[idx],
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isToday
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isToday ? AC.gold : subColor,
                              ),
                            ),
                          );
                        },
                        reservedSize: 28,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (value, meta) {
                          if (value % 1 != 0) return const SizedBox.shrink();
                          return Text(
                            value.toInt().toString(),
                            style:
                                TextStyle(fontSize: 11, color: subColor),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: AC.border(context),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(7, (i) {
                    return BarChartGroupData(
                      x: i,
                      groupVertically: false,
                      barsSpace: 4,
                      barRods: [
                        // On Time bar (green)
                        BarChartRodData(
                          toY: onTimeCounts[i],
                          color: onTimeCounts[i] > 0
                              ? onTimeColor
                              : onTimeColor.withValues(alpha: 0.15),
                          width: 12,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
                        ),
                        // Qaza bar (gold)
                        BarChartRodData(
                          toY: qazaCounts[i],
                          color: qazaCounts[i] > 0
                              ? qazaColor
                              : qazaColor.withValues(alpha: 0.15),
                          width: 12,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDonutChart(BuildContext context) {
    final total = _totalPrayers;
    final isDark = AC.isDark(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AC.card(context),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Distribution',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AC.text(context),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 180,
              child: total == 0
                  ? Center(
                      child: Text(
                        'No data yet.\nStart marking your prayers!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AC.textSub(context), fontSize: 14),
                      ),
                    )
                  : PieChart(
                      PieChartData(
                        centerSpaceRadius: 56,
                        sectionsSpace: 3,
                        sections: [
                          if (_onTimePercent > 0)
                            PieChartSectionData(
                              value: _onTimePercent,
                              color: const Color(0xFF1B5E3B),
                              radius: 40,
                              showTitle: false,
                            ),
                          if (_qazaPercent > 0)
                            PieChartSectionData(
                              value: _qazaPercent,
                              color: AppColors.qaza,
                              radius: 40,
                              showTitle: false,
                            ),
                          if (_missedPercent > 0)
                            PieChartSectionData(
                              value: _missedPercent,
                              color: AppColors.missed.withValues(alpha: 0.7),
                              radius: 40,
                              showTitle: false,
                            ),
                        ],
                        pieTouchData: PieTouchData(enabled: false),
                      ),
                    ),
            ),
            if (total > 0) ...[
              const SizedBox(height: 16),
              _LegendRow(
                color: const Color(0xFF1B5E3B),
                label: 'On-Time',
                percent: _onTimePercent,
              ),
              const SizedBox(height: 8),
              _LegendRow(
                color: AppColors.qaza,
                label: 'Qaza',
                percent: _qazaPercent,
              ),
              const SizedBox(height: 8),
              _LegendRow(
                color: AppColors.missed,
                label: 'Missed',
                percent: _missedPercent,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final double progress;
  final bool isDashed;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.progress,
    this.isDashed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AC.card(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: AC.isDark(context) ? 0.25 : 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AC.textSub(context)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1,
                  color: AC.textSub(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AC.border(context),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final double percent;

  const _LegendRow({
    required this.color,
    required this.label,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 14, color: AC.textSub(context)),
          ),
        ),
        Text(
          '${percent.round()}%',
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AC.text(context)),
        ),
      ],
    );
  }
}

/// Small colour pill used in the bar-chart legend.
class _ChartLegend extends StatelessWidget {
  final Color color;
  final String label;
  const _ChartLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AC.textSub(context),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
