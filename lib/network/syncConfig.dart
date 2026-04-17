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

  /// 计算本次需要上传的日期范围 [startDate, endDate]（格式均为 "YYYYMMDD"）
  ///
  /// - startDate: 上次同步截止日期的次日；若从未同步，则由调用方传入默认起始日期
  /// - endDate  : 今天
  ///
  /// 返回 null 表示无需上传（startDate > endDate）
  static Future<List<String>?> calcUploadRange({String? fallbackStartDate}) async {
    final today = _formatDate(DateTime.now());
    final lastEnd = await getLastSyncEndDate();

    String startDate;
    if (lastEnd == null) {
      // 从未同步：使用调用方传入的默认起始日期，或者今天
      startDate = fallbackStartDate ?? today;
    } else {
      // 上次同步截止日期的次日
      final lastEndDt = _parseDate(lastEnd);
      if (lastEndDt == null) {
        startDate = fallbackStartDate ?? today;
      } else {
        final nextDt = lastEndDt.add(const Duration(days: 1));
        startDate = _formatDate(nextDt);
      }
    }

    // 如果起始日期已经超过今天，没有需要上传的数据
    if (startDate.compareTo(today) > 0) return null;

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
