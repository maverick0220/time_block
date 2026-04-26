import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:time_block/dataStructure.dart';
import 'package:time_block/database/DayEventsRecord.dart';
import 'package:time_block/database/EventInfoRecord.dart';
import 'package:time_block/database/EventRecord.dart';
import 'package:time_block/network/dataSync.dart';
import 'package:time_block/network/syncConfig.dart';

// 互斥锁工具类（确保线程安全）
class Lock {
  bool _isLocked = false;
  final _queue = Queue<Completer<void>>();

  Future<void> synchronized(Function() action) async {
    while (_isLocked) {
      final completer = Completer<void>();
      _queue.add(completer);
      await completer.future;
    }

    _isLocked = true;
    try {
      await action();
    } finally {
      _isLocked = false;
      if (_queue.isNotEmpty) {
        _queue.removeFirst().complete();
      }
    }
  }
}

class UserProfileLoader extends ChangeNotifier {
    // 数据的增查改删API，任何动数据的事情都是这个类的实例提供服务
    late Box<DayEventsRecord> dayEventsRecordBox;// = Hive.box<DayEventsRecord>("dayRecords");
    late Box<EventInfoRecord> eventInfoRecordBox;

    late DataSync dataSync;
    late Timer _rightNowTimer;
    // var eventInfoRecordBox = Hive.box<EventInfoRecord>("eventInfoRecord"); // eventInfo还是暂时用json保存吧
    DateFormat formatter = DateFormat('yyyyMMdd');

    // 这个类里面直接保持当前年的全部数据json（拢共才几MB大小的数据，长期保存在内存里也不是什么罪过）
    // Map<String, dynamic> jsonData = {};
    Map<String, DayRecord> dayRecords = {}; // {"20250101": DayRecord()}
    List<String> renderDates = []; // 用来查询该渲染哪几天的数据，而不是全都渲染出来
    List<int> rightNowBlockIndex = [];

    List<EventInfo> eventInfos = [];

    UserProfileLoader(Box<DayEventsRecord> dayRecordBox, Box<EventInfoRecord> eventInfoBox, {List<String> savedOrder = const []}) {
        dayEventsRecordBox = dayRecordBox;
        eventInfoRecordBox = eventInfoBox;
        
        // 先构建 name→EventInfo 映射
        final Map<String, EventInfo> infoMap = {};
        for (var eventInfoKey in eventInfoBox.keys){
            var eventInfo = eventInfoBox.get(eventInfoKey);
            if (eventInfo != null){
                infoMap[eventInfo.eventName] = EventInfo(eventInfo.eventName, eventInfo.color_rgb);
            }
        }

        // 按 savedOrder 排列，未在 savedOrder 中的条目追加到末尾
        final orderedNames = savedOrder.where((n) => infoMap.containsKey(n)).toList();
        final unorderedNames = infoMap.keys.where((n) => !orderedNames.contains(n)).toList();
        for (final name in [...orderedNames, ...unorderedNames]) {
            eventInfos.add(infoMap[name]!);
        }
        print("== eventInfoBox eventInfos length: ${eventInfos.length}, order: ${eventInfos.map((e) => e.name).toList()}");

        // 2.数据加载
        // DateTime today = DateTime.parse("20250606");//DateTime.now();//.toString().split(" ")[0].replaceAll("-", "");
        DateTime today = DateTime.now();
        print("== init app with date: ${today}");
        const int aroundDayCount = 3;
        List<DateTime> dates = List.generate(aroundDayCount, (i) => today.add(Duration(days: -(aroundDayCount)+i))) + List.generate(aroundDayCount, (i) => today.add(Duration(days: i)));
        renderDates = List.generate(dates.length, (i) => dates[i].toString().split(" ")[0].replaceAll("-", ""));
        print("== UserProfileLoader renderDates: ${renderDates}");        

        for (var date in renderDates){
          var dayRecord = dayEventsRecordBox.get(date);
          if (dayRecord == null){
            // print("== problem at date ${date} while searching dayRecordBox");
            dayEventsRecordBox.put(date, DayEventsRecord(date: date, events: []));
          }
          dayRecord?.printRecord();
          dayRecords[date] = DayRecord(date, dayRecord?.events, this);
        }

        print("== UserProfileLoader init: ${renderDates}");

        // rightNowBlockIndex = transfromDateTimeToBlockIndex(today);
        // - todo: 这个rightNowBlockIndex得每隔一段时间自动更新，而且得让谁去通知新的和移除旧的标记
        // print("== userProfileLoader rightNowBlockIndex passed to update method: ${rightNowBlockIndex}");
        updateRightNowBlock(today);

        int minutes = today.minute;
        int second = today.second;
        int ms = today.millisecond;
        Duration initialDelay = Duration(minutes: ((((minutes ~/ 15)+1)*15)-minutes)%60, seconds: (60-second) % 60, milliseconds: (1000 - ms) % 1000);
        Timer(initialDelay, () {
            updateRightNowBlock(DateTime.now()); // 第一次在15分钟整倍数时执行
            _rightNowTimer = Timer.periodic(const Duration(minutes: 15), (timer) { updateRightNowBlock(DateTime.now()); });
        });

        dataSync = DataSync();
    }

