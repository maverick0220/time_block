import 'dart:convert';
import 'package:hive/hive.dart';

/// 管理数据同步相关的持久化配置
/// 使用 Hive 的 'syncConfig' box 存储，key/value 均为 String
class SyncConfig {
  static const String _boxName = 'syncConfig';
  static const String _serverUrlKey = 'serverUrl';

  /// 上次成功同步的截止日期（格式 "20250101"）
  /// 下次同步时，将从此日期的次日开始上传，直到今天
  static const String _lastSyncEndDateKey = 'lastSyncEndDate';

  /// 上次成功同步的 UTC 时间戳（ISO8601 字符串）
  /// 用于判断"今天是否已同步"——当天内多次同步需要重新上传当天数据
  static const String _lastSyncTimestampKey = 'lastSyncTimestamp';

  static Box<String>? _box;

  /// 初始化配置 box（应在 main() 中调用一次）
  static Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    if (Hive.isBoxOpen(_boxName)) {
      _box = Hive.box<String>(_boxName);
    } else {
      _box = await Hive.openBox<String>(_boxName);
    }
  }

  static Future<Box<String>> _ensureBox() async {
    if (_box != null && _box!.isOpen) return _box!;
    if (Hive.isBoxOpen(_boxName)) {
      _box = Hive.box<String>(_boxName);
    } else {
      _box = await Hive.openBox<String>(_boxName);
    }
    return _box!;
  }

  static Box<String> get _getBox {
    if (_box != null && _box!.isOpen) return _box!;
    throw StateError('SyncConfig not initialized. Call SyncConfig.init() first.');
  }

  // ─────────────────────────────────────────────
  // 服务端地址
  // ─────────────────────────────────────────────

  /// 读取服务端地址，默认为空字符串
  static Future<String> getServerUrl() async {
    final box = await _ensureBox();
    return box.get(_serverUrlKey, defaultValue: '') ?? '';
  }

  /// 保存服务端地址
  static Future<void> setServerUrl(String url) async {
    final box = await _ensureBox();
    await box.put(_serverUrlKey, url.trim());
  }

  // ─────────────────────────────────────────────
  // 上次同步截止日期
  // ─────────────────────────────────────────────

  /// 读取上次成功同步的截止日期（"YYYYMMDD" 格式）
  /// 若从未同步过，返回 null
  static Future<String?> getLastSyncEndDate() async {
    final box = await _ensureBox();
    final v = box.get(_lastSyncEndDateKey, defaultValue: '');
    return (v == null || v.isEmpty) ? null : v;
  }

  /// 保存上次同步截止日期（"YYYYMMDD" 格式）
  static Future<void> setLastSyncEndDate(String date) async {
    final box = await _ensureBox();
    await box.put(_lastSyncEndDateKey, date);
  }

  // ─────────────────────────────────────────────
  // 上次同步时间戳
  // ─────────────────────────────────────────────

  /// 读取上次同步时间戳（ISO8601 字符串）；若从未同步返回 null
  static Future<DateTime?> getLastSyncTimestamp() async {
    final box = await _ensureBox();
    final v = box.get(_lastSyncTimestampKey, defaultValue: '');
    if (v == null || v.isEmpty) return null;
    try {
      return DateTime.parse(v);
    } catch (_) {
      return null;
    }
  }

  /// 保存当前时刻为上次同步时间戳
  static Future<void> setLastSyncTimestamp() async {
    final box = await _ensureBox();
    await box.put(_lastSyncTimestampKey, DateTime.now().toIso8601String());
  }

  /// 计算本次需要上传的日期范围 [startDate, endDate]（格式均为 "YYYYMMDD"）
  ///
  /// 新逻辑：
  /// - endDate   = 今天（始终包含今天，确保当天多次同步都能上传最新状态）
  /// - startDate = 上次同步日期（不再加 +1 天，保证今天的数据每次都上传）；
  ///              若从未同步，使用 fallbackStartDate 或今天
  ///
  /// 返回 null 仅在内部错误时使用，正常情况始终返回包含今天的范围
  static Future<List<String>?> calcUploadRange({String? fallbackStartDate}) async {
    final today = _formatDate(DateTime.now());
    final lastEnd = await getLastSyncEndDate();

    String startDate;
    if (lastEnd == null) {
      // 从未同步：使用调用方传入的默认起始日期，或者今天
      startDate = fallbackStartDate ?? today;
    } else {
      // 从上次同步的那天开始（含当天），确保今天的数据在当天多次同步时都会上传
      // 如果上次同步是今天之前，则从上次截止日期开始（覆盖可能的增量变化）
      startDate = lastEnd.compareTo(today) < 0 ? lastEnd : today;
    }

    // startDate 最早不能超过 today（正常不会触发）
    if (startDate.compareTo(today) > 0) startDate = today;

    return [startDate, today];
  }

  // ─────────────────────────────────────────────
  // eventInfo 排序
  // ─────────────────────────────────────────────

  static const String _eventInfoOrderKey = 'eventInfoOrder';

  /// 读取 eventInfo 的排序列表（存储为 JSON 数组字符串）
  /// 返回 eventName 的有序列表，若从未保存过则返回空列表
  static Future<List<String>> getEventInfoOrder() async {
    final box = await _ensureBox();
    final raw = box.get(_eventInfoOrderKey, defaultValue: '') ?? '';
    if (raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.cast<String>();
    } catch (_) {
      return [];
    }
  }

  /// 保存 eventInfo 的排序列表
  static Future<void> setEventInfoOrder(List<String> order) async {
    final box = await _ensureBox();
    await box.put(_eventInfoOrderKey, jsonEncode(order));
  }

  // ─────────────────────────────────────────────
  // 工具方法
  // ─────────────────────────────────────────────

  static String _formatDate(DateTime dt) {
    return '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}';
  }

  static DateTime? _parseDate(String s) {
    if (s.length != 8) return null;
    try {
      return DateTime(int.parse(s.substring(0, 4)), int.parse(s.substring(4, 6)), int.parse(s.substring(6, 8)));
    } catch (_) {
      return null;
    }
  }
}
