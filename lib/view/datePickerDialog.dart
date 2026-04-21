import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:time_block/database/DayEventsRecord.dart';

/// 日期选择弹窗
/// 展示瀑布流日历（每行一周），通过 Hive dayRecords box 读取数据状态给色块着色。
/// 点击某天后调用 [onDateSelected] 回调并关闭弹窗。
/// 内置"回到今天"按钮跳回当前日期。
class DatePickerDialog extends StatefulWidget {
    /// 选中日期后的回调（格式 yyyyMMdd，如 "20260420"）
    final ValueChanged<DateTime> onDateSelected;

    /// 当前主页面显示的中心日期（用于初始化高亮）
    final DateTime initialFocusDate;

    const DatePickerDialog({
        super.key,
        required this.onDateSelected,
        required this.initialFocusDate,
    });

    @override
    State<DatePickerDialog> createState() => _DatePickerDialogState();
}

class _DatePickerDialogState extends State<DatePickerDialog> {
    late ScrollController _scrollController;
    late DateTime _today;
    late DateTime _focusDate;

    // 日历范围：从今天往前推 12 个月，往后推 3 个月
    late DateTime _calStart; // 日历第一行的周一
    late DateTime _calEnd;   // 日历最后一行的周日

    // 缓存每天的数据状态 0=无数据 1=有数据 2=完整 3=需注意（保留）
    final Map<String, int> _dayStatus = {};

    @override
    void initState() {
        super.initState();
        _today = _stripTime(DateTime.now());
        _focusDate = _stripTime(widget.initialFocusDate);
        _scrollController = ScrollController();

        _initCalendarRange();
        _loadDayStatuses();
    }

    DateTime _stripTime(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

    void _initCalendarRange() {
        // 从 12 个月前的第一天的所在周的周一开始
        DateTime rangeStart = DateTime(_today.year, _today.month - 12, 1);
        DateTime rangeEnd = DateTime(_today.year, _today.month + 3, 28); // 覆盖 +3 月

        // 对齐到周一
        int startWeekday = rangeStart.weekday; // 1=Mon
        _calStart = rangeStart.subtract(Duration(days: startWeekday - 1));

        // 对齐到周日
        int endWeekday = rangeEnd.weekday;
        _calEnd = rangeEnd.add(Duration(days: 7 - endWeekday));
    }

    Future<void> _loadDayStatuses() async {
        try {
            final box = Hive.box<DayEventsRecord>('dayRecords');

            final Map<String, int> statuses = {};
            for (final key in box.keys) {
                final record = box.get(key as String);
                if (record == null || record.events.isEmpty) {
                    statuses[key] = 0;
                    continue;
                }
                // 计算覆盖 block 数
                int covered = 0;
                for (final e in record.events) {
                    covered += (e.endIndex - e.startIndex + 1);
                }
                statuses[key] = covered >= 96 ? 2 : 1;
            }

            if (mounted) {
                setState(() {
                    _dayStatus.addAll(statuses);
                });
                // 滚动到 focusDate 对应的位置
                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToDate(_focusDate));
            }
        } catch (_) {}
    }

