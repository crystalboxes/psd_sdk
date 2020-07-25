import 'dart:typed_data';

abstract class NumDataType {}

class Uint8T extends NumDataType {}

class Int8T extends NumDataType {}

class Uint16T extends NumDataType {}

class Int16T extends NumDataType {}

class Uint32T extends NumDataType {}

class Int32T extends NumDataType {}

class Uint64T extends NumDataType {}

class Int64T extends NumDataType {}

class Float32T extends NumDataType {}

class Float64T extends NumDataType {}

bool isDouble<T extends NumDataType>() {
  switch (T) {
    case Float64T:
    case Float32T:
      return true;
    case Uint16T:
    case Int16T:
    case Int32T:
    case Uint32T:
    case Int64T:
    case Uint64T:
    case Uint8T:
    case Int8T:
      return false;
    default:
      throw Error();
  }
}

void setByteData<T extends NumDataType>(ByteData data, num value,
    [Endian endian]) {
  endian ??= Endian.host;
  switch (T) {
    case Float64T:
      data.setFloat64(0, value, endian);
      break;
    case Float32T:
      data.setFloat32(0, value, endian);
      break;
    case Uint16T:
      data.setUint16(0, value, endian);
      break;
    case Int16T:
      data.setInt16(0, value, endian);
      break;
    case Int32T:
      data.setInt32(0, value, endian);
      break;
    case Uint32T:
      data.setUint32(0, value, endian);
      break;
    case Int64T:
      data.setInt64(0, value, endian);
      break;
    case Uint64T:
      data.setUint64(0, value, endian);
      break;
    case Uint8T:
      data.setUint8(0, value);
      break;
    case Int8T:
      data.setInt8(0, value);
      break;
    default:
      throw Error();
      break;
  }
}

int sizeof<T extends NumDataType>() {
  switch (T) {
    case Uint16T:
    case Int16T:
      return 2;
    case Float32T:
    case Int32T:
    case Uint32T:
      return 4;
    case Float64T:
    case Int64T:
    case Uint64T:
      return 8;
    case Uint8T:
    case Int8T:
      return 1;
    default:
      throw Error();
  }
}

TypedData getTypedList<T extends NumDataType>(Uint8List list) {
  switch (T) {
    case Uint16T:
      return list.buffer.asUint16List();
    case Int16T:
      return list.buffer.asInt16List();
    case Float32T:
      return list.buffer.asFloat32List();
    case Int32T:
      return list.buffer.asInt32List();
    case Uint32T:
      return list.buffer.asUint32List();
    case Float64T:
      return list.buffer.asFloat64List();
    case Int64T:
      return list.buffer.asInt64List();
    case Uint64T:
      return list.buffer.asUint64List();
    case Uint8T:
      return list.buffer.asUint8List();
    case Int8T:
      return list.buffer.asInt8List();
    default:
      throw Error();
  }
}

num getElemHostEndian<T extends NumDataType>(
    ByteData byteData, int byteOffset) {
  return getElemEndian<T>(byteData, byteOffset, Endian.host);
}

num nativeToBigEndian<T extends NumDataType>(num value) {
  var bd = ByteData(sizeof<T>());
  setByteData<T>(bd, value);
  return getElemEndian<T>(bd, 0, Endian.big);
}

num getElemEndian<T extends NumDataType>(
    ByteData byteData, int byteOffset, Endian endian) {
  switch (T) {
    case Uint16T:
      return byteData.getUint16(byteOffset, endian);
    case Int16T:
      return byteData.getInt16(byteOffset, endian);
    case Float32T:
      return byteData.getFloat32(byteOffset, endian);
    case Int32T:
      return byteData.getInt32(byteOffset, endian);
    case Uint32T:
      return byteData.getUint32(byteOffset, endian);
    case Float64T:
      return byteData.getFloat64(byteOffset, endian);
    case Int64T:
      return byteData.getInt64(byteOffset, endian);
    case Uint64T:
      return byteData.getUint64(byteOffset, endian);
    case Uint8T:
      return byteData.getUint8(byteOffset);
    case Int8T:
      return byteData.getInt8(byteOffset);
    default:
      throw Error();
  }
}
