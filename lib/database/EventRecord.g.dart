// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'EventRecord.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class EventRecordAdapter extends TypeAdapter<EventRecord> {
  @override
  final int typeId = 1;

  @override
  EventRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return EventRecord(
      startIndex: fields[0] as int,
      endIndex: fields[1] as int,
      eventInfo: fields[2] as String,
    )
      ..type = fields[3] as String
      ..comment = fields[4] as String;
  }

  @override
  void write(BinaryWriter writer, EventRecord obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.startIndex)
      ..writeByte(1)
      ..write(obj.endIndex)
      ..writeByte(2)
      ..write(obj.eventInfo)
      ..writeByte(3)
      ..write(obj.type)
      ..writeByte(4)
      ..write(obj.comment);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