    void _scrollToDate(DateTime target) {
        // 计算 target 在第几行（周）
        int totalDays = target.difference(_calStart).inDays;
        int row = totalDays ~/ 7;
        // 每行高度约 44px，留一定顶部留白
        double targetOffset = row * 44.0 - 80;
        if (targetOffset < 0) targetOffset = 0;
        final maxExt = _scrollController.position.maxScrollExtent;
        if (targetOffset > maxExt) targetOffset = maxExt;
        _scrollController.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
        );
    }

    /// 获取某天的状态颜色
    Color _statusColor(DateTime date, bool isSelected) {
        final key = _dateKey(date);
        final isToday = date == _today;
        final isFuture = date.isAfter(_today);

        if (isSelected) return const Color(0xFFFFCA28); // 选中高亮：金黄

        final status = _dayStatus[key] ?? 0;
        if (isFuture) {
            // 未来：有数据用淡蓝色，无数据用深灰
            return status > 0 ? const Color(0xFF1E3A5F) : const Color(0xFF1A1A1A);
        }
        if (isToday) {
            return status >= 2
                ? const Color(0xFF1B5E20)   // 今天完整：深绿
                : status > 0
                    ? const Color(0xFF1565C0) // 今天有数据：深蓝
                    : const Color(0xFF3E2723); // 今天无数据：深红棕
        }
        // 过去
        switch (status) {
            case 2:  return const Color(0xFF2E7D32);   // 完整：绿
            case 1:  return const Color(0xFF1565C0);   // 有数据：蓝
            default: return const Color(0xFF111111);   // 无数据：黑
        }
    }

    String _dateKey(DateTime d) =>
        '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

    @override
    void dispose() {
        _scrollController.dispose();
        super.dispose();
    }

    @override
    Widget build(BuildContext context) {
        return Dialog(
            backgroundColor: const Color(0xFF0D0D0D),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: SizedBox(
                width: 340,
                height: 520,
                child: Column(
                    children: [
                        _buildHeader(),
                        const Divider(height: 1, color: Color(0xFF2A2A2A)),
                        _buildWeekdayRow(),
                        Expanded(child: _buildCalendar()),
                        const Divider(height: 1, color: Color(0xFF2A2A2A)),
                        _buildFooter(),
                    ],
                ),
            ),
        );
    }

    Widget _buildHeader() {
        return Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(
                children: [
                    const Icon(Icons.calendar_month, size: 16, color: Color(0xFF888888)),
                    const SizedBox(width: 8),
                    const Text(
                        '选择日期',
                        style: TextStyle(
                            color: Color(0xFFCCCCCC),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                        ),
                    ),
                    const Spacer(),
                    IconButton(
                        icon: const Icon(Icons.close, size: 16, color: Color(0xFF666666)),
                        onPressed: () => Navigator.of(context).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                ],
            ),
        );
    }

    Widget _buildWeekdayRow() {
        const labels = ['一', '二', '三', '四', '五', '六', '日'];
        return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
                children: labels.map((l) => Expanded(
                    child: Center(
                        child: Text(
                            l,
                            style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF555555),
                                fontWeight: FontWeight.w500,
                            ),
                        ),
                    ),
                )).toList(),
            ),
        );
    }

    Widget _buildCalendar() {
        // 生成所有周
        final List<Widget> rows = [];
        DateTime weekStart = _calStart;

        // 用于检测月份切换，显示月份标签
        int? lastMonth;

        while (!weekStart.isAfter(_calEnd)) {
            final DateTime ws = weekStart;
            final List<Widget> dayWidgets = [];
            String? monthLabel;

            for (int d = 0; d < 7; d++) {
                final day = ws.add(Duration(days: d));
                // 检测月份切换：这一周内第一次出现新月份（1日或者是首行）
                if (day.day == 1 || (d == 0 && lastMonth == null)) {
                    if (day.month != lastMonth) {
                        lastMonth = day.month;
                        monthLabel = '${day.month}月';
                    }
                }
                dayWidgets.add(_buildDayCell(day));
            }

            rows.add(
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                        children: [
                            // 月份标签区域（固定宽度）
                            SizedBox(
                                width: 28,
                                child: monthLabel != null
                                    ? Text(
                                        monthLabel,
                                        style: const TextStyle(
                                            fontSize: 9,
                                            color: Color(0xFF666666),
                                        ),
                                    )
                                    : null,
                            ),
                            // 7个色块
                            Expanded(
                                child: Row(
                                    children: dayWidgets,
                                ),
                            ),
                        ],
                    ),
                ),
            );

            weekStart = weekStart.add(const Duration(days: 7));
        }

        return ListView(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: rows,
        );
    }

    Widget _buildDayCell(DateTime date) {
        final isSelected = date == _focusDate;
        final isToday = date == _today;
        final bg = _statusColor(date, isSelected);

        return Expanded(
            child: GestureDetector(
                onTap: () {
                    setState(() => _focusDate = date);
                    widget.onDateSelected(date);
                    Navigator.of(context).pop();
                },
                child: Container(
                    height: 36,
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(4),
                        border: isToday
                            ? Border.all(color: const Color(0xFFFFCA28), width: 1.5)
                            : isSelected
                                ? Border.all(color: Colors.white, width: 1.5)
                                : null,
                    ),
                    child: Center(
                        child: Text(
                            '${date.day}',
                            style: TextStyle(
                                fontSize: 11,
                                color: isSelected
                                    ? Colors.black
                                    : isToday
                                        ? const Color(0xFFFFCA28)
                                        : const Color(0xFF999999),
                                fontWeight: (isToday || isSelected)
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                            ),
                        ),
                    ),
                ),
            ),
        );
    }

    Widget _buildFooter() {
        return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
                children: [
                    // 图例
                    _legend(const Color(0xFF2E7D32), '有完整数据'),
                    const SizedBox(width: 8),
                    _legend(const Color(0xFF1565C0), '有数据'),
                    const SizedBox(width: 8),
                    _legend(const Color(0xFF111111), '无数据'),
                    const Spacer(),
                    // 回到今天按钮
                    GestureDetector(
                        onTap: () {
                            setState(() => _focusDate = _today);
                            _scrollToDate(_today);
                            widget.onDateSelected(_today);
                            Navigator.of(context).pop();
                        },
                        child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                                color: const Color(0xFF1A1A1A),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: const Color(0xFFFFCA28), width: 1),
                            ),
                            child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                    Icon(Icons.today, size: 12, color: Color(0xFFFFCA28)),
                                    SizedBox(width: 4),
                                    Text(
                                        '今天',
                                        style: TextStyle(
                                            color: Color(0xFFFFCA28),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                        ),
                                    ),
                                ],
                            ),
                        ),
                    ),
                ],
            ),
        );
    }

    Widget _legend(Color color, String label) {
        return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
                Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                    ),
                ),
                const SizedBox(width: 3),
                Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF555555))),
            ],
        );
    }
}
