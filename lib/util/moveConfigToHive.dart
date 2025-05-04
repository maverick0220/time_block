import 'dart:io';
import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:time_block/database/DayEventsRecord.dart';
import 'package:time_block/database/EventInfoRecord.dart';
import 'package:time_block/database/EventRecord.dart';

void main() async {
  print("= moveConfigToHive =");
    Hive.init("hiveDB");
    Hive.registerAdapter(EventInfoRecordAdapter());
    final eventInfoBox = await Hive.openBox<EventInfoRecord>("eventInfo");
    
    File configFile = File('./lib/config.json');
    configFile.readAsString().then((contents) {
        if (contents == "") { return; }

        var jsonData = jsonDecode(contents); // 如果输入是空字符串，这玩意儿居然会直接报错……
        for(var event in jsonData["eventInfo"]){
          print("== event: ${event[0].runtimeType}, ${event[1].runtimeType}");
          EventInfoRecord record = EventInfoRecord(eventName: event[0], color_rgb: [event[1]["r"], event[1]["g"], event[1]["b"]], belongingToEvent: "");
          print("== ${event[0]}");
          try{
            eventInfoBox.put(event[0] as String, record);
          }catch (e){
            print("== error while put: $e");
          }
        }
    });


    var keys = await eventInfoBox.keys;
    print("== actual keys: ${keys}");
    for (var key in keys){
      EventInfoRecord? r = eventInfoBox.get(key);
          if (r != null){
            print("eventInfo found in box: ${r.eventName}");
          }else{
            print("== null key: ${key}");
          }
    }
}