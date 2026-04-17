import 'dart:io';
import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:time_block/database/EventInfoRecord.dart';

void main() async {
  print("= moveConfigToHive =");

  // ── 目标路径：macOS 沙盒应用实际使用的 Hive 路径 ──
  // Hive.initFlutter() 在 macOS sandbox 下会使用
  // ~/Library/Containers/com.example.timeBlock/Data/Documents/
  final String hivePath = Platform.environment['HOME']! +
      '/Library/Containers/com.example.timeBlock/Data/Documents';

  print("== Hive path: $hivePath");
  Directory(hivePath).createSync(recursive: true);

  Hive.init(hivePath);
  Hive.registerAdapter(EventInfoRecordAdapter());
  final eventInfoBox = await Hive.openBox<EventInfoRecord>("eventInfo");

  print("== current keys before import: ${eventInfoBox.keys.toList()}");

  // ── 读取 config.json ──
  // 脚本从项目根目录运行（dart run lib/util/moveConfigToHive.dart）
  File configFile = File('./lib/config.json');
  final contents = await configFile.readAsString();
  if (contents.trim().isEmpty) {
    print("== config.json is empty, nothing to do.");
    await Hive.close();
    return;
  }

  var jsonData = jsonDecode(contents);
  for (var event in jsonData["eventInfo"]) {
    final String name = event[0] as String;
    final record = EventInfoRecord(
      eventName: name,
      color_rgb: [event[1]["r"] as int, event[1]["g"] as int, event[1]["b"] as int],
      belongingToEvent: "",
    );
    try {
      await eventInfoBox.put(name, record);
      print("== put: $name");
    } catch (e) {
      print("== error while put '$name': $e");
    }
  }

  // ── 验证写入结果 ──
  print("\n== === 写入完成，验证数据 ===");
  final keys = eventInfoBox.keys.toList();
  print("== total keys: ${keys.length}");
  for (var key in keys) {
    final EventInfoRecord? r = eventInfoBox.get(key);
    if (r != null) {
      print("  ✓ ${r.eventName}  rgb(${r.color_rgb[0]}, ${r.color_rgb[1]}, ${r.color_rgb[2]})");
    } else {
      print("  ✗ null for key: $key");
    }
  }

  await Hive.close();
  print("\n== done.");
}