    List<int> transfromDateTimeToBlockIndex(DateTime time){
        List<int> blockIndex = List.generate(3, (index) => int.parse(time.toString().split(" ")[0].split("-")[index]));
        final moment = List.generate(2, (index) => int.parse(time.toString().split(" ")[1].split(":")[index]));
        blockIndex.add(moment[0]*4 + moment[1]~/15);

        return blockIndex;
    }

    void updateRightNowBlock(DateTime newDateTime){
        // 取消旧的rightNowBlock。如果是个空的那就是以前没标记过
        // print("== updateRightNowBlock rightNowBlockIndex: $rightNowBlockIndex");
        // print("== updateRightNowBlock newBlockIndex: $newDateTime");
        if (rightNowBlockIndex.isEmpty == false){
            String date = "${rightNowBlockIndex[0]}${rightNowBlockIndex[1].toString().padLeft(2, '0')}${rightNowBlockIndex[2].toString().padLeft(2, '0')}";
            // print("== updateRightNowBlock date: $date");
            // print("== updateRightNowBlock operation result: ${dayRecords[date]?.blocks[rightNowBlockIndex[3] ~/ 4][rightNowBlockIndex[3] % 4].isRightNow}");
            try{
                dayRecords[date]?.blocks[rightNowBlockIndex[3] ~/ 4][rightNowBlockIndex[3] % 4].isRightNow = false;
            }catch (e) {
                // dayRecords[date] = DayRecord(date, dayRecord?.events, this);
                // 这里可能有个边界外的问题，如果是hiveDB里没有，而且新的一天已经到了，那就得确定是不是DB里有，然后加载对应的DayRecord到loader里
                // print("== updateRightNowBlock e: $e");
            }
            // print("== updateRightNowBlock operation result: ${dayRecords[date]?.blocks[rightNowBlockIndex[3] ~/ 4][rightNowBlockIndex[3] % 4].isRightNow}");
        }

        // 标记新的rightNowBlock
        List<int> newBlockIndex = transfromDateTimeToBlockIndex(newDateTime);
        String date = "${newBlockIndex[0]}${newBlockIndex[1].toString().padLeft(2, '0')}${newBlockIndex[2].toString().padLeft(2, '0')}";
        dayRecords[date]?.blocks[newBlockIndex[3] ~/ 4][newBlockIndex[3] % 4].isRightNow = true;
        rightNowBlockIndex = newBlockIndex;

    }

    Color getBlockColorByEventType(String eventInfoKey){
        // 根据eventInfoKey返回对应的颜色
        var eventInfo = eventInfoRecordBox.get(eventInfoKey);
        if (eventInfo != null){
            List<int> color = eventInfo.color_rgb;
            return Color.fromRGBO(color[0], color[1], color[2], 1);
        }

        return Color.fromRGBO(0, 0, 0, 1);
    }
    
    List<DayRecord> createEmptyDayRecords(String startDateString, int range){
        // 创造从startDate开始后往后range这么多天的空白日期记录
        // var startDate_string = startDate.toString().split(" ")[0].split("-");
        // var startDate_int = List<int>.generate(3, (i) => int.parse(startDate_string[i]));

        DateTime startDate = DateTime.parse("${startDateString.substring(0,4)}-${startDateString.substring(4,6)}-${startDateString.substring(6)}");
        List<String> dateStrings = [];
        for (int i = 0; i < range; i++) {
            DateTime currentDay = startDate.add(Duration(days: i));
            String formattedDate = "${currentDay.year}${currentDay.month.toString().padLeft(2, '0')}${currentDay.day.toString().padLeft(2, '0')}";
            dateStrings.add(formattedDate);
        }
        // range是1才有1个DayRecord，是0的话就一天都没有了
        List<DayRecord> record = List.generate(range, (i) => DayRecord(dateStrings[i], [], this));
        return record;
    }

