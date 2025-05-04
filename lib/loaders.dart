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
    // var eventInfoRecordBox = Hive.box<EventInfoRecord>("eventInfoRecord"); // eventInfo还是暂时用json保存吧
    DateFormat formatter = DateFormat('yyyyMMdd');

    // 这个类里面直接保持当前年的全部数据json（拢共才几MB大小的数据，长期保存在内存里也不是什么罪过）
    // Map<String, dynamic> jsonData = {};
    Map<String, DayRecord> dayRecords = {}; // {"20250101": DayRecord()}
    List<String> renderDates = []; // 用来查询该渲染哪几天的数据，而不是全都渲染出来


    List<EventInfo> eventInfos = [];

    UserProfileLoader(Box<DayEventsRecord> dayRecordBox, Box<EventInfoRecord> eventInfoBox) {
        dayEventsRecordBox = dayRecordBox;
        eventInfoRecordBox = eventInfoBox;
        
        for (var eventInfoKey in eventInfoBox.keys){
            var eventInfo = eventInfoBox.get(eventInfoKey);
            if (eventInfo != null){
                eventInfos.add(EventInfo(eventInfo.eventName, eventInfo.color_rgb));
            }
        }
        print("== eventInfoBox eventInfos length: ${eventInfos.length}");

        // 2.数据加载
        // DateTime today = DateTime.parse("20250108");//DateTime.now();//.toString().split(" ")[0].replaceAll("-", "");
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


    void importRecordData(){
        
    }

    // List<DayRecord> getToFitDataIndex(){

    // }

    Future<String> exportRecordDataByDates(List<String> dates) async {
        Map<String, String> records = {};

        final dayRecordBox = await Hive.openBox<DayEventsRecord>("dayRecords");
        // final dates = dayRecordBox.keys;

        for (var date in dates){
            final dayRecord = dayRecordBox.get(date);
            if (dayRecord != null){
                records[date.toString()] = dayRecord.exportRecordAsString_onlyEvents();
            }
        }

        // records这个Map转换成json文件，以json格式返回
        return jsonEncode(records);
    }

    void refreshRenderDates(){
        
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

    void selectBlocks(Block block, UserProfileLoader userProfileLoader){
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
        
        Set<String> selectedBlocksEvent = List.generate(selectedBlocks.length, (i) => selectedBlocks[i].eventType).toSet();
        if (selectedBlocksEvent.length == 1){ selectedBlockEvent = selectedBlocksEvent.first; } else { selectedBlockEvent = ""; }
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

    void refreshRenderDates(UserProfileLoader userProfileLoader){
        // 刷新显示什么day的blocks


        notifyListeners();
    }

    void deleteEventInfo(EventInfo eventInfo, UserProfileLoader userProfileLoader){
        print("== deleteEventInfo: try to delete ${eventInfo.name}");
    }

    void editEventInfo(EventInfo eventInfo, UserProfileLoader userProfileLoader){
        print("== editEventInfo: try to edit ${eventInfo.name}");
    }

}