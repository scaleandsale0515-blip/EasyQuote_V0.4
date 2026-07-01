import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../models/quote_doc.dart';
import '../storage/local_db.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'documents_list_screen.dart';
import 'backup_screen.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum _StatFilter { all, thisWeek, thisMonth, custom }

enum _GraphMetric { invoiceTotal, amountPaid, outstanding, quotationCount }

enum _GraphPeriod { month, quarter, year, custom }

// ─── Dashboard Screen ─────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Stat card filter
  _StatFilter _statFilter = _StatFilter.all;
  DateTimeRange? _statCustomRange;

  // Graph controls
  _GraphMetric _metric = _GraphMetric.invoiceTotal;
  _GraphPeriod _graphPeriod = _GraphPeriod.month;
  DateTimeRange? _graphCustomRange;

  bool _bannerDismissed = false;

  // ─── Helpers ──────────────────────────────────────────────────────────────

  List<QuoteDoc> _applyStatFilter(List<QuoteDoc> docs) {
    final now = DateTime.now();
    switch (_statFilter) {
      case _StatFilter.all:
        return docs;
      case _StatFilter.thisWeek:
        final start = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        final end = start.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
        return docs.where((d) => !d.date.isBefore(start) && !d.date.isAfter(end)).toList();
      case _StatFilter.thisMonth:
        return docs.where((d) => d.date.year == now.year && d.date.month == now.month).toList();
      case _StatFilter.custom:
        if (_statCustomRange == null) return docs;
        final end = _statCustomRange!.end.add(const Duration(days: 1));
        return docs
            .where((d) => !d.date.isBefore(_statCustomRange!.start) && d.date.isBefore(end))
            .toList();
    }
  }

  Future<void> _pickStatCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _statCustomRange,
    );
    if (picked != null) setState(() { _statCustomRange = picked; _statFilter = _StatFilter.custom; });
  }

  Future<void> _pickGraphCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _graphCustomRange,
    );
    if (picked != null) setState(() { _graphCustomRange = picked; _graphPeriod = _GraphPeriod.custom; });
  }

  String get _statFilterLabel {
    switch (_statFilter) {
      case _StatFilter.all: return 'All time';
      case _StatFilter.thisWeek: return 'This Week';
      case _StatFilter.thisMonth: return 'This Month';
      case _StatFilter.custom:
        if (_statCustomRange == null) return 'Custom Range';
        return '${formatDate(_statCustomRange!.start)} – ${formatDate(_statCustomRange!.end)}';
    }
  }

  // ─── Graph data builder ───────────────────────────────────────────────────

  _ChartData _buildChartData(List<QuoteDoc> allDocs) {
    final now = DateTime.now();

    // Docs relevant to the current metric (invoices or quotations)
    final relevantDocs = _metric == _GraphMetric.quotationCount
        ? allDocs.where((d) => d.type == DocType.quotation).toList()
        : allDocs.where((d) => d.type == DocType.invoice).toList();

    double metricValue(List<QuoteDoc> bucket) {
      switch (_metric) {
        case _GraphMetric.invoiceTotal:
          return bucket.fold(0.0, (s, d) => s + d.total);
        case _GraphMetric.amountPaid:
          return bucket.fold(0.0, (s, d) => s + (d.status == DocStatus.paid ? d.total : d.amountPaid));
        case _GraphMetric.outstanding:
          return bucket.fold(0.0, (s, d) => s + (d.status == DocStatus.paid ? 0.0 : d.balanceDue));
        case _GraphMetric.quotationCount:
          return bucket.length.toDouble();
      }
    }

    List<_Bar> bars;
    switch (_graphPeriod) {
      case _GraphPeriod.month:
        // Show only dates in the current month that actually have documents.
        final daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);
        final Map<int, List<QuoteDoc>> byDay = {};
        for (final d in relevantDocs) {
          if (d.date.year == now.year && d.date.month == now.month) {
            byDay.putIfAbsent(d.date.day, () => []).add(d);
          }
        }
        if (byDay.isEmpty) {
          // Nothing this month — show full month with all zeros so the
          // chart isn't just empty blank space.
          bars = List.generate(daysInMonth, (i) => _Bar('${i + 1}', 0));
        } else {
          //bars = byDay.entries.toList()
          //  ..sort((a, b) => a.key.compareTo(b.key));
          //bars = bars.map((e) => _Bar('${e.key}', metricValue(e.value))).toList();
         final sortedEntries = byDay.entries.toList()
  ..sort((a, b) => a.key.compareTo(b.key));

bars = sortedEntries
  .map((e) => _Bar(
        '${e.key}',
        metricValue(e.value), // ✅ convert to double
      ))
  .toList();
        }
        break;

      case _GraphPeriod.quarter:
        // 4 columns — Q1 to Q4 of the current year.
        const qLabels = ['Q1', 'Q2', 'Q3', 'Q4'];
        bars = List.generate(4, (qi) {
          final qDocs = relevantDocs.where((d) {
            if (d.date.year != now.year) return false;
            final q = ((d.date.month - 1) ~/ 3);
            return q == qi;
          }).toList();
          return _Bar(qLabels[qi], metricValue(qDocs));
        });
        break;

      case _GraphPeriod.year:
        // 12 monthly columns for the current year.
        const mLabels = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
        bars = List.generate(12, (mi) {
          final mDocs = relevantDocs.where((d) =>
              d.date.year == now.year && d.date.month == mi + 1).toList();
          return _Bar(mLabels[mi], metricValue(mDocs));
        });
        break;

      case _GraphPeriod.custom:
        if (_graphCustomRange == null) {
          bars = [_Bar('—', 0)];
          break;
        }
        final rangeStart = _graphCustomRange!.start;
        final rangeEnd = _graphCustomRange!.end;
        final spanDays = rangeEnd.difference(rangeStart).inDays + 1;

        if (spanDays <= 31) {
          // Daily bars — only dates that have documents (same as Month view).
          final Map<String, List<QuoteDoc>> byDay = {};
          for (final d in relevantDocs) {
            if (!d.date.isBefore(rangeStart) &&
                !d.date.isAfter(rangeEnd.add(const Duration(days: 1)))) {
              final key = '${d.date.day}/${d.date.month}';
              byDay.putIfAbsent(key, () => []).add(d);
            }
          }
          if (byDay.isEmpty) {
            bars = [_Bar('No data', 0)];
          } else {
            // Sort by date
            final sortedKeys = byDay.keys.toList()
              ..sort((a, b) {
                final ap = a.split('/').map(int.parse).toList();
                final bp = b.split('/').map(int.parse).toList();
                if (ap[1] != bp[1]) return ap[1].compareTo(bp[1]);
                return ap[0].compareTo(bp[0]);
              });
            bars = sortedKeys.map((k) => _Bar(k, metricValue(byDay[k]!))).toList();
          }
        } else if (spanDays <= 90) {
          // Weekly bars.
          final weeks = <DateTime>[];
          var wStart = rangeStart;
          while (!wStart.isAfter(rangeEnd)) {
            weeks.add(wStart);
            wStart = wStart.add(const Duration(days: 7));
          }
          bars = weeks.map((ws) {
            final we = ws.add(const Duration(days: 6));
            final wDocs = relevantDocs.where((d) =>
                !d.date.isBefore(ws) && !d.date.isAfter(we)).toList();
            return _Bar('${ws.day}/${ws.month}', metricValue(wDocs));
          }).toList();
        } else {
          // Monthly bars.
          final months = <DateTime>[];
          var cur = DateTime(rangeStart.year, rangeStart.month);
          while (!cur.isAfter(rangeEnd)) {
            months.add(cur);
            cur = DateTime(cur.year, cur.month + 1);
          }
          const mLabels = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
          bars = months.map((m) {
            final mDocs = relevantDocs.where((d) =>
                d.date.year == m.year && d.date.month == m.month).toList();
            return _Bar(mLabels[m.month - 1], metricValue(mDocs));
          }).toList();
        }
        break;
    }

    final maxVal = bars.fold(0.0, (a, b) => a > b.value ? a : b.value);
    return _ChartData(bars: bars, maxVal: maxVal);
  }

  // ─── UI helpers ───────────────────────────────────────────────────────────

  String get _metricLabel {
    switch (_metric) {
      case _GraphMetric.invoiceTotal: return 'Invoice Total';
      case _GraphMetric.amountPaid:   return 'Amount Paid';
      case _GraphMetric.outstanding:  return 'Outstanding';
      case _GraphMetric.quotationCount: return 'Quotation Count';
    }
  }

  bool get _metricIsCount => _metric == _GraphMetric.quotationCount;

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final allDocs = LocalDB.instance.getDocuments();
    final filteredDocs = _applyStatFilter(allDocs);
    final filteredInvoices = filteredDocs.where((d) => d.type == DocType.invoice).toList();
    final filteredQuotations = filteredDocs.where((d) => d.type == DocType.quotation).toList();

    final totalQuoted = filteredQuotations.fold(0.0, (s, d) => s + d.total);
    final totalInvoiced = filteredInvoices.fold(0.0, (s, d) => s + d.total);
    final totalPaid = filteredInvoices.fold(
      0.0,
      (s, d) => s + (d.status == DocStatus.paid ? d.total : d.amountPaid),
    );
    final totalOutstanding = filteredInvoices.fold(
      0.0,
      (s, d) => s + (d.status == DocStatus.paid ? 0.0 : d.balanceDue),
    );

    // Overdue always uses ALL invoices regardless of the stat filter —
    // overdue is a live current-state indicator, not a filtered view.
    final allInvoices = allDocs.where((d) => d.type == DocType.invoice).toList();
    final overdueInvoices = allInvoices.where((d) => d.isOverdue).toList();
    final overdueTotal = overdueInvoices.fold(0.0, (s, d) => s + d.balanceDue);

    final chart = _buildChartData(allDocs);
    final lastBackup = LocalDB.instance.getLastBackupAt();
    final needsBackupReminder = !_bannerDismissed &&
        (lastBackup == null || DateTime.now().difference(lastBackup).inDays >= 30);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (needsBackupReminder) _backupReminderBanner(lastBackup),

          // ── Stat card filter ─────────────────────────────────────────────
          _buildStatFilter(),
          const SizedBox(height: 10),

          // ── 4 stat cards ─────────────────────────────────────────────────
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.7,
            children: [
              _statCard('Quotations', filteredQuotations.length.toString(), formatRupees(totalQuoted)),
              _statCard('Invoices', filteredInvoices.length.toString(), formatRupees(totalInvoiced)),
              _statCard('Amount Paid', '', formatRupees(totalPaid), color: AppColors.ok),
              _statCard('Outstanding', '', formatRupees(totalOutstanding), color: AppColors.danger),
            ],
          ),

          const SizedBox(height: 22),

          // ── Graph header: metric dropdown + period filter ─────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildMetricDropdown(),
              const Spacer(),
              _buildPeriodFilter(),
            ],
          ),
          const SizedBox(height: 10),
          _buildGraphCustomRangeTile(),
          const SizedBox(height: 8),

          // ── Bar chart ────────────────────────────────────────────────────
          SizedBox(
            height: 200,
            child: chart.maxVal == 0
                ? const Center(child: Text('No data for this period', style: TextStyle(color: AppColors.inkSoft)))
                : BarChart(
                    BarChartData(
                      maxY: chart.maxVal * 1.25,
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (_) => AppColors.blueprintDk,
                          getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                            _metricIsCount
                                ? rod.toY.toInt().toString()
                                : formatRupees(rod.toY),
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                      barGroups: List.generate(
                        chart.bars.length,
                        (i) => BarChartGroupData(x: i, barRods: [
                          BarChartRodData(
                            toY: chart.bars[i].value,
                            color: AppColors.blueprint,
                            width: chart.bars.length > 10 ? 10 : chart.bars.length > 6 ? 16 : 22,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ]),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i < 0 || i >= chart.bars.length) return const SizedBox();
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  chart.bars[i].label,
                                  style: const TextStyle(fontSize: 9, color: AppColors.inkSoft),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                    ),
                  ),
          ),

          const SizedBox(height: 18),

          // ── Overdue card (always all-time, not filtered) ──────────────────
          _overdueCard(overdueInvoices.length, overdueTotal),
        ],
      ),
    );
  }

  // ─── Stat filter row ──────────────────────────────────────────────────────

  Widget _buildStatFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _statChip('All', _StatFilter.all),
          _statChip('This Week', _StatFilter.thisWeek),
          _statChip('This Month', _StatFilter.thisMonth),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              labelPadding: const EdgeInsets.symmetric(horizontal: 10),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              label: Text(
                _statFilter == _StatFilter.custom && _statCustomRange != null
                    ? '${formatDate(_statCustomRange!.start)} – ${formatDate(_statCustomRange!.end)}'
                    : 'Custom Range',
                style: const TextStyle(height: 1.0),
              ),
              selected: _statFilter == _StatFilter.custom,
              onSelected: (_) {
                if (_statFilter == _StatFilter.custom) {
                  setState(() { _statFilter = _StatFilter.all; _statCustomRange = null; });
                } else {
                  _pickStatCustomRange();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, _StatFilter f) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          labelPadding: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          label: Text(label, style: const TextStyle(height: 1.0)),
          selected: _statFilter == f,
          onSelected: (_) => setState(() {
            _statFilter = _statFilter == f && f != _StatFilter.all ? _StatFilter.all : f;
            _statCustomRange = null;
          }),
        ),
      );

  // ─── Graph metric dropdown ────────────────────────────────────────────────

  Widget _buildMetricDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_GraphMetric>(
          value: _metric,
          isDense: true,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
            color: AppColors.blueprintDk,
            letterSpacing: 0.3,
          ),
          items: const [
            DropdownMenuItem(value: _GraphMetric.invoiceTotal,    child: Text('Invoice Total')),
            DropdownMenuItem(value: _GraphMetric.amountPaid,      child: Text('Amount Paid')),
            DropdownMenuItem(value: _GraphMetric.outstanding,     child: Text('Outstanding')),
            DropdownMenuItem(value: _GraphMetric.quotationCount,  child: Text('Quotation Count')),
          ],
          onChanged: (v) => setState(() => _metric = v ?? _metric),
        ),
      ),
    );
  }

  // ─── Graph period filter ──────────────────────────────────────────────────

  Widget _buildPeriodFilter() {
     return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
    //return Row(
      children: [
        _periodChip('Month', _GraphPeriod.month),
        _periodChip('Quarter', _GraphPeriod.quarter),
        _periodChip('Year', _GraphPeriod.year),
        Padding(
          padding: const EdgeInsets.only(right: 0),
          child: ChoiceChip(
            labelPadding: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            label: const Text('Custom', style: TextStyle(height: 1.0, fontSize: 11.5)),
            selected: _graphPeriod == _GraphPeriod.custom,
            onSelected: (_) {
              if (_graphPeriod == _GraphPeriod.custom) {
                setState(() { _graphPeriod = _GraphPeriod.month; _graphCustomRange = null; });
              } else {
                _pickGraphCustomRange();
              }
            },
          ),
        ),
      ],
     ),
    );
  }

  Widget _periodChip(String label, _GraphPeriod p) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          labelPadding: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          label: Text(label, style: const TextStyle(height: 1.0, fontSize: 11.5)),
          selected: _graphPeriod == p,
          onSelected: (_) => setState(() {
            _graphPeriod = _graphPeriod == p ? _GraphPeriod.month : p;
            _graphCustomRange = null;
          }),
        ),
      );

  Widget _buildGraphCustomRangeTile() {
    if (_graphPeriod != _GraphPeriod.custom) return const SizedBox.shrink();
    return InkWell(
      onTap: _pickGraphCustomRange,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          _graphCustomRange == null
              ? 'Tap to pick a custom date range'
              : 'Range: ${formatDate(_graphCustomRange!.start)} – ${formatDate(_graphCustomRange!.end)}  (tap to change)',
          style: const TextStyle(color: AppColors.blueprintDk, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // ─── Overdue card ─────────────────────────────────────────────────────────

  Widget _overdueCard(int count, double amount) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DocumentsListScreen(docType: DocType.invoice, overdueOnly: true)),
      ),
      child: Card(
        color: count > 0 ? const Color(0xFFFBEFEC) : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: count > 0 ? AppColors.danger : AppColors.line),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OVERDUE INVOICES',
                      style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w700,
                        color: count > 0 ? AppColors.danger : AppColors.inkSoft,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      count == 0
                          ? 'None — you\'re all caught up'
                          : '$count invoice${count == 1 ? '' : 's'} • ${formatRupees(amount)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: count > 0 ? AppColors.danger : AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              if (count > 0) const Icon(Icons.chevron_right, color: AppColors.danger),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Stat card ────────────────────────────────────────────────────────────

  Widget _statCard(String label, String count, String amount, {Color color = AppColors.ink}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label.toUpperCase(),
                style: const TextStyle(fontSize: 10.5, color: AppColors.inkSoft, letterSpacing: 0.5)),
            const SizedBox(height: 6),
            if (count.isNotEmpty)
              Text(count, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            Text(amount,
                style: TextStyle(
                    fontSize: count.isEmpty ? 18 : 12.5,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ],
        ),
      ),
    );
  }

  // ─── Backup reminder ──────────────────────────────────────────────────────

  Widget _backupReminderBanner(DateTime? lastBackup) {
    final neverBackedUp = lastBackup == null;
    return Card(
      color: const Color(0xFFFFF6E5),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.backup_outlined, color: AppColors.rebar),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                neverBackedUp
                    ? 'You haven\'t backed up this device\'s data yet.'
                    : 'It\'s been over 30 days since your last backup.',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () async {
                await Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const BackupScreen()));
                setState(() {});
              },
              child: const Text('Back up'),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _bannerDismissed = true),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Data models ──────────────────────────────────────────────────────────────

class _Bar {
  final String label;
  final double value;
  const _Bar(this.label, this.value);
}

class _ChartData {
  final List<_Bar> bars;
  final double maxVal;
  _ChartData({required this.bars, required this.maxVal});
}
