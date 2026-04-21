import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:time_block/database/DayEventsRecord.dart';
import 'package:time_block/database/EventInfoRecord.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 图表类型枚举
// ─────────────────────────────────────────────────────────────────────────────
enum ChartType { line, pie, bar }

// ─────────────────────────────────────────────────────────────────────────────
// 数据计算层：统计每日各 eventInfo 的分钟数
// ─────────────────────────────────────────────────────────────────────────────
class AnalyzeData {
    /// 按日期排序的日期列表 (yyyyMMdd)
    final List<String> dates;

    /// dayMinutes[date][eventName] = 分钟数
    final Map<String, Map<String, int>> dayMinutes;

    /// 选中的 eventName 列表
    final List<String> selectedEvents;

    const AnalyzeData({
        required this.dates,
        required this.dayMinutes,
        required this.selectedEvents,
    });

    /// 统计某个 event 在所有日期内的总分钟数
    int totalMinutes(String eventName) {
        int total = 0;
        for (final d in dates) {
            total += (dayMinutes[d]?[eventName] ?? 0);
        }
        return total;
    }

    /// 全部选中事项的总分钟数
    int get grandTotal {
        int total = 0;
        for (final e in selectedEvents) {
            total += totalMinutes(e);
        }
        return total;
    }

    static AnalyzeData compute({
        required DateTime start,
        required DateTime end,
        required List<String> selectedEvents,
        required Box<DayEventsRecord> box,
    }) {
        final List<String> dates = [];
        final Map<String, Map<String, int>> dayMinutes = {};

        DateTime cur = DateTime(start.year, start.month, start.day);
        final endDay = DateTime(end.year, end.month, end.day);

        while (!cur.isAfter(endDay)) {
            final key = '${cur.year}${cur.month.toString().padLeft(2, '0')}${cur.day.toString().padLeft(2, '0')}';
            dates.add(key);

            final record = box.get(key);
            final Map<String, int> mins = {};
            if (record != null) {
                for (final ev in record.events) {
                    if (selectedEvents.contains(ev.eventInfo)) {
                        final m = (ev.endIndex - ev.startIndex + 1) * 15;
                        mins[ev.eventInfo] = (mins[ev.eventInfo] ?? 0) + m;
                    }
                }
            }
            dayMinutes[key] = mins;
            cur = cur.add(const Duration(days: 1));
        }

        return AnalyzeData(
            dates: dates,
            dayMinutes: dayMinutes,
            selectedEvents: selectedEvents,
        );
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 主页面
// ─────────────────────────────────────────────────────────────────────────────
class AnalyzeView extends StatefulWidget {
    const AnalyzeView({super.key, required this.title});
    final String title;

    @override
    State<AnalyzeView> createState() => _AnalyzeViewState();
}

class _AnalyzeViewState extends State<AnalyzeView> {
    // ── 时间段 ──
    DateTime _startDate = DateTime.now().subtract(const Duration(days: 29));
    DateTime _endDate = DateTime.now();

    // ── 事项选择 ──
    List<String> _allEventNames = [];
    Set<String> _selectedEvents = {};
    Map<String, Color> _eventColors = {};

    // ── 图表类型 ──
    ChartType _chartType = ChartType.line;

    // ── 计算结果 ──
    AnalyzeData? _data;

    // ── Hive box ──
    Box<DayEventsRecord>? _dayBox;
    Box<EventInfoRecord>? _infoBox;

    // ── 滑动手势起始 X ──
    double _dragStartX = 0;

    @override
    void initState() {
        super.initState();
        _loadEventInfos();
    }

    void _loadEventInfos() {
        try {
            _dayBox = Hive.box<DayEventsRecord>('dayRecords');
            _infoBox = Hive.box<EventInfoRecord>('eventInfo');
            final List<String> names = [];
            final Map<String, Color> colors = {};
            for (final key in _infoBox!.keys) {
                final rec = _infoBox!.get(key as String);
                if (rec != null) {
                    names.add(rec.eventName);
                    final c = rec.color_rgb;
                    colors[rec.eventName] = Color.fromRGBO(c[0], c[1], c[2], 1);
                }
            }
            setState(() {
                _allEventNames = names;
                _selectedEvents = names.toSet();
                _eventColors = colors;
            });
            _recompute();
        } catch (_) {}
    }

    void _recompute() {
        if (_dayBox == null) return;
        setState(() {
            _data = AnalyzeData.compute(
                start: _startDate,
                end: _endDate,
                selectedEvents: _selectedEvents.toList(),
                box: _dayBox!,
            );
        });
    }

    // ─────────────────────────────────────
    // 时间范围左右滑动偏移
    // ─────────────────────────────────────
    void _shiftRange(int direction) {
        // direction: -1 = 向前（更早），+1 = 向后（更新）
        final days = _endDate.difference(_startDate).inDays + 1;
        final shift = Duration(days: days * direction);
        setState(() {
            _startDate = _startDate.add(shift);
            _endDate = _endDate.add(shift);
        });
        _recompute();
    }

    // ─────────────────────────────────────
    // 时间段选择器（日期范围弹窗）
    // ─────────────────────────────────────
    Future<void> _pickDateRange(BuildContext context) async {
        // 使用自定义双日历弹窗，避免依赖 flutter_localizations
        final result = await showDialog<DateTimeRange>(
            context: context,
            builder: (ctx) => _DateRangePickerDialog(
                initialStart: _startDate,
                initialEnd: _endDate,
            ),
        );
        if (result != null) {
            setState(() {
                _startDate = result.start;
                _endDate = result.end;
            });
            _recompute();
        }
    }

    // ─────────────────────────────────────
    // 事项多选弹窗
    // ─────────────────────────────────────
    Future<void> _showEventPicker(BuildContext context) async {
        Set<String> tempSelected = Set.from(_selectedEvents);

        await showModalBottomSheet(
            context: context,
            backgroundColor: const Color(0xFF111111),
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            builder: (ctx) {
                return StatefulBuilder(builder: (ctx2, setBS) {
                    return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                            Padding(
                                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                                child: Row(
                                    children: [
                                        const Text('选择事项', style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 14, fontWeight: FontWeight.w600)),
                                        const Spacer(),
                                        TextButton(
                                            onPressed: () {
                                                setBS(() => tempSelected = _allEventNames.toSet());
                                            },
                                            child: const Text('全选', style: TextStyle(color: Color(0xFFFFCA28), fontSize: 12)),
                                        ),
                                        TextButton(
                                            onPressed: () {
                                                setBS(() => tempSelected.clear());
                                            },
                                            child: const Text('全不选', style: TextStyle(color: Color(0xFF888888), fontSize: 12)),
                                        ),
                                    ],
                                ),
                            ),
                            const Divider(height: 1, color: Color(0xFF2A2A2A)),
                            Flexible(
                                child: ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: _allEventNames.length,
                                    itemBuilder: (_, i) {
                                        final name = _allEventNames[i];
                                        final color = _eventColors[name] ?? Colors.grey;
                                        final selected = tempSelected.contains(name);
                                        return InkWell(
                                            onTap: () {
                                                setBS(() {
                                                    if (selected) {
                                                        tempSelected.remove(name);
                                                    } else {
                                                        tempSelected.add(name);
                                                    }
                                                });
                                            },
                                            child: Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                                child: Row(
                                                    children: [
                                                        Container(
                                                            width: 12, height: 12,
                                                            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                                                        ),
                                                        const SizedBox(width: 10),
                                                        Expanded(child: Text(name, style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 13))),
                                                        AnimatedContainer(
                                                            duration: const Duration(milliseconds: 150),
                                                            width: 20, height: 20,
                                                            decoration: BoxDecoration(
                                                                color: selected ? const Color(0xFFFFCA28) : Colors.transparent,
                                                                borderRadius: BorderRadius.circular(4),
                                                                border: Border.all(
                                                                    color: selected ? const Color(0xFFFFCA28) : const Color(0xFF444444),
                                                                    width: 1.5,
                                                                ),
                                                            ),
                                                            child: selected
                                                                ? const Icon(Icons.check, size: 13, color: Colors.black)
                                                                : null,
                                                        ),
                                                    ],
                                                ),
                                            ),
                                        );
                                    },
                                ),
                            ),
                            Padding(
                                padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
                                child: SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFFFFCA28),
                                            foregroundColor: Colors.black,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        onPressed: () {
                                            setState(() => _selectedEvents = tempSelected);
                                            Navigator.pop(ctx);
                                            _recompute();
                                        },
                                        child: const Text('确认', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                    ),
                                ),
                            ),
                        ],
                    );
                });
            },
        );
    }

    // ─────────────────────────────────────
    // Build
    // ─────────────────────────────────────
    @override
    Widget build(BuildContext context) {
        final String rangeLabel =
            '${_fmt(_startDate)}  →  ${_fmt(_endDate)}  (${_endDate.difference(_startDate).inDays + 1}天)';

        return Scaffold(
            backgroundColor: const Color(0xFF0A0A0A),
            body: Column(
                children: [
                    // ── 时间段选择器 ──
                    _buildDateRangeBar(context, rangeLabel),

                    // ── 事项多选入口 ──
                    _buildEventFilterBar(context),

                    // ── 三分类切换 ──
                    _buildChartTypeBar(),

                    // ── 图表区域（70%高度，支持左右滑动切换范围）──
                    Expanded(
                        child: GestureDetector(
                            onHorizontalDragStart: (d) => _dragStartX = d.globalPosition.dx,
                            onHorizontalDragEnd: (d) {
                                final dx = d.globalPosition.dx - _dragStartX;
                                if (dx.abs() > 40) {
                                    _shiftRange(dx > 0 ? -1 : 1);
                                }
                            },
                            child: _buildChartArea(),
                        ),
                    ),
                ],
            ),
        );
    }

    // ─────────────────────────────────────
    // 顶部时间段选择条
    // ─────────────────────────────────────
    Widget _buildDateRangeBar(BuildContext context, String label) {
        return GestureDetector(
            onTap: () => _pickDateRange(context),
            child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                    color: const Color(0xFF151515),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF2A2A2A)),
                ),
                child: Row(
                    children: [
                        const Icon(Icons.date_range, size: 14, color: Color(0xFFFFCA28)),
                        const SizedBox(width: 8),
                        Text(label, style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 12)),
                        const Spacer(),
                        const Icon(Icons.expand_more, size: 16, color: Color(0xFF666666)),
                    ],
                ),
            ),
        );
    }

    // ─────────────────────────────────────
    // 事项筛选条
    // ─────────────────────────────────────
    Widget _buildEventFilterBar(BuildContext context) {
        final selectedCount = _selectedEvents.length;
        final totalCount = _allEventNames.length;
        return GestureDetector(
            onTap: () => _showEventPicker(context),
            child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                    color: const Color(0xFF151515),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF2A2A2A)),
                ),
                child: Row(
                    children: [
                        const Icon(Icons.filter_list, size: 14, color: Color(0xFF888888)),
                        const SizedBox(width: 8),
                        // 颜色点预览（最多显示8个）
                        ..._selectedEvents.take(8).map((name) {
                            final c = _eventColors[name] ?? Colors.grey;
                            return Container(
                                width: 8, height: 8,
                                margin: const EdgeInsets.only(right: 3),
                                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                            );
                        }),
                        const SizedBox(width: 4),
                        Text(
                            selectedCount == totalCount
                                ? '全部事项 ($totalCount)'
                                : '已选 $selectedCount / $totalCount 项',
                            style: const TextStyle(color: Color(0xFF888888), fontSize: 11),
                        ),
                        const Spacer(),
                        const Icon(Icons.chevron_right, size: 14, color: Color(0xFF444444)),
                    ],
                ),
            ),
        );
    }

    // ─────────────────────────────────────
    // 三分类切换选择器
    // ─────────────────────────────────────
    Widget _buildChartTypeBar() {
        return Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            height: 36,
            decoration: BoxDecoration(
                color: const Color(0xFF151515),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2A2A2A)),
            ),
            child: Row(
                children: [
                    _typeTab(ChartType.line, Icons.show_chart, '折线'),
                    _divider(),
                    _typeTab(ChartType.pie, Icons.pie_chart_outline, '饼图'),
                    _divider(),
                    _typeTab(ChartType.bar, Icons.bar_chart, '柱状'),
                ],
            ),
        );
    }

    Widget _divider() => Container(width: 1, color: const Color(0xFF2A2A2A));

    Widget _typeTab(ChartType type, IconData icon, String label) {
        final active = _chartType == type;
        return Expanded(
            child: GestureDetector(
                onTap: () => setState(() => _chartType = type),
                child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                        color: active ? const Color(0xFF2A2200) : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                    ),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                            Icon(icon, size: 14, color: active ? const Color(0xFFFFCA28) : const Color(0xFF666666)),
                            const SizedBox(width: 4),
                            Text(label, style: TextStyle(
                                fontSize: 11,
                                color: active ? const Color(0xFFFFCA28) : const Color(0xFF666666),
                                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                            )),
                        ],
                    ),
                ),
            ),
        );
    }

    // ─────────────────────────────────────
    // 图表区域
    // ─────────────────────────────────────
    Widget _buildChartArea() {
        if (_data == null || _data!.selectedEvents.isEmpty) {
            return const Center(child: Text('暂无数据', style: TextStyle(color: Color(0xFF444444))));
        }
        return Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
            decoration: BoxDecoration(
                color: const Color(0xFF0F0F0F),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF1E1E1E)),
            ),
            child: Column(
                children: [
                    // 滑动提示
                    Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                            Icon(Icons.chevron_left, size: 12, color: Color(0xFF333333)),
                            SizedBox(width: 4),
                            Text('左右滑动切换时间范围', style: TextStyle(color: Color(0xFF333333), fontSize: 9)),
                            SizedBox(width: 4),
                            Icon(Icons.chevron_right, size: 12, color: Color(0xFF333333)),
                        ],
                    ),
                    const SizedBox(height: 4),
                    Expanded(child: _buildChart()),
                    const SizedBox(height: 8),
                    _buildLegend(),
                ],
            ),
        );
    }

    Widget _buildChart() {
        switch (_chartType) {
            case ChartType.line: return _LineChart(data: _data!, eventColors: _eventColors);
            case ChartType.pie:  return _PieChart(data: _data!, eventColors: _eventColors);
            case ChartType.bar:  return _BarChart(data: _data!, eventColors: _eventColors);
        }
    }

    // ─────────────────────────────────────
    // 图例
    // ─────────────────────────────────────
    Widget _buildLegend() {
        final data = _data!;
        return Wrap(
            spacing: 10,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: data.selectedEvents.map((name) {
                final color = _eventColors[name] ?? Colors.grey;
                final total = data.totalMinutes(name);
                final h = total ~/ 60;
                final m = total % 60;
                final timeStr = h > 0 ? '${h}h${m > 0 ? '${m}m' : ''}' : '${m}m';
                return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                        const SizedBox(width: 4),
                        Text('$name $timeStr', style: const TextStyle(color: Color(0xFF888888), fontSize: 9)),
                    ],
                );
            }).toList(),
        );
    }

    String _fmt(DateTime d) => '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}

