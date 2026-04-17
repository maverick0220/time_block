// ignore_for_file: non_constant_identifier_names

import 'package:hive/hive.dart';
import 'package:time_block/database/EventRecord.dart';

part 'DayEventsRecord.g.dart';

@HiveType(typeId: 2)
class DayEventsRecord {

  DayEventsRecord({required this.date, required this.events});

  @HiveField(0)
  String date;

  @HiveField(1)
  List<EventRecord> events;

  void printRecord() {
    print("DayRecord $date: ${List.generate(events.length, (i) => events[i].eventInfo)}");
  }

  String exportRecordAsString(){
    return "[date: $date, events: ${List.generate(events.length, (i) => events[i].getEventAsString())}]";
  }

  String exportRecordAsString_onlyEvents(){
    return "${List.generate(events.length, (i) => events[i].getEventAsString())}";
  }

  List<List<dynamic>> exportRecordAsJson_onlyEvents(){
    return List.generate(events.length, (i) => events[i].getEventAsList());
  }
}