import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_block/loaders.dart';
import 'package:time_block/network/dataSync.dart';
import 'package:time_block/network/syncConfig.dart';
import 'package:time_block/view/datePickerDialog.dart' as datePicker;


class AppBarView extends StatefulWidget {
    OperationControl operationControl;
    UserProfileLoader userProfileLoader;
    /// 主页面的 ScrollController，选择日期后用于滚动到目标位置
    final ScrollController? scrollController;
    AppBarView({super.key, required this.operationControl, required this.userProfileLoader, this.scrollController});

    @override
    State<AppBarView> createState() => _AppBarViewState();
}


class _AppBarViewState extends State<AppBarView> {

    bool _isSyncing = false;

    @override
    void initState() {
        super.initState();
    }

    @override
    void dispose() {
        super.dispose();
    }

    /// 触发完整同步（使用新的多步握手协议）
    Future<void> _doSync(BuildContext context) async {
        // 检查服务端地址是否已配置
        final serverUrl = await SyncConfig.getServerUrl();
        if (serverUrl.isEmpty) {
            _showSnackBar(context, '请先在编辑页配置服务端地址', isError: true);
            return;
        }

        setState(() => _isSyncing = true);

        // 判断是否应该使用多步同步
        // 首次同步或本地无数据时，使用多步同步拉取全部历史
        final dataSync = DataSync();
        final shouldUseMultiStep = await dataSync.shouldUseMultiStepSync();

        SyncResult result;
        if (shouldUseMultiStep) {
          // 首次同步：使用多步协议，明确请求拉取全部历史数据
          print('== AppBarView._doSync: using multi-step sync (first time or no local data)');
          result = await dataSync.runMultiStepSync(wantFullData: true);
        } else {
          // 增量同步：使用多步协议
          print('== AppBarView._doSync: using multi-step sync (incremental)');
          result = await dataSync.runMultiStepSync(wantFullData: false);
        }

        if (!mounted) return;
        setState(() => _isSyncing = false);

        _showSnackBar(context, result.message, isError: !result.success);

        // 如果有补丁数据写入了本地，精确刷新这些日期的内存数据
        if (result.success && result.patchedDays > 0) {
            // applyPatchedDates 会从 Hive 重读数据并 notifyListeners，
            // 无论补丁日期是否在当前 renderDates 窗口内都能正确更新
            widget.userProfileLoader.applyPatchedDates(result.patchedDates);
        }

        // 如果 eventInfo 有更新，刷新内存中的 eventInfos 列表
        if (result.success && result.eventInfoUpdated) {
            await widget.userProfileLoader.applyServerEventInfo();
        }
    }

    void _showSnackBar(BuildContext context, String message, {bool isError = false}) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(message, style: const TextStyle(fontSize: 12)),
                backgroundColor: isError ? Colors.redAccent.shade700 : Colors.green.shade700,
                duration: Duration(seconds: isError ? 5 : 3),
                behavior: SnackBarBehavior.floating,
            ),
        );
    }

    /// 打开日期选择弹窗，选中后跳转
    Future<void> _openDatePicker(BuildContext context) async {
        // 当前 renderDates 的中间那天作为初始焦点
        final renderDates = widget.userProfileLoader.renderDates;
        DateTime initialFocus = DateTime.now();
        if (renderDates.isNotEmpty) {
            final mid = renderDates[renderDates.length ~/ 2];
            try {
                initialFocus = DateTime.parse(
                    '${mid.substring(0, 4)}-${mid.substring(4, 6)}-${mid.substring(6)}',
                );
            } catch (_) {}
        }

        await showDialog(
            context: context,
            builder: (_) => datePicker.DatePickerDialog(
                initialFocusDate: initialFocus,
                onDateSelected: (selectedDate) {
                    // 更新 renderDates，以选中日期为中心
                    widget.operationControl.jumpRenderDates(
                        widget.userProfileLoader, selectedDate);
                    // 滚动到中间（第 aroundDayCount 个日期 = index 3）
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                        final sc = widget.scrollController;
                        if (sc != null && sc.hasClients) {
                            const int centerIndex = 3;
                            double targetOffset = centerIndex * 630.0;
                            final maxExt = sc.position.maxScrollExtent;
                            if (targetOffset > maxExt) targetOffset = maxExt;
                            sc.animateTo(
                                targetOffset,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOut,
                            );
                        }
                    });
                },
            ),
        );
    }

    @override
    Widget build(BuildContext context) {
      final BorderRadius buttonBorderRadius = BorderRadius.circular(6.0);
      
      return Row(
        mainAxisAlignment : MainAxisAlignment.end,
        children: [
          // 选中色块的事件名称（按时间顺序，多类型用 · 分隔）
          Expanded(
            child: Text(
              Provider.of<OperationControl>(context, listen: true).selectedBlockEvent,
              style: const TextStyle(fontSize: 11, color: Colors.black87),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
          const SizedBox(width: 6),
          // ── 日期选择按钮 ──
          ElevatedButton(
            style: ButtonStyle(
                shape: MaterialStateProperty.all<RoundedRectangleBorder>(RoundedRectangleBorder(borderRadius: buttonBorderRadius)),
                backgroundColor: MaterialStateProperty.all(Colors.amber.shade700),
                textStyle: MaterialStateProperty.all(const TextStyle(color: Colors.black)),
                padding: MaterialStateProperty.all(const EdgeInsets.symmetric(horizontal: 8, vertical: 0)),
                minimumSize: MaterialStateProperty.all(const Size(32, 32)),
            ),
            onPressed: () => _openDatePicker(context),
            child: const Icon(Icons.calendar_today, size: 14, color: Colors.black),
          ),
          const Padding(padding: EdgeInsets.all(2.0)),
          // ── 刷新按钮 ──
          ElevatedButton(
            style: ButtonStyle(
                shape: MaterialStateProperty.all<RoundedRectangleBorder>(RoundedRectangleBorder(borderRadius: buttonBorderRadius)),
                backgroundColor: MaterialStateProperty.all(Colors.amber),
                textStyle: MaterialStateProperty.all(const TextStyle(color: Colors.black)),
            ),
            onPressed: () {
                setState(() {
                    print('Button 刷新 pressed');
                    Provider.of<OperationControl>(context, listen: false).refreshRenderDates(widget.userProfileLoader);
                    // 刷新后也滚回中间位置
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                        final sc = widget.scrollController;
                        if (sc != null && sc.hasClients) {
                            sc.animateTo(
                                3 * 630.0,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOut,
                            );
                        }
                    });
                });
            },
            child: const Text("刷新", style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.normal)),
          ),
          const Padding(padding: EdgeInsets.all(2.0)),
          ElevatedButton(
            style: ButtonStyle(
                shape: MaterialStateProperty.all<RoundedRectangleBorder>(RoundedRectangleBorder(borderRadius: buttonBorderRadius)),
                backgroundColor: MaterialStateProperty.all(
                    _isSyncing ? Colors.amber.shade200 : Colors.amber,
                ),
                textStyle: MaterialStateProperty.all(const TextStyle(color: Colors.black)),
            ),
            onPressed: _isSyncing ? null : () => _doSync(context),
            child: _isSyncing
                ? const SizedBox(
                    width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54),
                  )
                : const Text("同步", style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.normal)),
          )
        ]
      );
    }
}