    List<Block> getBlocksByIndexRange(List<int> startIndex, List<int> endIndex) {
        // 根据blockIndex返回对应的block数组
        // 返回的List是不包含startIndex和endIndex的，仅包含两个index之间的block。
        // 因为在唯一调用这个method的地方，startIndex对应的block已经被选中了，所以不用再选一遍了
        // 而且存在endIndex可能再startIndex前面的情况，要再加判断更麻烦，索性在这里就俩都不放进去，左右都是开区间
        
        DateTime startDate = DateTime.parse("${startIndex[0]}-${startIndex[1].toString().padLeft(2, '0')}-${startIndex[2].toString().padLeft(2, '0')}");
        DateTime endDate = DateTime.parse("${endIndex[0]}-${endIndex[1].toString().padLeft(2, '0')}-${endIndex[2].toString().padLeft(2, '0')}");

        List<Block> requiredBlocks = [];
        requiredBlocks.add(dayRecords[startDate.toString().split(" ")[0].replaceAll("-", "")]!.getBlockFromOneDayByIndex(startIndex[3]));
        requiredBlocks.add(dayRecords[endDate.toString().split(" ")[0].replaceAll("-", "")]!.getBlockFromOneDayByIndex(endIndex[3]));

        if (startDate.isAfter(endDate) || (startDate.day == endDate.day && startIndex[3] > endIndex[3])) {
            DateTime temp = startDate;
            startDate = endDate;
            endDate = temp;

            List<int> tempIndex = List.from(startIndex);
            startIndex = List.from(endIndex);
            endIndex = tempIndex;
            // print("== getBlocksByIndexRange: did swamp");
        }

        // 1-不跨day的情形。是大多数情况
        if (startDate.day == endDate.day){
            print("== getBlocksByIndexRange: 1, ${endDate.toString().split(" ")[0].replaceAll("-", "")}, ${startIndex[3]}, ${endIndex[3]}");
            String targetDate = endDate.toString().split(" ")[0].replaceAll("-", "");
            requiredBlocks.addAll(dayRecords[targetDate]!.getBlocksFromOneDayByIndex_OpenRange(startIndex[3], endIndex[3]));
            return requiredBlocks;
        }

        // 2-跨day的情形。执行次数相对较少（估计主要是晚上睡觉跨天了）：
        // 2-1先确定有哪些天，形成列表。
        int range = endDate.difference(startDate).inDays + 1;
        List<DateTime> dates = List.generate(range, (i) => startDate.add(Duration(days: i)));
        print("== getBlocksByIndexRange day counts: ${dates.length}");

        // 2-2再根据形成的列表，按照每一天的范围补齐中间的index（例如跨天了，那么就会在start-day1、end-day2之间再创造end-day1、start-day2，形成天数*2的index范围对列表
        requiredBlocks = [];
        List<List<List<int>>> indexRangeList = [];
        if (dates.length < 3){
            List<int> endIndex_1 = List.from(startIndex);
            endIndex_1[3] = 95;
            indexRangeList.add([startIndex, endIndex_1]);

            List<int> startIndex_2 = List.from(endIndex);
            startIndex_2[3] = 0;
            indexRangeList.add([startIndex_2, endIndex]);
            print("== getBlocksByIndexRange: 2-1, indexRangeList ${indexRangeList}");
        }else{
            List<int> endIndex_1 = List.from(startIndex);
            endIndex_1[3] = 95;
            indexRangeList.add([startIndex, endIndex_1]);
            print("== getBlocksByIndexRange: 2-2, indexRangeList ${indexRangeList}");
            for (int i = 1; i < dates.length - 1; i++){
                var startIndex_i = List<int>.from([dates[i].year, dates[i].month, dates[i].day, 0]);
                var endIndex_i = List<int>.from([dates[i].year, dates[i].month, dates[i].day, 95]);
                indexRangeList.add([startIndex_i, endIndex_i]);

                print("== getBlocksByIndexRange: 2-2-${i}, indexRangeList ${indexRangeList}");
            }

            List<int> startIndex_2 = List.from(endIndex);
            startIndex_2[3] = 0;
            indexRangeList.add([startIndex_2, endIndex]);
        }

        // 2-3最后把这个范围对列表进行迭代，用不跨day的相同办法收集block
        for (var indexRange in indexRangeList){
            String targetDate = "${indexRange[0][0]}${indexRange[0][1].toString().padLeft(2, '0')}${indexRange[0][2].toString().padLeft(2, '0')}";
            print("== getBlocksByIndexRange: 2-3, ${targetDate}, range: ${indexRange[0][3]}-${indexRange[1][3]}");
            requiredBlocks.addAll(dayRecords[targetDate]!.getBlocksFromOneDayByIndex_CloseRange(indexRange[0][3], indexRange[1][3]));
            print("== getBlocksByIndexRange: 2-4, ${List.generate(requiredBlocks.length, (index) => requiredBlocks[index].blockIndex)}");
        }
        print("== getBlocksByIndexRange requiredBlocks: ${List.generate(requiredBlocks.length, (index) => requiredBlocks[index].blockIndex)}");
        return requiredBlocks;
    }


