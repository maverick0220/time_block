// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'EventInfoRecord.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class EventInfoRecordAdapter extends TypeAdapter<EventInfoRecord> {
  @override
  final int typeId = 0;

  @override
  EventInfoRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return EventInfoRecord(
      eventName: fields[0] as String,
      color_rgb: (fields[1] as List).cast<int>(),
      belongingToEvent: fields[2] as String,
    );
  }

  @override
  void write(BinaryWriter writer, EventInfoRecord obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.eventName)
      ..writeByte(1)
      ..write(obj.color_rgb)
      ..writeByte(2)
      ..write(obj.belongingToEvent);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventInfoRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
