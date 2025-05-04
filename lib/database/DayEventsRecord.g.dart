// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'DayEventsRecord.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DayEventsRecordAdapter extends TypeAdapter<DayEventsRecord> {
  @override
  final int typeId = 2;

  @override
  DayEventsRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DayEventsRecord(
      date: fields[0] as String,
      events: (fields[1] as List).cast<EventRecord>(),
    );
  }

  @override
  void write(BinaryWriter writer, DayEventsRecord obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.date)
      ..writeByte(1)
      ..write(obj.events);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DayEventsRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