    // Future<void> importRecordData(String importRecords) async {
    //     // 这里是要考虑冲突问题的……草
    //     Map<String, String> records = json.decode(importRecords);
    //     final dayRecordBox = await Hive.openBox<DayEventsRecord>("dayRecords");


    //     for (var date in records.keys){
    //         final dayRecord = dayRecordBox.get(date);
    //         if (dayRecord != null){
    //             // 如果这一天已经存在本地记录了，那就得对比一下，然后看看怎么合并
    //             List<EventRecord> mergedEventRecords = mergeEventRecords(dayRecord.events, records[date] as List<EventRecord>);
    //         }else{
    //             // 如果这一天根本没本地记录，那就照单全收
    //             records[date.toString()] = dayRecord!.exportRecordAsString_onlyEvents();
    //         }
    //     }
        
    // }

    List<EventRecord> mergeEventRecords_old(List<EventRecord> record_1, List<EventRecord> record_2){
        // 1. 合并两个列表
        List<EventRecord> merged = [];
        merged.addAll(record_1);
        merged.addAll(record_2);

        // 2. 按起始时间排序（可选，方便后续处理和查看）
        merged.sort((a, b) {
            if (a.startIndex != b.startIndex) {
                return a.startIndex.compareTo(b.startIndex);
            }
            return a.endIndex.compareTo(b.endIndex);
        });

        // 3. 可选：如果你想标记冲突，可以遍历并找出有重叠的事件
        for (int i = 0; i < merged.length; i++) {
            for (int j = i + 1; j < merged.length; j++) {
                if (!(merged[i].endIndex < merged[j].startIndex || merged[j].endIndex < merged[i].startIndex)) {
                    // 有重叠
                    merged[i].comment += " [conflict with event ${j}]";
                    merged[j].comment += " [conflict with event ${i}]";
                }
            }
        }

        return merged;
    }

    List<EventRecord> mergeEventRecords(List<EventRecord> mainRecord, List<EventRecord> addedRecord) {
        // 1. 以record_1为主体，先按时间排序
        // List<EventRecord> mainRecord = List.from(record_1)
        //     ..sort((a, b) => a.startIndex.compareTo(b.startIndex));
        // List<EventRecord> addedRecord = List.from(record_2)
        //     ..sort((a, b) => a.startIndex.compareTo(b.startIndex));

        List<EventRecord> result = [];

        // 2. 标记mainRecord每个时间段的归属
        List<int?> owner = List.filled(96, null); // 0: mainRecord, 1: addedRecord
        for (var rec in mainRecord) {
            for (int i = rec.startIndex; i <= rec.endIndex; i++) {
                owner[i] = 0;
            }
        }

        // 3. 处理record_2，分割出未被record_1覆盖的区间
        for (var rec in addedRecord) {
            int segStart = -1;
            for (int i = rec.startIndex; i <= rec.endIndex + 1; i++) {
                bool covered = (i <= rec.endIndex) && owner[i] == 0;
                if (segStart == -1 && !covered && i <= rec.endIndex) {
                    segStart = i;
                }
                if ((segStart != -1 && (covered || i > rec.endIndex))) {
                    // 找到一段未被覆盖的区间
                    result.add(EventRecord(startIndex: segStart, endIndex: i - 1, eventInfo: rec.eventInfo));
                    segStart = -1;
                }
            }
        }

        // 4. 处理record_1，标记冲突
        for (var rec in mainRecord) {
            bool hasConflict = false;
            List<String> conflictEvents = [];
            for (var rec2 in addedRecord) {
            int overlapStart = rec.startIndex > rec2.startIndex ? rec.startIndex : rec2.startIndex;
            int overlapEnd = rec.endIndex < rec2.endIndex ? rec.endIndex : rec2.endIndex;
            if (overlapStart <= overlapEnd) {
                hasConflict = true;
                conflictEvents.add('${rec2.eventInfo}($overlapStart~$overlapEnd)');
            }
            }
            if (hasConflict) {
            rec.comment += ' [conflict: ' + conflictEvents.join(', ') + ']';
            }
            result.add(rec);
        }

        // 5. 按startIndex排序输出
        result.sort((a, b) => a.startIndex.compareTo(b.startIndex));
        return result;
    }