// ─────────────────────────────────────────────────────────────────────────────
// 自定义日期范围选择弹窗（不依赖 flutter_localizations）
// ─────────────────────────────────────────────────────────────────────────────
class _DateRangePickerDialog extends StatefulWidget {
    final DateTime initialStart;
    final DateTime initialEnd;

    const _DateRangePickerDialog({
        required this.initialStart,
        required this.initialEnd,
    });

    @override
    State<_DateRangePickerDialog> createState() => _DateRangePickerDialogState();
}

class _DateRangePickerDialogState extends State<_DateRangePickerDialog> {
    late DateTime _viewMonth; // 当前展示的月份
    DateTime? _start;
    DateTime? _end;
    bool _selectingStart = true; // true = 正在选开始日期

    @override
    void initState() {
        super.initState();
        _start = DateTime(widget.initialStart.year, widget.initialStart.month, widget.initialStart.day);
        _end = DateTime(widget.initialEnd.year, widget.initialEnd.month, widget.initialEnd.day);
        _viewMonth = DateTime(_start!.year, _start!.month, 1);
        _selectingStart = false; // 默认显示已有范围
    }

    void _prevMonth() => setState(() {
        _viewMonth = DateTime(_viewMonth.year, _viewMonth.month - 1, 1);
    });

    void _nextMonth() => setState(() {
        _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + 1, 1);
    });

    void _onDayTap(DateTime day) {
        setState(() {
            if (_selectingStart) {
                _start = day;
                _end = null;
                _selectingStart = false;
            } else {
                if (day.isBefore(_start!)) {
                    _end = _start;
                    _start = day;
                } else {
                    _end = day;
                }
                _selectingStart = true;
            }
        });
    }

    bool _inRange(DateTime day) {
        if (_start == null || _end == null) return false;
        return !day.isBefore(_start!) && !day.isAfter(_end!);
    }

    static const List<String> _weekLabels = ['一', '二', '三', '四', '五', '六', '日'];

    @override
    Widget build(BuildContext context) {
        final int daysInMonth = DateUtils.getDaysInMonth(_viewMonth.year, _viewMonth.month);
        // 该月第一天是周几（1=周一，7=周日）
        final int firstWeekday = DateTime(_viewMonth.year, _viewMonth.month, 1).weekday;
        final int leadingBlanks = firstWeekday - 1;
        final int totalCells = leadingBlanks + daysInMonth;
        final int rowCount = (totalCells / 7).ceil();

        final String fmt = _fmtDate;
        final bool hasRange = _start != null && _end != null;

        return Dialog(
            backgroundColor: const Color(0xFF111111),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        // ── 标题 + 状态 ──
                        Text(
                            _selectingStart ? '选择开始日期' : '选择结束日期',
                            style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                            hasRange ? '${_fmtD(_start!)}  →  ${_fmtD(_end!)}' : (_start != null ? _fmtD(_start!) : '请选择时间段'),
                            style: const TextStyle(color: Color(0xFFFFCA28), fontSize: 11),
                        ),
                        const SizedBox(height: 12),

                        // ── 月份导航 ──
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                                IconButton(
                                    onPressed: _prevMonth,
                                    icon: const Icon(Icons.chevron_left, color: Color(0xFF888888), size: 20),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                ),
                                Text(
                                    '${_viewMonth.year}年${_viewMonth.month}月',
                                    style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                IconButton(
                                    onPressed: _nextMonth,
                                    icon: const Icon(Icons.chevron_right, color: Color(0xFF888888), size: 20),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                ),
                            ],
                        ),
                        const SizedBox(height: 8),

                        // ── 周标题行 ──
                        Row(
                            children: _weekLabels.map((w) => Expanded(
                                child: Center(
                                    child: Text(w, style: const TextStyle(color: Color(0xFF555555), fontSize: 10)),
                                ),
                            )).toList(),
                        ),
                        const SizedBox(height: 4),

                        // ── 日历格 ──
                        ...List.generate(rowCount, (row) {
                            return Row(
                                children: List.generate(7, (col) {
                                    final cellIdx = row * 7 + col;
                                    final dayNum = cellIdx - leadingBlanks + 1;
                                    if (dayNum < 1 || dayNum > daysInMonth) {
                                        return const Expanded(child: SizedBox(height: 30));
                                    }
                                    final day = DateTime(_viewMonth.year, _viewMonth.month, dayNum);
                                    final isStart = _start != null && day == _start;
                                    final isEnd = _end != null && day == _end;
                                    final inRange = _inRange(day);
                                    final isToday = day == DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

                                    Color bg = Colors.transparent;
                                    Color fg = const Color(0xFFCCCCCC);
                                    if (isStart || isEnd) {
                                        bg = const Color(0xFFFFCA28);
                                        fg = Colors.black;
                                    } else if (inRange) {
                                        bg = const Color(0xFF2A2200);
                                        fg = const Color(0xFFFFCA28);
                                    }

                                    return Expanded(
                                        child: GestureDetector(
                                            onTap: () => _onDayTap(day),
                                            child: Container(
                                                height: 30,
                                                margin: const EdgeInsets.all(1),
                                                decoration: BoxDecoration(
                                                    color: bg,
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: isToday && !isStart && !isEnd
                                                        ? Border.all(color: const Color(0xFF555500), width: 1)
                                                        : null,
                                                ),
                                                child: Center(
                                                    child: Text(
                                                        '$dayNum',
                                                        style: TextStyle(fontSize: 11, color: fg),
                                                    ),
                                                ),
                                            ),
                                        ),
                                    );
                                }),
                            );
                        }),

                        const SizedBox(height: 12),

                        // ── 操作按钮 ──
                        Row(
                            children: [
                                Expanded(
                                    child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                            side: const BorderSide(color: Color(0xFF333333)),
                                            foregroundColor: const Color(0xFF888888),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('取消', style: TextStyle(fontSize: 12)),
                                    ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFFFFCA28),
                                            foregroundColor: Colors.black,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        onPressed: hasRange
                                            ? () => Navigator.pop(context, DateTimeRange(start: _start!, end: _end!))
                                            : null,
                                        child: const Text('确认', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                    ),
                                ),
                            ],
                        ),
                    ],
                ),
            ),
        );
    }

    String get _fmtDate => '';
    String _fmtD(DateTime d) => '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}

