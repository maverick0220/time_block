import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:hive/hive.dart';
import 'package:time_block/database/DayEventsRecord.dart';
import 'package:time_block/database/EventInfoRecord.dart';
import 'package:time_block/database/EventRecord.dart';
import 'package:time_block/network/syncConfig.dart';

// ─────────────────────────────────────────────
// 数据结构
// ─────────────────────────────────────────────

/// 同步操作的结果
class SyncResult {
  final bool success;
  final String message;

  /// 本次上传的天数
  final int uploadedDays;

  /// 服务端回填的补丁天数
  final int patchedDays;

  /// 服务端回填的具体日期列表（用于调用方精确刷新内存中对应的 DayRecord）
  final List<String> patchedDates;

  /// 发生冲突的天数
  final int conflictDays;

  /// 服务端最新版本号（-1 表示未获取到）
  final int serverVersion;

  SyncResult({
    required this.success,
    required this.message,
    this.uploadedDays = 0,
    this.patchedDays = 0,
    this.patchedDates = const [],
    this.conflictDays = 0,
    this.serverVersion = -1,
  });

  @override
  String toString() =>
      'SyncResult(success: $success, message: $message, '
      'uploaded: $uploadedDays, patched: $patchedDays, conflicts: $conflictDays)';
}

// ─────────────────────────────────────────────
// DataSync
// ─────────────────────────────────────────────

/// 与服务端进行数据同步的 HTTP 客户端
class DataSync {
  DataSync();

  /// 获取服务端基础 URL（去掉末尾斜杠）
  Future<String> _getBaseUrl() async {
    final url = (await SyncConfig.getServerUrl()).trim();
    if (url.endsWith('/')) return url.substring(0, url.length - 1);
    return url;
  }

  // ─────────────────────────────────────────────
  // Ping
  // ─────────────────────────────────────────────