    /// 同步后调用：从 Hive eventInfoBox 重建内存中的 eventInfos 列表，
    /// 并按 [SyncConfig.getEventInfoOrder] 排序，然后触发 UI 刷新。
    ///
    /// 应在 DataSync 的 _applyServerEventInfo 写入 Hive 后调用。
    Future<void> applyServerEventInfo() async {
        // 重新读取已更新的 Hive 数据
        final Map<String, EventInfo> infoMap = {};
        for (final key in eventInfoRecordBox.keys) {
            final rec = eventInfoRecordBox.get(key as String);
            if (rec != null) {
                infoMap[rec.eventName] = EventInfo(rec.eventName, rec.color_rgb);
            }
        }

        // 按持久化顺序重建列表
        final savedOrder = await SyncConfig.getEventInfoOrder();
        final orderedNames = savedOrder.where((n) => infoMap.containsKey(n)).toList();
        final unorderedNames = infoMap.keys.where((n) => !orderedNames.contains(n)).toList();

        eventInfos
            ..clear()
            ..addAll([...orderedNames, ...unorderedNames].map((n) => infoMap[n]!));

        print('== UserProfileLoader.applyServerEventInfo: rebuilt ${eventInfos.length} items, order: ${eventInfos.map((e) => e.name).toList()}');
        notifyListeners();
    }

    /// 同步收到补丁后调用：将指定日期的数据从 Hive 重新加载到内存中的 dayRecords，
    /// 并触发 UI 刷新（无论该日期是否在当前 renderDates 窗口内）
    void applyPatchedDates(List<String> dates) {
        if (dates.isEmpty) return;
        bool changed = false;
        for (final date in dates) {
            final hiveRecord = dayEventsRecordBox.get(date);
            // 无论该日期是否在 renderDates 内，都更新内存中的 DayRecord
            // 这样用户滚动到该日期时能立即看到最新数据
            dayRecords[date] = DayRecord(date, hiveRecord?.events, this);
            changed = true;
            print('== UserProfileLoader.applyPatchedDates: refreshed $date (${hiveRecord?.events.length ?? 0} events)');
        }
        if (changed) {
            notifyListeners();
        }
    }

    /// 拖动排序后调用：持久化新顺序并通知 UI 刷新
    Future<void> reorderEventInfos(int oldIndex, int newIndex) async {
        // ReorderableListView 的 newIndex 在移除旧元素前计算，需修正
        if (newIndex > oldIndex) newIndex -= 1;
        final item = eventInfos.removeAt(oldIndex);
        eventInfos.insert(newIndex, item);
        // 持久化排序
        final order = eventInfos.map((e) => e.name).toList();
        await SyncConfig.setEventInfoOrder(order);
        notifyListeners();
    }

    Future<String> exportRecordDataByDates(List<String> dates, bool saveAsFile) async {
        Map<String, List<List<dynamic>>> records = {};

        // 使用已打开的 Box，不要重新 open
        final dayRecordBox = Hive.box<DayEventsRecord>("dayRecords");

        if (dates.isEmpty){
            // 默认dates没指定的话，就是导出全部
            dates = dayEventsRecordBox.keys.cast<String>().toList();
        }

        for (var date in dates){
            final dayRecord = dayRecordBox.get(date);
            if (dayRecord != null){
                records[date.toString()] = dayRecord.exportRecordAsJson_onlyEvents();
            }
        }

        // records这个Map转换成json文件，以json格式的字符串形式返回
        // print("== export records of dates: $dates, records: =${records}=");
        String recordsData = const JsonEncoder.withIndent('    ').convert(records);
        // print("== export records of dates: $dates, records: =${recordsData}=");

        if (saveAsFile){
            File outputFile = File("./hiveDB/outputData-${DateTime.now().toIso8601String().replaceAll(RegExp(r'[:\-\.]'), "")}.json");
            outputFile.writeAsString(recordsData);
        }

        return recordsData;
    }

