import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:time_block/dataStructure.dart';
import 'package:time_block/database/DayEventsRecord.dart';
import 'package:time_block/loaders.dart';
import 'package:time_block/view/appBarViiew.dart';
import 'package:time_block/view/eventInfoEditView.dart';
import 'package:time_block/view/eventInfoDialog.dart';
import 'package:time_block/network/syncConfig.dart';
import 'package:time_block/network/dataSync.dart';
import 'package:time_block/database/EventInfoRecord.dart';


class EditPage extends StatefulWidget {
    const EditPage({super.key, required this.title});
    final String title;
    @override
    State<EditPage> createState() => _EditPageState();
}


class _EditPageState extends State<EditPage> {

    // -------- 服务端配置 --------
    late TextEditingController _serverUrlController;
    String _syncStatusMessage = '';
    bool _isSyncing = false;
    bool? _lastPingResult; // null=未测试, true=通, false=不通

    @override
    void initState() {
        super.initState();
        _serverUrlController = TextEditingController();
        _loadServerUrl();
    }

    Future<void> _loadServerUrl() async {
        final url = await SyncConfig.getServerUrl();
        if (mounted) {
            setState(() {
                _serverUrlController.text = url;
            });
        }
    }

    @override
    void dispose() {
        _serverUrlController.dispose();
        super.dispose();
    }

    /// 保存地址并验证连通性
    Future<void> _saveAndVerifyUrl(String newUrl) async {
        await SyncConfig.setServerUrl(newUrl);
        if (newUrl.trim().isEmpty) {
            setState(() {
                _lastPingResult = null;
                _syncStatusMessage = '';
            });
            return;
        }
        setState(() {
            _lastPingResult = null;
            _syncStatusMessage = '验证中…';
        });
        final ok = await DataSync().pingServer();
        setState(() {
            _lastPingResult = ok;
            _syncStatusMessage = ok ? '服务端连接正常 ✓' : '无法连接服务端，请检查地址或确认服务端已启动';
        });
    }

    /// 触发完整同步（使用多步握手协议）
    Future<void> _doUpload(UserProfileLoader userProfileLoader) async {
        setState(() { _isSyncing = true; _syncStatusMessage = '正在同步数据…'; });

        final dataSync = DataSync();
        final shouldUseMultiStep = await dataSync.shouldUseMultiStepSync();

        SyncResult result;
        if (shouldUseMultiStep) {
          result = await dataSync.runMultiStepSync(wantFullData: true);
        } else {
          result = await dataSync.runMultiStepSync(wantFullData: false);
        }

        // 同步后刷新补丁数据
        if (result.success && result.patchedDays > 0) {
            userProfileLoader.applyPatchedDates(result.patchedDates);
        }
        // 同步后刷新 eventInfo 配置
        if (result.success && result.eventInfoUpdated) {
            await userProfileLoader.applyServerEventInfo();
        }

        setState(() {
            _isSyncing = false;
            _syncStatusMessage = result.message;
        });
    }

