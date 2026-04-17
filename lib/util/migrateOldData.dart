import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:time_block/database/EventRecord.dart';
import 'package:time_block/database/EventInfoRecord.dart';
import 'package:time_block/database/DayEventsRecord.dart';

/// 数据迁移工具
/// 
/// 用于将旧版本使用 Hive.init("./hiveDB/") 存储的数据
/// 迁移到 Hive.initFlutter() 使用的跨平台存储路径
/// 
/// 使用方法：
/// 1. 在 main.dart 中调用 await migrateOldHiveData()
/// 2. 或者在单独的脚本中运行
Future<bool> migrateOldHiveData() async {
  print('=== 开始检查旧数据迁移 ===');
  
  // 旧数据目录路径
  final oldHiveDir = Directory('./hiveDB/');
  
  // 检查旧目录是否存在
  if (!await oldHiveDir.exists()) {
    print('未找到旧数据目录 ./hiveDB/，无需迁移');
    return false;
  }
  
  print('发现旧数据目录: ${oldHiveDir.absolute.path}');
  
  try {
    // 初始化新路径的 Hive
    await Hive.initFlutter();
    Hive.registerAdapter(EventRecordAdapter());
    Hive.registerAdapter(EventInfoRecordAdapter());
    Hive.registerAdapter(DayEventsRecordAdapter());
    
    // 打开或创建新位置的 box
    final newEventInfoBox = await Hive.openBox<EventInfoRecord>('eventInfo');
    final newDayRecordBox = await Hive.openBox<DayEventsRecord>('dayRecords');
    
    // 检查新位置是否已有数据
    if (newEventInfoBox.isNotEmpty || newDayRecordBox.isNotEmpty) {
      print('新位置已有数据，跳过迁移');
      print('  - eventInfo: ${newEventInfoBox.length} 条记录');
      print('  - dayRecords: ${newDayRecordBox.length} 条记录');
      
      // 关闭新位置的 box
      await newEventInfoBox.close();
      await newDayRecordBox.close();
      await Hive.close();
      
      return false;
    }
    
    // 初始化旧路径的 Hive
    Hive.init('./hiveDB/');
    Hive.registerAdapter(EventRecordAdapter());
    Hive.registerAdapter(EventInfoRecordAdapter());
    Hive.registerAdapter(DayEventsRecordAdapter());
    
    final oldEventInfoBox = await Hive.openBox<EventInfoRecord>('eventInfo');
    final oldDayRecordBox = await Hive.openBox<DayEventsRecord>('dayRecords');
    
    print('旧数据统计:');
    print('  - eventInfo: ${oldEventInfoBox.length} 条记录');
    print('  - dayRecords: ${oldDayRecordBox.length} 条记录');
    
    // 迁移 eventInfo
    for (var key in oldEventInfoBox.keys) {
      final value = oldEventInfoBox.get(key);
      if (value != null) {
        newEventInfoBox.put(key, value);
      }
    }
    
    // 迁移 dayRecords
    for (var key in oldDayRecordBox.keys) {
      final value = oldDayRecordBox.get(key);
      if (value != null) {
        newDayRecordBox.put(key, value);
      }
    }
    
    // 关闭所有 box
    await oldEventInfoBox.close();
    await oldDayRecordBox.close();
    await Hive.close();
    
    await newEventInfoBox.close();
    await newDayRecordBox.close();
    await Hive.close();
    
    print('=== 数据迁移完成 ===');
    print('已迁移:');
    print('  - eventInfo: ${newEventInfoBox.length} 条记录');
    print('  - dayRecords: ${newDayRecordBox.length} 条记录');
    
    // 提示用户可以删除旧目录
    print('\n⚠️  迁移成功后，您可以手动删除旧目录 ./hiveDB/');
    print('   备份命令: mv ./hiveDB/ ./hiveDB.backup.${DateTime.now().millisecondsSinceEpoch}/');
    
    return true;
    
  } catch (e, stackTrace) {
    print('❌ 数据迁移失败: $e');
    print(stackTrace);
    return false;
  }
}

/// 手动删除旧数据目录的辅助函数
/// 注意：此操作不可逆，建议先备份！
Future<void> deleteOldHiveData() async {
  final oldHiveDir = Directory('./hiveDB/');
  
  if (!await oldHiveDir.exists()) {
    print('旧数据目录不存在: ./hiveDB/');
    return;
  }
  
  // 先备份
  final backupDir = Directory('./hiveDB.backup.${DateTime.now().millisecondsSinceEpoch}/');
  await oldHiveDir.rename(backupDir.path);
  
  print('已将旧数据目录备份到: ${backupDir.path}');
  print('如确认新数据正常，可以手动删除备份目录');
}
