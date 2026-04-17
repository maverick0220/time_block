import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

part 'EventInfoRecord.g.dart';

@HiveType(typeId: 0)
class EventInfoRecord {

  EventInfoRecord({required this.eventName, required this.color_rgb, required this.belongingToEvent});

  Color getColor() {
    if (color_rgb.length < 3){ return Colors.black; }
    return Color.fromRGBO(color_rgb[0], color_rgb[1], color_rgb[2], 1.0);
  }
  @HiveField(0)
  String eventName; // 这个事儿是啥

  @HiveField(1)
  List<int> color_rgb; // {"r": 0, "g": 204, "b": 102}

  @HiveField(2)
  String belongingToEvent; // 默认是空值

}