// ─────────────────────────────────────────────────────────────────────────────
// 折线图组件
// ─────────────────────────────────────────────────────────────────────────────
class _LineChart extends StatelessWidget {
    final AnalyzeData data;
    final Map<String, Color> eventColors;

    const _LineChart({required this.data, required this.eventColors});

    @override
    Widget build(BuildContext context) {
        if (data.dates.isEmpty) return const SizedBox();

        // X 轴最大点数，超过 60 天时做降采样（每 N 天取一个点）
        final int totalDays = data.dates.length;
        final int step = totalDays > 60 ? (totalDays / 60).ceil() : 1;

        // 构建折线数据
        final List<LineChartBarData> lines = [];
        double maxY = 0;

        for (final eventName in data.selectedEvents) {
            final color = eventColors[eventName] ?? Colors.grey;
            final List<FlSpot> spots = [];
            for (int i = 0; i < totalDays; i += step) {
                final mins = (data.dayMinutes[data.dates[i]]?[eventName] ?? 0).toDouble();
                spots.add(FlSpot(i.toDouble(), mins));
                if (mins > maxY) maxY = mins;
            }
            lines.add(LineChartBarData(
                spots: spots,
                isCurved: true,
                preventCurveOverShooting: true,
                preventCurveOvershootingThreshold: 0,
                color: color,
                barWidth: 1.5,
                dotData: FlDotData(show: totalDays <= 31),
                belowBarData: BarAreaData(show: false),
            ));
        }

        if (maxY == 0) maxY = 60;

        // X 轴标签：最多显示 6 个日期
        final int labelStep = math.max(1, (data.dates.length / 6).ceil());

        return LineChart(
            LineChartData(
                backgroundColor: Colors.transparent,
                minX: 0,
                maxX: (totalDays - 1).toDouble(),
                minY: 0,
                maxY: (maxY * 1.2).ceilToDouble(),
                gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => FlLine(color: const Color(0xFF1E1E1E), strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 36,
                            getTitlesWidget: (value, _) {
                                final h = value.toInt() ~/ 60;
                                final m = value.toInt() % 60;
                                final str = h > 0 ? '${h}h' : '${m}m';
                                return Text(str, style: const TextStyle(color: Color(0xFF555555), fontSize: 8));
                            },
                        ),
                    ),
                    bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 18,
                            getTitlesWidget: (value, _) {
                                final idx = value.toInt();
                                if (idx % labelStep != 0) return const SizedBox();
                                if (idx < 0 || idx >= data.dates.length) return const SizedBox();
                                final d = data.dates[idx];
                                return Text(
                                    '${d.substring(4, 6)}/${d.substring(6)}',
                                    style: const TextStyle(color: Color(0xFF555555), fontSize: 8),
                                );
                            },
                        ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                lineBarsData: lines,
            ),
        );
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 饼图组件
// ─────────────────────────────────────────────────────────────────────────────
class _PieChart extends StatefulWidget {
    final AnalyzeData data;
    final Map<String, Color> eventColors;