    Future<void> updateDayRecordToBox(String updateDate) async {
        var updateEvents = dayRecords[updateDate]?.events;
        if (updateEvents != null){
            DayEventsRecord updateDayRecord = DayEventsRecord(date: updateDate, events: updateEvents);
            print("== updateDayRecordToBox 1: putting ${updateDate} with ${List.generate(updateDayRecord.events.length, (i) => updateDayRecord.events[i].eventInfo)}");
            dayEventsRecordBox.put(updateDate, updateDayRecord);
        }else{
            dayEventsRecordBox.put(updateDate, DayEventsRecord(date: updateDate, events: []));
            print("== updateDayRecordToBox: add a empty day at date ${updateDate}");
        }
    }
}


class OperationControl extends ChangeNotifier {
    List<Block> selectedBlocks = [];
    String selectedBlockEvent = "";
    List<String> renderDates = [];

    // ─────────────────────────────────────────────
    // 长按拖动选中状态
    // ─────────────────────────────────────────────
    bool isLongPressSelecting = false;
    Block? longPressStartBlock;
    Block? longPressCurrentBlock;
    List<Block> longPressPreviewBlocks = [];

    /// 开始长按拖动选择
    void startLongPressSelect(Block block, UserProfileLoader userProfileLoader) {
      print('== OperationControl.startLongPressSelect: ${block.blockIndex}');
      isLongPressSelecting = true;
      longPressStartBlock = block;
      longPressCurrentBlock = block;

      // 清空之前的选中状态
      for (var b in selectedBlocks) {
        b.unselectBlock();
      }
      selectedBlocks.clear();
      selectedBlockEvent = '';

      // 更新预览
      _updateLongPressPreview(userProfileLoader);
      notifyListeners();
    }

    /// 更新长按拖动选择过程中的当前块
    void updateLongPressSelect(Block block, UserProfileLoader userProfileLoader) {
      if (!isLongPressSelecting) return;

      longPressCurrentBlock = block;
      _updateLongPressPreview(userProfileLoader);
      notifyListeners();
    }

    /// 完成长按拖动选择
    void endLongPressSelect(UserProfileLoader userProfileLoader) {
      if (!isLongPressSelecting) return;

      print('== OperationControl.endLongPressSelect: preview ${longPressPreviewBlocks.length} blocks');

      // 将预览块转为正式选中
      for (var b in longPressPreviewBlocks) {
        b.selectBlock();
        selectedBlocks.add(b);
      }

      // 更新选中事件描述
      _updateSelectedBlockEvent();

      // 重置长按状态
      isLongPressSelecting = false;
      longPressStartBlock = null;
      longPressCurrentBlock = null;
      longPressPreviewBlocks.clear();

      notifyListeners();
    }

    /// 取消长按拖动选择
    void cancelLongPressSelect() {
      if (!isLongPressSelecting) return;

      // 重置预览块颜色
      for (var b in longPressPreviewBlocks) {
        if (!selectedBlocks.contains(b)) {
          b.unselectBlock();
        }
      }

      isLongPressSelecting = false;
      longPressStartBlock = null;
      longPressCurrentBlock = null;
      longPressPreviewBlocks.clear();

      notifyListeners();
    }

    /// 更新长按拖动预览块
    void _updateLongPressPreview(UserProfileLoader userProfileLoader) {
      // 1. 重置之前的预览块颜色
      for (var b in longPressPreviewBlocks) {
        if (!selectedBlocks.contains(b)) {
          b.unselectBlock();
        }
      }
      longPressPreviewBlocks.clear();

      // 2. 如果没有起点块，不做处理
      if (longPressStartBlock == null || longPressCurrentBlock == null) return;

      // 3. 获取起点到当前块之间的所有块
      longPressPreviewBlocks = userProfileLoader.getBlocksByIndexRange(
        longPressStartBlock!.blockIndex,
        longPressCurrentBlock!.blockIndex,
      );

      // 4. 设置预览颜色（半透明选中色）
      for (var b in longPressPreviewBlocks) {
        b.selectBlock();
      }
    }

    /// 更新选中块的事件描述
    void _updateSelectedBlockEvent() {
      final List<String> orderedEvents = [];
      String lastEvent = '';
      for (final b in selectedBlocks) {
        if (b.eventType.isNotEmpty && b.eventType != lastEvent) {
          orderedEvents.add(b.eventType);
          lastEvent = b.eventType;
        }
      }
      selectedBlockEvent = orderedEvents.join(' · ');
    }

