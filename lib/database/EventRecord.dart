import 'package:hive/hive.dart';

part 'EventRecord.g.dart';

@HiveType(typeId: 1)
class EventRecord {

  EventRecord({required this.startIndex, required this.endIndex, required this.eventInfo});

  // EventRecord(List<dynamic> rawEvent){
  //   startIndex = rawEvent[0];
  //   endIndex = rawEvent[1];
  //   eventInfo = rawEvent[2];
  //   type = rawEvent[3];
  //   comment = rawEvent[4];
  // }

  @HiveField(0)
  int startIndex; // 从哪儿开始。是个闭区间

  @HiveField(1)
  int endIndex; // 到哪儿结束。是个闭区间

  @HiveField(2)
  String eventInfo; // 这个事儿是啥

  @HiveField(3)
  String type = ""; // 这个事儿是啥

  @HiveField(4)
  String comment = ""; // 这个事儿是啥

  int getEventBlockCount(){
    return endIndex - startIndex + 1; // 因为肯定是同一个DayRecord里面的，所以这个不考虑跨没跨天
  }

  String getEventAsString(){
    return '[$startIndex, $endIndex, "$eventInfo", "$type", "$comment"]';
  }

  List<dynamic> getEventAsList(){
    return [startIndex, endIndex, eventInfo, type, comment];
  }
}