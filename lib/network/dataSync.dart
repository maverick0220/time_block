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

  /// 是否是新协议多步同步
  final bool multiStepSync;

  /// 是否有 eventInfo 更新（下载后写入了新的事件类型配置）
  final bool eventInfoUpdated;

  SyncResult({
    required this.success,
    required this.message,
    this.uploadedDays = 0,
    this.patchedDays = 0,
    this.patchedDates = const [],
    this.conflictDays = 0,
    this.serverVersion = -1,
    this.multiStepSync = false,
    this.eventInfoUpdated = false,
  });

  @override
  String toString() =>
      'SyncResult(success: $success, message: $message, '
      'uploaded: $uploadedDays, patched: $patchedDays, conflicts: $conflictDays)';
}

/// 握手响应
class HandshakeInfo {
  final bool success;
  final String status;
  final String protocolVersion;
  final int currentVersion;
  final String? earliestDate;
  final String? latestDate;
  final Map<String, dynamic> features;

  HandshakeInfo({
    required this.success,
    required this.status,
    required this.protocolVersion,
    required this.currentVersion,
    this.earliestDate,
    this.latestDate,
    required this.features,
  });

  factory HandshakeInfo.fromJson(Map<String, dynamic> json) {
    final dataRange = json['dataRange'] as Map<String, dynamic>? ?? {};
    return HandshakeInfo(
      success: json['status'] == 'ok',
      status: json['status'] ?? '',
      protocolVersion: json['protocolVersion'] ?? '1.0',
      currentVersion: (json['currentVersion'] as num?)?.toInt() ?? 0,
      earliestDate: dataRange['earliest'] as String?,
      latestDate: dataRange['latest'] as String?,
      features: json['features'] as Map<String, dynamic>? ?? {},
    );
  }
}

/// 协商响应
class NegotiateResult {
  final bool success;
  final bool uploadRequired;
  final bool downloadRequired;
  final String uploadRangeStart;
  final String uploadRangeEnd;
  final String downloadRangeStart;
  final String downloadRangeEnd;
  final List<String> serverHasDates;
  final bool eventInfoChanged;
  final int newVersion;

  NegotiateResult({
    required this.success,
    required this.uploadRequired,
    required this.downloadRequired,
    required this.uploadRangeStart,
    required this.uploadRangeEnd,
    required this.downloadRangeStart,
    required this.downloadRangeEnd,
    required this.serverHasDates,
    required this.eventInfoChanged,
    required this.newVersion,
  });

  factory NegotiateResult.fromJson(Map<String, dynamic> json) {
    final uploadRange = json['uploadRange'] as List<dynamic>? ?? [];
    final downloadRange = json['downloadRange'] as List<dynamic>? ?? [];
    return NegotiateResult(
      success: true,
      uploadRequired: json['uploadRequired'] as bool? ?? false,
      downloadRequired: json['downloadRequired'] as bool? ?? false,
      uploadRangeStart: uploadRange.length >= 2 ? uploadRange[0] as String : '',
      uploadRangeEnd: uploadRange.length >= 2 ? uploadRange[1] as String : '',
      downloadRangeStart: downloadRange.length >= 2 ? downloadRange[0] as String : '',
      downloadRangeEnd: downloadRange.length >= 2 ? downloadRange[1] as String : '',
      serverHasDates: (json['serverHasDates'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      eventInfoChanged: json['eventInfoChanged'] as bool? ?? false,
      newVersion: (json['newVersion'] as num?)?.toInt() ?? 0,
    );
  }
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
  // 多步同步协议 v2.0
  // ─────────────────────────────────────────────

  /// 步骤1：握手。获取服务端状态和能力。
  Future<HandshakeInfo?> handshake() async {
    final url = await _getBaseUrl();
    if (url.isEmpty) {
      print('== DataSync.handshake: server URL is empty');
      return null;
    }
    try {
      final uri = Uri.parse('$url/handshake');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        print('== DataSync.handshake: status=${response.statusCode}');
        return null;
      }
      final result = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      print('== DataSync.handshake: ${result}');
      return HandshakeInfo.fromJson(result);
    } catch (e) {
      print('== DataSync.handshake: error - $e');
      return null;
    }
  }

  /// 步骤2：协商。客户端声明需求，服务端返回同步计划。
  Future<NegotiateResult?> _negotiate({
    required String clientId,
    required String? lastSyncDate,
    required bool wantFullData,
    required List<String> clientDates,
    required List<Map<String, dynamic>> eventInfoList,
  }) async {
    final url = await _getBaseUrl();
    if (url.isEmpty) return null;

    try {
      final payload = {
        'clientId': clientId,
        'lastSyncDate': lastSyncDate ?? '',
        'wantFullData': wantFullData,
        'clientDates': clientDates,
        'clientEventInfo': eventInfoList,
      };

      final uri = Uri.parse('$url/handshake/negotiate');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        print('== DataSync._negotiate: status=${response.statusCode}');
        return null;
      }

      final result = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      print('== DataSync._negotiate: $result');
      return NegotiateResult.fromJson(result);
    } catch (e) {
      print('== DataSync._negotiate: error - $e');
      return null;
    }
  }