    const _PieChart({required this.data, required this.eventColors});

    @override
    State<_PieChart> createState() => _PieChartState();
}

class _PieChartState extends State<_PieChart> {
    int _touchedIndex = -1;

    @override
    Widget build(BuildContext context) {
        final List<PieChartSectionData> sections = [];
        int idx = 0;
        for (final name in widget.data.selectedEvents) {
            final total = widget.data.totalMinutes(name);
            if (total == 0) { idx++; continue; }
            final color = widget.eventColors[name] ?? Colors.grey;
            final isTouched = idx == _touchedIndex;
            final h = total ~/ 60;
            final m = total % 60;
            final timeStr = h > 0 ? '${h}h${m > 0 ? '${m}m' : ''}' : '${m}m';
            sections.add(PieChartSectionData(
                color: color,
                value: total.toDouble(),
                title: isTouched ? '$name\n$timeStr' : '',
                radius: isTouched ? 80 : 65,
                titleStyle: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
                titlePositionPercentageOffset: 0.6,
            ));
            idx++;
        }

        if (sections.isEmpty) {
            return const Center(child: Text('无有效数据', style: TextStyle(color: Color(0xFF444444))));
        }

        return PieChart(
            PieChartData(
                pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                        setState(() {
                            if (!event.isInterestedForInteractions || response?.touchedSection == null) {
                                _touchedIndex = -1;
                            } else {
                                _touchedIndex = response!.touchedSection!.touchedSectionIndex;
                            }
                        });
                    },
                ),
                borderData: FlBorderData(show: false),
                sectionsSpace: 2,
                centerSpaceRadius: 30,
                sections: sections,
            ),
        );
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 横向柱状图组件
// ─────────────────────────────────────────────────────────────────────────────
class _BarChart extends StatelessWidget {
    final AnalyzeData data;
    final Map<String, Color> eventColors;

