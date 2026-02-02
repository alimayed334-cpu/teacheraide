// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hive_exam.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class HiveExamAdapter extends TypeAdapter<HiveExam> {
  @override
  final int typeId = 1;

  @override
  HiveExam read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return HiveExam(
      id: fields[0] as String,
      studentId: fields[1] as String,
      subject: fields[2] as String,
      score: fields[3] as double,
      maxScore: fields[4] as double,
      date: fields[5] as DateTime,
      notes: fields[6] as String?,
      examType: fields[7] as String?,
      createdAt: fields[8] as DateTime,
      updatedAt: fields[9] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, HiveExam obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.studentId)
      ..writeByte(2)
      ..write(obj.subject)
      ..writeByte(3)
      ..write(obj.score)
      ..writeByte(4)
      ..write(obj.maxScore)
      ..writeByte(5)
      ..write(obj.date)
      ..writeByte(6)
      ..write(obj.notes)
      ..writeByte(7)
      ..write(obj.examType)
      ..writeByte(8)
      ..write(obj.createdAt)
      ..writeByte(9)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HiveExamAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
