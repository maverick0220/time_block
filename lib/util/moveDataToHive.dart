import 'dart:io';
import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:time_block/database/DayEventsRecord.dart';
import 'package:time_block/database/EventInfoRecord.dart';
import 'package:time_block/database/EventRecord.dart';

void main() async {
    print("= moveDataToHive =");
    Hive.init("hiveDB");
    Hive.registerAdapter(EventRecordAdapter());
    Hive.registerAdapter(DayEventsRecordAdapter());
    // final eventInfosBox = await Hive.openBox<EventRecord>('events');
    final dayRecordBox = await Hive.openBox<DayEventsRecord>("dayRecords");
    
    File dataFile = File('./2025.json');
    List<String> dates = [];
    dataFile.readAsString().then((contents) {
        if (contents == "") { return; }
        var jsonData = jsonDecode(contents); // 如果输入是空字符串，这玩意儿居然会直接报错……
        print("== 0 dateKeys: ${jsonData.keys.toList()}");
        for(var date in jsonData.keys.toList()){
            // print("== 1moveDataToHive: ${date}, ${jsonData[date]}");
            dates.add(date);
            List<EventRecord> events = List.generate(jsonData[date].length, (i) => EventRecord(startIndex: jsonData[date][i][0], endIndex: jsonData[date][i][1], eventInfo: jsonData[date][i][2]));
            DayEventsRecord record = DayEventsRecord(date: date, events: events);
            try{
              dayRecordBox.put(date, record);
            }catch (e){
              print("== error while put: $e");
            }
            
        }
    });


    var keys = await dayRecordBox.keys;
    print("== actual keys:${keys}");
    for (var key in keys){
      DayEventsRecord? r = dayRecordBox.get(key);
          if (r != null){
            r.printRecord();
          }else{
            print("== null key: ${key}");
          }
    }





    
    

}