    // ─────────────────────────────────────────────
    // 点击选择（原有逻辑）
    // ─────────────────────────────────────────────

    void selectBlocks(Block block, UserProfileLoader userProfileLoader){
        // 长按选择模式下，点击不处理（由长按结束/取消处理）
        if (isLongPressSelecting) {
          print("== selectBlocks: ignored during long press select");
          return;
        }

        print("== selectedBlocks start: ${List<List<int>>.generate(selectedBlocks.length, (i) => selectedBlocks[i].blockIndex)}");
        // 选择block，如果已经有两个block被选中了，那么就清空，重新选
        switch (selectedBlocks.length) {
            case 0:
                print("== selectedBlocks: 0");
                selectedBlocks.add(block);
                selectedBlocks[0].selectBlock();
                notifyListeners();
            case 1:
                if (selectedBlocks[0] == block){
                    print("== selectedBlocks: 1-1");
                    selectedBlocks[0].unselectBlock();
                    selectedBlocks.clear();
                    // block.unselectBlock();
                    notifyListeners();
                }else{
                    print("== selectedBlocks: 1-2");
                    // 把两个block之间的所有block都给添加到selectedBlocks里面
                    print("== selectedBlocks: ${selectedBlocks[0].blockIndex}, ${block.blockIndex}");
                    selectedBlocks = userProfileLoader.getBlocksByIndexRange(selectedBlocks[0].blockIndex, block.blockIndex);

                    for (var block in selectedBlocks){ block.selectBlock(); }
                    notifyListeners();
                }
            default:
                print("== selectedBlocks: default");
                // todo：这里不应该是现在的逻辑。应该是只要点了就给加进来，多选状态下的取消和擦除应该是额外的按钮的活儿

                bool newBlockHasBeenSelected = false;
                for (int i=0; i<selectedBlocks.length; i++){
                    if (selectedBlocks[i] == block){
                        print("== selectBlocks default start - block ${block.blockIndex}, color: ${block.color}");
                        
                        print("== selectBlocks default block ${block.blockIndex}, backupColor: ${block.backupColor}");
                        selectedBlocks[i].color = selectedBlocks[i].backupColor;
                        notifyListeners();

                        selectedBlocks.removeAt(i);
                        newBlockHasBeenSelected = true;

                        print("== selectBlocks end  -- block ${block.blockIndex}, color: ${block.color}");
                        break;
                    }
                }
                if (newBlockHasBeenSelected == false){
                    selectedBlocks.add(block);
                    block.selectBlock();
                }
        } 
        
        _updateSelectedBlockEvent();
        notifyListeners();

        // 给selectedBlocks按时间排个序
        selectedBlocks.sort((a, b) {
            for (int i = 0; i < 4; i++) {
                if (a.blockIndex[i] != b.blockIndex[i]) {
                    return a.blockIndex[i].compareTo(b.blockIndex[i]);
                }
            }
            return 0;
        });
        
        print("== selectedBlocks end: ${List<List<int>>.generate(selectedBlocks.length, (i) => selectedBlocks[i].blockIndex)}\n");
    }

    Future<void> recordBlocksAsEvent(String eventType, UserProfileLoader userProfileLoader) async {
        print("== recordBlocksAsEvent-1");
        if (selectedBlocks.isEmpty){ return; }

        // 整个方法都可以重写以下，尽可能在一个for循环里搞定三件事（给每个block更新颜色和事件、整理出来按天分段的EventRecord、记录更新的事件都涉及那些date
        Set<String> updateDates = {};
        final eventColor = userProfileLoader.getBlockColorByEventType(eventType);
        for (var block in selectedBlocks){
            block.eventType = eventType;
            block.color = eventColor;
            updateDates.add(block.getDateAsString());
        }

        // _updateEventRecordsToDayRecords(eventRecordsForUpdate); // 把相关的date定下来，然后更新整个day的events，不然DayRecord里面没变化，就不会有任何新东西写入到hive
        // Set updateDates = List.generate(selectedBlocks.length, (i) => selectedBlocks[i].getDateAsString()).toSet();
        for (var updateDate in updateDates){
            print("== recordBlocksAsEvent: did get here");
            await userProfileLoader.dayRecords[updateDate]?.updateDayRecordEvents().then((value) async => {
                userProfileLoader.updateDayRecordToBox(updateDate)
            });
        }

        selectedBlockEvent = "";
        selectedBlocks.clear();
        notifyListeners();
    }