  /// 步骤3：上传数据到服务端。
  Future<Map<String, dynamic>?> _uploadDayRecords({
    required String clientId,
    required String uploadRangeStart,
    required String uploadRangeEnd,
    required Map<String, List<List<dynamic>>> dayRecords,
    required List<Map<String, dynamic>> eventInfoList,
  }) async {
    final url = await _getBaseUrl();
    if (url.isEmpty) return null;

    try {
      final payload = {
        'clientId': clientId,
        'clientTime': DateTime.now().toIso8601String(),
        'uploadRange': [uploadRangeStart, uploadRangeEnd],
        'dayRecords': dayRecords,
        'eventInfo': eventInfoList,
      };

      print('== DataSync._uploadDayRecords: uploading ${dayRecords.length} days');

      final uri = Uri.parse('$url/sync/upload');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        print('== DataSync._uploadDayRecords: status=${response.statusCode}');
        return null;
      }

      final result = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      print('== DataSync._uploadDayRecords: ${result['message']}');
      return result;
    } catch (e) {
      print('== DataSync._uploadDayRecords: error - $e');
      return null;
    }
  }

  /// 步骤4：从服务端下载数据。
  Future<Map<String, dynamic>?> _downloadDayRecords({
    required String rangeStart,
    required String rangeEnd,
  }) async {
    final url = await _getBaseUrl();
    if (url.isEmpty) return null;

    try {
      print('== DataSync._downloadDayRecords: downloading $rangeStart~$rangeEnd');

      final uri = Uri.parse('$url/sync/download').replace(queryParameters: {
        'range_start': rangeStart,
        'range_end': rangeEnd,
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 120));

      if (response.statusCode != 200) {
        print('== DataSync._downloadDayRecords: status=${response.statusCode}');
        return null;
      }

      final result = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      print('== DataSync._downloadDayRecords: ${result['message']}, dates=${result['dateCount']}');
      return result;
    } catch (e) {
      print('== DataSync._downloadDayRecords: error - $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────
  // 完整同步（新版：多步握手 + 协商 + 分步交换）
  // ─────────────────────────────────────────────

  /// 执行一次完整的多步双向同步（协议 v2.0）：
  ///
  /// 步骤1：握手 → 获取服务端能力
  /// 步骤2：协商 → 双方互换信息，确定上传/下载范围
  /// 步骤3：上传 → 客户端上传增量数据（如需要）
  /// 步骤4：下载 → 客户端获取缺失数据（如需要）
  ///
  /// [wantFullData] 是否想拉取服务端全部历史数据（首次同步或数据不一致时建议设为 true）
  ///
  /// 返回值中 [SyncResult.patchedDates] 包含本次同步更新的日期列表，
  /// 调用方应调用 [UserProfileLoader.applyPatchedDates] 刷新内存中对应的 DayRecord；
  /// 若 [SyncResult.eventInfoUpdated] 为 true，还应调用
  /// [UserProfileLoader.applyServerEventInfo] 更新 eventInfo。
  Future<SyncResult> runMultiStepSync({bool wantFullData = false}) async {
    final url = await _getBaseUrl();
    if (url.isEmpty) {
      return SyncResult(success: false, message: '未配置服务端地址，请先在设置页填写服务端地址');
    }

    print('== DataSync.runMultiStepSync: starting multi-step sync, wantFullData=$wantFullData');

    // 获取设备唯一标识
    final clientId = await SyncConfig.getClientId();

    // 步骤1：握手
    print('== DataSync.runMultiStepSync: step 1 - handshake');
    final handshakeInfo = await handshake();
    if (handshakeInfo == null || !handshakeInfo.success) {
      // 握手失败可能是服务端为旧版（无 /handshake 路由），降级到旧协议
      print('== DataSync.runMultiStepSync: handshake failed, falling back to legacy /sync protocol');
      return runFullSync();
    }

    // 获取本地日期列表和 eventInfo（含顺序）
    final dayRecordBox = Hive.box<DayEventsRecord>('dayRecords');
    final eventInfoBox = Hive.box<EventInfoRecord>('eventInfo');
    final clientDates = dayRecordBox.keys.cast<String>().toList();
    final savedOrder = await SyncConfig.getEventInfoOrder();
    final eventInfoList = _buildEventInfoList(eventInfoBox, orderedNames: savedOrder);

    // 步骤2：协商
    print('== DataSync.runMultiStepSync: step 2 - negotiate');
    final negotiateResult = await _negotiate(
      clientId: clientId,
      lastSyncDate: await SyncConfig.getLastSyncEndDate(),
      wantFullData: wantFullData,
      clientDates: clientDates,
      eventInfoList: eventInfoList,
    );
    if (negotiateResult == null) {
      return SyncResult(success: false, message: '协商失败');
    }

    String msg = '';
    int totalUploaded = 0;
    int totalPatched = 0;
    int totalConflicts = 0;
    final List<String> allPatchedDates = [];
    bool eventInfoUpdated = false;

    // 步骤3：上传（如需要）
    if (negotiateResult.uploadRequired) {
      print('== DataSync.runMultiStepSync: step 3 - upload');

      // 读取 uploadRange 内的 dayRecords
      final dayRecordsMap = _readDayRecordsInRange(
        dayRecordBox,
        negotiateResult.uploadRangeStart,
        negotiateResult.uploadRangeEnd,
      );

      final uploadResult = await _uploadDayRecords(
        clientId: clientId,
        uploadRangeStart: negotiateResult.uploadRangeStart,
        uploadRangeEnd: negotiateResult.uploadRangeEnd,
        dayRecords: dayRecordsMap,
        eventInfoList: eventInfoList,
      );

      if (uploadResult == null) {
        return SyncResult(success: false, message: '上传失败');
      }

      totalUploaded = uploadResult['mergedDays'] as int? ?? 0;
      totalConflicts = uploadResult['conflictDays'] as int? ?? 0;
      msg += '上传 ${totalUploaded} 天';
      if (totalConflicts > 0) {
        msg += '（$totalConflicts 天冲突）';
      }
    }

    // 步骤4：下载（如需要）
    if (negotiateResult.downloadRequired) {
      print('== DataSync.runMultiStepSync: step 4 - download');

      final downloadResult = await _downloadDayRecords(
        rangeStart: negotiateResult.downloadRangeStart,
        rangeEnd: negotiateResult.downloadRangeEnd,
      );

      if (downloadResult == null) {
        return SyncResult(
          success: totalUploaded > 0,
          message: totalUploaded > 0 ? '下载失败，但上传成功' : '下载失败',
          uploadedDays: totalUploaded,
          conflictDays: totalConflicts,
          serverVersion: negotiateResult.newVersion,
          multiStepSync: true,
        );
      }

      // 将下载的 dayRecords 写入本地 Hive
      final dayRecords = downloadResult['dayRecords'] as Map<String, dynamic>? ?? {};
      for (final dateKey in dayRecords.keys) {
        final rawEvents = dayRecords[dateKey] as List<dynamic>;
        final List<EventRecord> eventRecords = _parseEventRecords(rawEvents);
        await dayRecordBox.put(dateKey, DayEventsRecord(date: dateKey, events: eventRecords));
        allPatchedDates.add(dateKey);
        totalPatched++;
      }

      if (totalPatched > 0) {
        if (msg.isNotEmpty) msg += '，';
        msg += '下载补全 $totalPatched 天';
      }

      // ── 同步 eventInfo（如果服务端有更新的配置）────────────────
      final serverEventInfo = downloadResult['eventInfo'] as List<dynamic>? ?? [];
      if (serverEventInfo.isNotEmpty) {
        final applied = await _applyServerEventInfo(
          serverEventInfo,
          eventInfoBox,
        );
        if (applied) {
          eventInfoUpdated = true;
          print('== DataSync.runMultiStepSync: eventInfo applied from server');
          if (msg.isNotEmpty) msg += '，';
          msg += '配置已更新';
        }
      }
    }

    // 同步成功，更新 lastSyncEndDate
    final today = _formatDate(DateTime.now());
    await SyncConfig.setLastSyncEndDate(today);
    await SyncConfig.setLastSyncTimestamp();

    if (msg.isEmpty) {
      msg = '已是最新，无需同步';
    }

    print('== DataSync.runMultiStepSync: completed - $msg');

    return SyncResult(
      success: true,
      message: msg,
      uploadedDays: totalUploaded,
      patchedDays: totalPatched,
      patchedDates: allPatchedDates,
      conflictDays: totalConflicts,
      serverVersion: negotiateResult.newVersion,
      multiStepSync: true,
      eventInfoUpdated: eventInfoUpdated,
    );
  }

  // ─────────────────────────────────────────────
  // 兼容旧接口（单次同步，仍保留用于兼容）
  // ─────────────────────────────────────────────

  /// 执行一次完整的双向同步（旧协议，单次请求完成）：
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
      final savedOrder = await SyncConfig.getEventInfoOrder();
      final eventInfoList = _buildEventInfoList(eventInfoBox, orderedNames: savedOrder);

      // 4. 构造请求体
      final clientId = await SyncConfig.getClientId();
      final payload = {
        'eventInfo': eventInfoList,
        'dayRecords': dayRecordsMap,
        'uploadRange': [rangeStart, rangeEnd],
        'clientTime': DateTime.now().toIso8601String(),
        'clientId': clientId,
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

  /// 将服务端返回的 eventInfo 列表写入本地 Hive，并更新 eventInfoOrder。
  ///
  /// 合并规则（配置层面）：
  ///   - 服务端有、本地没有 → 添加
  ///   - 服务端有、本地也有 → 以服务端为准更新颜色/所属
  ///   - 本地有、服务端没有 → **保留**（本地独有不删除）
  ///   - 顺序：以服务端下发的 sortOrder 为准；本地独有条目追加到末尾
  ///
  /// 返回 true 表示有变化（调用方需刷新 UI）。
  Future<bool> _applyServerEventInfo(
    List<dynamic> serverEventInfoRaw,
    Box<EventInfoRecord> eventInfoBox,
  ) async {
    bool changed = false;

    // 解析服务端列表，按 sortOrder 排序
    final List<Map<String, dynamic>> serverList = serverEventInfoRaw
        .whereType<Map<String, dynamic>>()
        .toList();
    serverList.sort((a, b) {
      final oa = (a['sortOrder'] as num?)?.toInt() ?? 999;
      final ob = (b['sortOrder'] as num?)?.toInt() ?? 999;
      return oa.compareTo(ob);
    });

    for (final item in serverList) {
      final name = item['name'] as String? ?? '';
      if (name.isEmpty) continue;

      final colorMap = item['color'] as Map<String, dynamic>? ?? {};
      final r = (colorMap['r'] as num?)?.toInt() ?? 128;
      final g = (colorMap['g'] as num?)?.toInt() ?? 128;
      final b = (colorMap['b'] as num?)?.toInt() ?? 128;
      final belonging = item['belongingTo'] as String? ?? '';

      final existing = eventInfoBox.get(name);
      if (existing == null) {
        // 本地没有 → 新增
        await eventInfoBox.put(name, EventInfoRecord(
          eventName: name,
          color_rgb: [r, g, b],
          belongingToEvent: belonging,
        ));
        changed = true;
        print('== DataSync._applyServerEventInfo: added "$name"');
      } else {
        // 本地有 → 检查是否需要更新
        final colorChanged = existing.color_rgb.length < 3 ||
            existing.color_rgb[0] != r ||
            existing.color_rgb[1] != g ||
            existing.color_rgb[2] != b;
        final belongingChanged = existing.belongingToEvent != belonging;
        if (colorChanged || belongingChanged) {
          existing.color_rgb = [r, g, b];
          existing.belongingToEvent = belonging;
          await eventInfoBox.put(name, existing);
          changed = true;
          print('== DataSync._applyServerEventInfo: updated "$name" color/belonging');
        }
      }
    }

    // 更新本地排序：服务端顺序在前，本地独有追加在后
    final serverNames = serverList.map((e) => e['name'] as String? ?? '').where((n) => n.isNotEmpty).toList();
    final localNames = eventInfoBox.keys.cast<String>().toList();
    final extraLocal = localNames.where((n) => !serverNames.contains(n)).toList();
    final newOrder = [...serverNames, ...extraLocal];
    await SyncConfig.setEventInfoOrder(newOrder);

    return changed;
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

  /// 从 eventInfoBox 构建上传列表（含顺序信息）
  ///
  /// [orderedNames] 若非空，则按此顺序排列（来自 syncConfig 的持久化排序）；
  /// 否则按 box 的自然顺序。
  List<Map<String, dynamic>> _buildEventInfoList(
    Box<EventInfoRecord> eventInfoBox, {
    List<String> orderedNames = const [],
  }) {
    final List<Map<String, dynamic>> eventInfoList = [];

    // 构建 name → record 映射
    final Map<String, EventInfoRecord> recMap = {};
    for (final key in eventInfoBox.keys) {
      final rec = eventInfoBox.get(key as String);
      if (rec != null) recMap[rec.eventName] = rec;
    }

    // 按 orderedNames 顺序（已有顺序列表），剩余的追加到末尾
    final ordered = orderedNames.where((n) => recMap.containsKey(n)).toList();
    final unordered = recMap.keys.where((n) => !ordered.contains(n)).toList();
    final nameList = [...ordered, ...unordered];

    for (int i = 0; i < nameList.length; i++) {
      final rec = recMap[nameList[i]]!;
      eventInfoList.add({
        'name': rec.eventName,
        'color': {'r': rec.color_rgb[0], 'g': rec.color_rgb[1], 'b': rec.color_rgb[2]},
        'belongingTo': rec.belongingToEvent,
        'sortOrder': i,
      });
    }
    return eventInfoList;
  }

  /// 读取指定日期范围内的 dayRecords
  Map<String, List<List<dynamic>>> _readDayRecordsInRange(
    Box<DayEventsRecord> dayRecordBox,
    String rangeStart,
    String rangeEnd,
  ) {
    final Map<String, List<List<dynamic>>> dayRecordsMap = {};
    final allDatesInRange = _enumerateDates(rangeStart, rangeEnd);
    for (final dateKey in allDatesInRange) {
      final record = dayRecordBox.get(dateKey);
      if (record != null && record.events.isNotEmpty) {
        dayRecordsMap[dateKey] = record.exportRecordAsJson_onlyEvents();
      }
    }
    return dayRecordsMap;
  }

  // ─────────────────────────────────────────────
  // 兼容旧接口（供 editPage.dart 的"上传数据"按钮保留使用）
  // ─────────────────────────────────────────────

  /// 向后兼容：仅执行上传（内部调用 runFullSync）
  Future<SyncResult> runUploadTask() => runFullSync();

  /// 兼容接口：判断是否应该使用多步同步
  /// 首次同步或本地数据为空时，建议使用多步同步拉取全部历史
  Future<bool> shouldUseMultiStepSync() async {
    final lastSync = await SyncConfig.getLastSyncEndDate();
    if (lastSync == null) return true; // 从未同步过

    final dayRecordBox = Hive.box<DayEventsRecord>('dayRecords');
    final allKeys = dayRecordBox.keys.cast<String>().toList();
    if (allKeys.isEmpty) return true; // 本地无数据

    return false;
  }
}