    const _BarChart({required this.data, required this.eventColors});

    @override
    Widget build(BuildContext context) {
        // 按总时长降序排列
        final sorted = data.selectedEvents
            .map((name) => MapEntry(name, data.totalMinutes(name)))
            .where((e) => e.value > 0)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        if (sorted.isEmpty) {
            return const Center(child: Text('无有效数据', style: TextStyle(color: Color(0xFF444444))));
        }

        final maxMins = sorted.first.value;

        // 名称列宽 + 时间列宽固定，柱子占剩余空间
        const double nameColW = 64.0;
        const double timeColW = 44.0;
        const double hPad = 8.0; // 每行左右 padding 各 4

        return LayoutBuilder(builder: (ctx, constraints) {
            // 柱子最大可用宽度 = 总宽 - 名称列 - 时间列 - 间距 - padding
            final barMaxWidth = constraints.maxWidth - nameColW - timeColW - 12 - hPad * 2;

            return ListView.builder(
                itemCount: sorted.length,
                itemBuilder: (_, i) {
                    final name = sorted[i].key;
                    final mins = sorted[i].value;
                    final color = eventColors[name] ?? Colors.grey;
                    final barFraction = maxMins > 0 ? mins / maxMins : 0.0;
                    final barWidth = (barFraction * barMaxWidth).clamp(0.0, barMaxWidth);
                    final h = mins ~/ 60;
                    final m = mins % 60;
                    final timeStr = h > 0 ? '${h}h${m > 0 ? '${m}m' : ''}' : '${m}m';

                    return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: hPad),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                                // 固定宽度事项名
                                SizedBox(
                                    width: nameColW,
                                    child: Text(
                                        name,
                                        style: const TextStyle(color: Color(0xFF999999), fontSize: 10),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                    ),
                                ),
                                // 柱子区域（Flexible 保证不溢出）
                                Expanded(
                                    child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 400),
                                            curve: Curves.easeOut,
                                            width: barWidth,
                                            height: 16,
                                            decoration: BoxDecoration(
                                                color: color,
                                                borderRadius: BorderRadius.circular(3),
                                            ),
                                        ),
                                    ),
                                ),
                                const SizedBox(width: 6),
                                // 固定宽度时间标签（右对齐）
                                SizedBox(
                                    width: timeColW,
                                    child: Text(
                                        timeStr,
                                        style: const TextStyle(color: Color(0xFF666666), fontSize: 9),
                                        textAlign: TextAlign.right,
                                        overflow: TextOverflow.ellipsis,
                                    ),
                                ),
                            ],
                        ),
                    );
                },
            );
        });
    }
}