    @override
    Widget build(BuildContext context) {
        var operationControl = Provider.of<OperationControl>(context);
        var userProfileLoader = Provider.of<UserProfileLoader>(context);
        List<EventInfo> eventInfos = userProfileLoader.eventInfos;

        final BorderRadius buttonBorderRadius = BorderRadius.circular(6.0);
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        return Scaffold(
            appBar: AppBar(
                backgroundColor: theme.colorScheme.background,
                title: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                        ElevatedButton(
                            style: ButtonStyle(
                                shape: MaterialStateProperty.all<RoundedRectangleBorder>(RoundedRectangleBorder(borderRadius: buttonBorderRadius)),
                                backgroundColor: MaterialStateProperty.all(const Color.fromARGB(255, 90, 187, 26)),
                                textStyle: MaterialStateProperty.all(const TextStyle(color: Colors.black)),
                            ),
                            onPressed: () => _showAddEventInfoDialog(context, userProfileLoader, operationControl),
                            child: const Text("新增", style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.normal)),
                        ),
                        const Padding(padding: EdgeInsets.all(2.0)),
                        /* 查找按钮功能 - 暂未实现 */
                        ElevatedButton(
                            style: ButtonStyle(
                                shape: MaterialStateProperty.all<RoundedRectangleBorder>(RoundedRectangleBorder(borderRadius: buttonBorderRadius)),
                                backgroundColor: MaterialStateProperty.all(const Color.fromARGB(255, 90, 187, 26)),
                                textStyle: MaterialStateProperty.all(const TextStyle(color: Colors.black)),
                            ),
                            onPressed: () {
                                setState(() {
                                    print('Button 查找eventInfo pressed');
                                });
                            },
                            child: const Text("查找", style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.normal)),
                        )
                    ]
                )
            ),
            body: Row(
              children: [
                Expanded(child: SingleChildScrollView(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                            // -------- 事件类型列表（支持拖动排序） --------
                            ReorderableListView(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                onReorder: (oldIndex, newIndex) {
                                    userProfileLoader.reorderEventInfos(oldIndex, newIndex);
                                },
                                children: List.generate(
                                    eventInfos.length,
                                    (i) => EventInfoEditView(
                                        key: ValueKey(eventInfos[i].name),
                                        eventInfo: eventInfos[i],
                                        userProfileLoader: userProfileLoader,
                                        onEditPressed: (eventInfo) => _showEditEventInfoDialog(context, userProfileLoader, operationControl, eventInfo),
                                    ),
                                ),
                            ),

                            const SizedBox(height: 16),

                            // -------- 数据同步配置卡片 --------
                            _buildSyncConfigCard(isDark, userProfileLoader),

                            const SizedBox(height: 24),
                        ]
                    )
                )),
                const Padding(padding: EdgeInsets.all(2.0)),
              ],
            )
        );
    }

    Widget _buildSyncConfigCard(bool isDark, UserProfileLoader userProfileLoader) {
        final cardColor = isDark
            ? const Color.fromARGB(255, 35, 35, 40)
            : const Color.fromARGB(255, 245, 245, 250);
        final labelColor = isDark ? Colors.white70 : Colors.black87;
        final hintColor = isDark ? Colors.white38 : Colors.black38;
        final borderColor = isDark ? Colors.white24 : Colors.black26;

        // 连接状态指示颜色
        Color statusColor = Colors.grey;
        if (_lastPingResult == true) statusColor = Colors.greenAccent;
        if (_lastPingResult == false) statusColor = Colors.redAccent;

        return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Container(
                decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: borderColor, width: 1),
                ),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        // 标题行
                        Row(
                            children: [
                                Icon(Icons.cloud_sync_outlined, size: 16, color: labelColor),
                                const SizedBox(width: 6),
                                Text(
                                    '数据备份 / 同步',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: labelColor,
                                    ),
                                ),
                            ],
                        ),
                        const SizedBox(height: 10),

                        // 地址输入框
                        Text(
                            '服务端地址',
                            style: TextStyle(fontSize: 11, color: hintColor),
                        ),
                        const SizedBox(height: 4),
                        TextField(
                            controller: _serverUrlController,
                            style: TextStyle(fontSize: 13, color: labelColor),
                            decoration: InputDecoration(
                                hintText: '例：http://127.0.0.1:5001',
                                hintStyle: TextStyle(fontSize: 12, color: hintColor),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(color: borderColor),
                                ),
                                // 右侧连接状态指示点
                                suffixIcon: _lastPingResult == null
                                    ? null
                                    : Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: Icon(
                                            _lastPingResult! ? Icons.check_circle_outline : Icons.error_outline,
                                            size: 18,
                                            color: statusColor,
                                        ),
                                      ),
                            ),
                            onSubmitted: (val) => _saveAndVerifyUrl(val),
                            onEditingComplete: () {
                                _saveAndVerifyUrl(_serverUrlController.text);
                                FocusScope.of(context).unfocus();
                            },
                        ),

                        const SizedBox(height: 8),

                        // 状态消息
                        if (_syncStatusMessage.isNotEmpty)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                    _syncStatusMessage,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: _lastPingResult == false
                                            ? Colors.redAccent
                                            : (_isSyncing ? Colors.blueAccent : Colors.greenAccent),
                                    ),
                                ),
                            ),

                        // 操作按钮行
                        Row(
                            children: [
                                // 验证连接
                                Expanded(
                                    child: OutlinedButton.icon(
                                        icon: const Icon(Icons.wifi_tethering, size: 14),
                                        label: const Text('验证连接', style: TextStyle(fontSize: 12)),
                                        style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(vertical: 6),
                                            side: BorderSide(color: borderColor),
                                            foregroundColor: labelColor,
                                        ),
                                        onPressed: () => _saveAndVerifyUrl(_serverUrlController.text),
                                    ),
                                ),
                                const SizedBox(width: 8),
                                // 上传数据
                                Expanded(
                                    child: ElevatedButton.icon(
                                        icon: _isSyncing
                                            ? const SizedBox(
                                                width: 12,
                                                height: 12,
                                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                              )
                                            : const Icon(Icons.sync, size: 14),
                                        label: Text(
                                            _isSyncing ? '同步中…' : '立即同步',
                                            style: const TextStyle(fontSize: 12),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(vertical: 6),
                                            backgroundColor: const Color.fromARGB(255, 60, 130, 220),
                                            foregroundColor: Colors.white,
                                        ),
                                        onPressed: _isSyncing ? null : () => _doUpload(userProfileLoader),
                                    ),
                                ),
                            ],
                        ),
                    ],
                ),
            ),
        );
    }
    // ─────────────────────────────────────────────
    // EventInfo 编辑和新增
    // ─────────────────────────────────────────────

    /// 显示新增 EventInfo 弹窗
    Future<void> _showAddEventInfoDialog(BuildContext context, UserProfileLoader userProfileLoader, OperationControl operationControl) async {
        final result = await showEventInfoDialog(context);
        if (result == null) return; // 用户取消

        await _saveEventInfo(
            context,
            userProfileLoader,
            operationControl,
            result['name'] as String,
            result['color'] as List<int>,
            null, // 新增时没有旧名称
        );
    }

    /// 显示编辑 EventInfo 弹窗
    Future<void> _showEditEventInfoDialog(
        BuildContext context,
        UserProfileLoader userProfileLoader,
        OperationControl operationControl,
        EventInfo eventInfo,
    ) async {
        final result = await showEventInfoDialog(
            context,
            initialName: eventInfo.name,
            initialColor: [
                eventInfo.color.red,
                eventInfo.color.green,
                eventInfo.color.blue,
            ],
        );
        if (result == null) return; // 用户取消

        await _saveEventInfo(
            context,
            userProfileLoader,
            operationControl,
            result['name'] as String,
            result['color'] as List<int>,
            eventInfo.name, // 旧名称
        );
    }

    /// 保存 EventInfo 到 Hive
    Future<void> _saveEventInfo(
        BuildContext context,
        UserProfileLoader userProfileLoader,
        OperationControl operationControl,
        String name,
        List<int> colorRgb,
        String? oldName,
    ) async {
        try {
            // 使用 Hive.box() 获取已打开的 Box，而不是 openBox()
            final eventInfoBox = Hive.box<EventInfoRecord>('eventInfo');

            // 如果是编辑模式且名称改变，需要删除旧的记录
            if (oldName != null && oldName != name) {
                await eventInfoBox.delete(oldName);
                
                // 更新所有使用旧名称的事件
                final dayRecordBox = Hive.box<DayEventsRecord>('dayRecords');
                for (final key in dayRecordBox.keys) {
                    final record = dayRecordBox.get(key);
                    if (record != null) {
                        bool modified = false;
                        for (final event in record.events) {
                            if (event.eventInfo == oldName) {
                                event.eventInfo = name;
                                modified = true;
                            }
                        }
                        if (modified) {
                            await dayRecordBox.put(key, record);
                        }
                    }
                }
            }

            // 保存新的 EventInfoRecord
            final newRecord = EventInfoRecord(
                eventName: name,
                color_rgb: colorRgb,
                belongingToEvent: '',
            );
            await eventInfoBox.put(name, newRecord);

            // 刷新本地缓存（保持现有排序，新增条目追加末尾）
            final Map<String, EventInfo> infoMap = {};
            for (final key in eventInfoBox.keys) {
                final rec = eventInfoBox.get(key);
                if (rec != null) {
                    infoMap[rec.eventName] = EventInfo(rec.eventName, rec.color_rgb);
                }
            }
            // 在已有排序基础上更新（名称改变时用新名替换旧位置）
            final updatedList = <EventInfo>[];
            for (final existing in userProfileLoader.eventInfos) {
                final existingName = (oldName != null && existing.name == oldName) ? name : existing.name;
                if (infoMap.containsKey(existingName)) {
                    updatedList.add(infoMap[existingName]!);
                    infoMap.remove(existingName);
                }
            }
            // 新增条目追加到末尾
            updatedList.addAll(infoMap.values);
            userProfileLoader.eventInfos
                ..clear()
                ..addAll(updatedList);
            // 持久化新顺序
            await SyncConfig.setEventInfoOrder(userProfileLoader.eventInfos.map((e) => e.name).toList());

            // 刷新所有已加载的 dayRecords（因为颜色可能改变）
            operationControl.refreshRenderDates(userProfileLoader);

            if (context.mounted) {
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(oldName == null ? '事件类型已添加' : '事件类型已更新'),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 2),
                    ),
                );
            }
        } catch (e) {
            print('== Error saving eventInfo: $e');
            if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('保存失败: $e'),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 3),
                    ),
                );
            }
        }
    }
}

