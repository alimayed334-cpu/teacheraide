// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hive_student.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class HiveStudentAdapter extends TypeAdapter<HiveStudent> {
  @override
  final int typeId = 0;

  @override
  HiveStudent read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return HiveStudent(
      id: fields[0] as String,
      name: fields[1] as String,
      age: fields[2] as int,
      grade: fields[3] as String,
      classId: fields[4] as String?,
      phoneNumber: fields[5] as String?,
      parentPhone: fields[6] as String?,
      address: fields[7] as String?,
      imageUrl: fields[8] as String?,
      createdAt: fields[9] as DateTime,
      updatedAt: fields[10] as DateTime?,
      examIds: (fields[11] as List?)?.cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, HiveStudent obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.age)
      ..writeByte(3)
      ..write(obj.grade)
      ..writeByte(4)
      ..write(obj.classId)
      ..writeByte(5)
      ..write(obj.phoneNumber)
      ..writeByte(6)
      ..write(obj.parentPhone)
      ..writeByte(7)
      ..write(obj.address)
      ..writeByte(8)
      ..write(obj.imageUrl)
      ..writeByte(9)
      ..write(obj.createdAt)
      ..writeByte(10)
      ..write(obj.updatedAt)
      ..writeByte(11)
      ..write(obj.examIds);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HiveStudentAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