    void cancelSelection(){
        // 取消选中
        if (selectedBlocks.isEmpty){ return; }

        // print("== cancelSelection selectedBlocks: length ${selectedBlocks.length}, ${selectedBlocks}");

        for (var block in selectedBlocks){
            block.unselectBlock();
        }

        // selectedBlocks[0].unselectBlock(); // 别问为啥，不单独写这句话反正就是会有bug，写了就对了
        selectedBlocks.clear();
        selectedBlockEvent = "";   // 清空顶部事件名显示
        notifyListeners();
    }

    Future<void> wipeSelection(UserProfileLoader userProfileLoader) async {
        // 把选中的block全都擦除
        if (selectedBlocks.isEmpty){ return; }

        Set<String> updateDates = {};
        for (var block in selectedBlocks){
            block.wipeOutBlock();
            updateDates.add(block.getDateAsString());
        }

        for (var updateDate in updateDates){
            await userProfileLoader.dayRecords[updateDate]?.updateDayRecordEvents().then((value) async => {
                userProfileLoader.updateDayRecordToBox(updateDate)
            });
        }
        
        selectedBlockEvent = "";
        selectedBlocks.clear();
        notifyListeners();
    }

    void refreshRenderDates(UserProfileLoader userProfileLoader) {
        // 刷新显示today的blocks
        DateTime now = DateTime.now();
        const int aroundDayCount = 3;
        List<DateTime> dates = List.generate(aroundDayCount, (i) => now.add(Duration(days: -(aroundDayCount)+i))) + List.generate(aroundDayCount, (i) => now.add(Duration(days: i)));
        userProfileLoader.renderDates = List.generate(dates.length, (i) => dates[i].toString().split(" ")[0].replaceAll("-", ""));

        for (var date in userProfileLoader.renderDates) {
            var dayRecord = userProfileLoader.dayEventsRecordBox.get(date);
            if (dayRecord == null) {
                // print("== problem at date ${date} while searching dayRecordBox");
                userProfileLoader.dayEventsRecordBox.put(date, DayEventsRecord(date: date, events: []));
            }
            // dayRecord?.printRecord();
            userProfileLoader.dayRecords[date] = DayRecord(date, dayRecord?.events, userProfileLoader);
        }

        // 更新此时此刻是哪个block了
        userProfileLoader.updateRightNowBlock(DateTime.now());
        notifyListeners();
    }

    void jumpRenderDates(UserProfileLoader userProfileLoader, DateTime jumpToDate){
        // 刷新显示today的blocks。跟上面的refreshRenderDates()其实是同一个函数
        const int aroundDayCount = 3;
        List<DateTime> dates = List.generate(aroundDayCount, (i) => jumpToDate.add(Duration(days: -(aroundDayCount)+i))) + List.generate(aroundDayCount, (i) => jumpToDate.add(Duration(days: i)));
        userProfileLoader.renderDates = List.generate(dates.length, (i) => dates[i].toString().split(" ")[0].replaceAll("-", ""));

        for (var date in userProfileLoader.renderDates){
          var dayRecord = userProfileLoader.dayEventsRecordBox.get(date);
          if (dayRecord == null){
            // print("== problem at date ${date} while searching dayRecordBox");
            userProfileLoader.dayEventsRecordBox.put(date, DayEventsRecord(date: date, events: []));
          }
          dayRecord?.printRecord();
          userProfileLoader.dayRecords[date] = DayRecord(date, dayRecord?.events, userProfileLoader);
        }

        // 重新标记当前时刻的 block（新建的 DayRecord 里所有 isRightNow 都是 false，
        // 必须在 dayRecords 填完之后调用，否则找不到对应的 block 对象）
        userProfileLoader.updateRightNowBlock(DateTime.now());
        notifyListeners();
    }

    void deleteEventInfo(EventInfo eventInfo, UserProfileLoader userProfileLoader){
        print("== deleteEventInfo: try to delete ${eventInfo.name}");
    }

    Future<void> editEventInfo(EventInfo eventInfo, UserProfileLoader userProfileLoader) async {
        print("== editEventInfo: try to edit ${eventInfo.name}");
        
        // 导入弹窗组件
        // 注意：这里需要在使用的地方 import eventInfoDialog.dart
    }

}