  /// 测试服务端是否可达（GET /ping）
  Future<bool> pingServer() async {
    final url = await _getBaseUrl();
    if (url.isEmpty) {
      print('== DataSync.pingServer: server URL is empty');
      return false;
    }
    try {
      final uri = Uri.parse('$url/ping');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      print('== DataSync.pingServer: status=${response.statusCode}, body=${response.body}');
      return response.statusCode == 200;
    } catch (e) {
      print('== DataSync.pingServer: error - $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────
  // 完整同步（上传增量 + 接收补丁）
  // ─────────────────────────────────────────────

  /// 执行一次完整的双向同步：
  ///   1. 确定上传范围（上次同步截止日期次日 → 今天）
  ///   2. 读取该范围内的 Hive dayRecords 并上传
  ///   3. 服务端返回补丁（在该范围内客户端缺失的天），写入本地 Hive
  ///   4. 同步成功后，更新 lastSyncEndDate = 今天
  ///
  /// [fallbackStartDate] 若从未同步过，默认从这个日期开始（格式 "YYYYMMDD"）
  Future<SyncResult> runFullSync({String? fallbackStartDate}) async {
    final url = await _getBaseUrl();
    if (url.isEmpty) {
      return SyncResult(success: false, message: '未配置服务端地址，请先在设置页填写服务端地址');
    }

    // 1. 计算上传范围
    // 若调用方没有传入 fallbackStartDate，且客户端从未同步过，
    // 则自动推算：取 Hive dayRecords 里最早有事件的日期；
    // 若 Hive 也是空的，则默认从当年 1 月 1 日起。
    // 这样可以确保多客户端场景下，从未同步的 B 能把服务端的历史数据全部拉回来。
    String? effectiveFallback = fallbackStartDate;
    if (effectiveFallback == null) {
      final lastSync = await SyncConfig.getLastSyncEndDate();
      if (lastSync == null) {
        // 从未同步过，找到本地最早的有效日期
        final dayRecordBox = Hive.box<DayEventsRecord>('dayRecords');
        final allKeys = dayRecordBox.keys.cast<String>().toList()..sort();
        final earliest = allKeys.firstWhere(
          (k) => (dayRecordBox.get(k)?.events.isNotEmpty ?? false),
          orElse: () => '',
        );
        if (earliest.isNotEmpty) {
          effectiveFallback = earliest;
        } else {
          // 本地也没有任何数据，从当年 1 月 1 日起，以便拉取服务端全部历史
          final year = DateTime.now().year;
          effectiveFallback = '${year}0101';
        }
        print('== DataSync.runFullSync: first sync, fallback start = $effectiveFallback');
      }
    }

    final range = await SyncConfig.calcUploadRange(fallbackStartDate: effectiveFallback);
    // calcUploadRange 新逻辑始终返回包含今天的范围，不再返回 null
    if (range == null) {
      return SyncResult(success: true, message: '已是最新，无需同步', uploadedDays: 0);
    }
    final rangeStart = range[0];
    final rangeEnd   = range[1];
    print('== DataSync.runFullSync: upload range $rangeStart ~ $rangeEnd');

    try {
      // 2. 读取该范围内的 dayRecords
      final dayRecordBox = Hive.box<DayEventsRecord>('dayRecords');
      final Map<String, List<List<dynamic>>> dayRecordsMap = {};

      final allDatesInRange = _enumerateDates(rangeStart, rangeEnd);
      for (final dateKey in allDatesInRange) {
        final record = dayRecordBox.get(dateKey);
        if (record != null && record.events.isNotEmpty) {
          dayRecordsMap[dateKey] = record.exportRecordAsJson_onlyEvents();
        }
        // 空的也要上传（服务端据此判断该日期客户端"有记录但空白"vs"根本没这个日期"）
        // 若该日期 Hive 中根本不存在，不放入 map，服务端会知道客户端这天是空缺
      }

      // 3. 读取 eventInfo（每次同步都带上，保持服务端最新）
      final eventInfoBox = Hive.box<EventInfoRecord>('eventInfo');
      final List<Map<String, dynamic>> eventInfoList = [];
      for (var key in eventInfoBox.keys) {
        final rec = eventInfoBox.get(key);
        if (rec != null) {
          eventInfoList.add({
            'name': rec.eventName,
            'color': {'r': rec.color_rgb[0], 'g': rec.color_rgb[1], 'b': rec.color_rgb[2]},
            'belongingTo': rec.belongingToEvent,
          });
        }
      }

      // 4. 构造请求体
      final payload = {
        'eventInfo': eventInfoList,
        'dayRecords': dayRecordsMap,
        'uploadRange': [rangeStart, rangeEnd],
        'clientTime': DateTime.now().toIso8601String(),
        'clientId': 'flutter-client',
      };

      print('== DataSync.runFullSync: uploading ${dayRecordsMap.length} days to $url');

      // 5. 发送请求
      final uri = Uri.parse('$url/sync');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        return SyncResult(
          success: false,
          message: '服务端返回错误: ${response.statusCode}',
        );
      }

      // 6. 解析响应
      final result = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final patch = result['patch'] as Map<String, dynamic>? ?? {};
      final conflictDays = (result['conflictDays'] as num?)?.toInt() ?? 0;
      final serverVersion = (result['newVersion'] as num?)?.toInt() ?? -1;

      print('== DataSync.runFullSync: server response: ${result['message']}');
      print('== DataSync.runFullSync: patch days = ${patch.length}, conflicts = $conflictDays');

      // 7. 将补丁写入本地 Hive
      int patchedCount = 0;
      final List<String> patchedDatesList = [];
      for (final dateKey in patch.keys) {
        final rawEvents = patch[dateKey] as List<dynamic>;
        final List<EventRecord> eventRecords = _parseEventRecords(rawEvents);
        await dayRecordBox.put(dateKey, DayEventsRecord(date: dateKey, events: eventRecords));
        patchedCount++;
        patchedDatesList.add(dateKey);
        print('== DataSync.runFullSync: patched $dateKey (${eventRecords.length} events)');
      }

      // 8. 同步成功，更新 lastSyncEndDate 和时间戳
      await SyncConfig.setLastSyncEndDate(rangeEnd);
      await SyncConfig.setLastSyncTimestamp();

      // 9. 组装结果消息
      String msg = result['message']?.toString() ?? '同步完成';
      if (patchedCount > 0) {
        msg += '，本地补全 $patchedCount 天';
      }
      if (conflictDays > 0) {
        msg += '（$conflictDays 天数据有冲突，已存入服务端冲突库）';
      }

      return SyncResult(
        success: true,
        message: msg,
        uploadedDays: dayRecordsMap.length,
        patchedDays: patchedCount,
        patchedDates: patchedDatesList,
        conflictDays: conflictDays,
        serverVersion: serverVersion,
      );
    } catch (e) {
      print('== DataSync.runFullSync: error - $e');
      return SyncResult(success: false, message: '同步失败: $e');
    }
  }

  // ─────────────────────────────────────────────
  // 工具方法
  // ─────────────────────────────────────────────

  /// 枚举从 startDate 到 endDate（含）之间的所有日期字符串（"YYYYMMDD" 格式）
  List<String> _enumerateDates(String startStr, String endStr) {
    final start = _parseDate(startStr);
    final end   = _parseDate(endStr);
    if (start == null || end == null) return [];

    final List<String> dates = [];
    DateTime cur = start;
    while (!cur.isAfter(end)) {
      dates.add(_formatDate(cur));
      cur = cur.add(const Duration(days: 1));
    }
    return dates;
  }

  String _formatDate(DateTime dt) =>
      '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}';

  DateTime? _parseDate(String s) {
    if (s.length != 8) return null;
    try {
      return DateTime(int.parse(s.substring(0, 4)), int.parse(s.substring(4, 6)), int.parse(s.substring(6, 8)));
    } catch (_) {
      return null;
    }
  }

  /// 将服务端返回的 JSON 事件数组解析为 EventRecord 列表
  List<EventRecord> _parseEventRecords(List<dynamic> rawEvents) {
    return rawEvents.map((e) {
      final row = e as List<dynamic>;
      return EventRecord(
        startIndex: (row[0] as num).toInt(),
        endIndex: (row[1] as num).toInt(),
        eventInfo: row[2] as String,
      )
        ..type    = (row.length > 3 ? row[3] : '') as String
        ..comment = (row.length > 4 ? row[4] : '') as String;
    }).toList();
  }

  // ─────────────────────────────────────────────
  // 兼容旧接口（供 editPage.dart 的"上传数据"按钮保留使用）
  // ─────────────────────────────────────────────

  /// 向后兼容：仅执行上传（内部调用 runFullSync）
  Future<SyncResult> runUploadTask() => runFullSync();
}
