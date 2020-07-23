import 'dart:typed_data';

abstract class NumDataType {}

class uint8_t extends NumDataType {}

class int8_t extends NumDataType {}

class uint16_t extends NumDataType {}

class int16_t extends NumDataType {}

class uint32_t extends NumDataType {}

class int32_t extends NumDataType {}

class uint64_t extends NumDataType {}

class int64_t extends NumDataType {}

class float32_t extends NumDataType {}

class float64_t extends NumDataType {}

bool isDouble<T extends NumDataType>() {
  switch (T) {
    case float64_t:
    case float32_t:
      return true;
    case uint16_t:
    case int16_t:
    case int32_t:
    case uint32_t:
    case int64_t:
    case uint64_t:
    case uint8_t:
    case int8_t:
    default:
      return false;
  }
}

void setByteData<T extends NumDataType>(ByteData data, num value) {
  switch (T) {
    case float64_t:
      data.setFloat64(0, value, Endian.host);
      break;
    case float32_t:
      data.setFloat32(0, value, Endian.host);
      break;
    case uint16_t:
      data.setUint16(0, value, Endian.host);
      break;
    case int16_t:
      data.setInt16(0, value, Endian.host);
      break;
    case int32_t:
      data.setInt32(0, value, Endian.host);
      break;
    case uint32_t:
      data.setUint32(0, value, Endian.host);
      break;
    case int64_t:
      data.setInt64(0, value, Endian.host);
      break;
    case uint64_t:
      data.setUint64(0, value, Endian.host);
      break;
    case uint8_t:
      data.setUint8(0, value);
      break;
    case int8_t:
      data.setInt8(0, value);
      break;
    default:
      break;
  }
}

int sizeof<T extends NumDataType>() {
  switch (T) {
    case uint16_t:
    case int16_t:
      return 2;
    case float32_t:
    case int32_t:
    case uint32_t:
      return 4;
    case float64_t:
    case int64_t:
    case uint64_t:
      return 8;
    case uint8_t:
    case int8_t:
    default:
      return 1;
  }
}

void printType<T extends NumDataType>() {
  switch (T) {
    case uint16_t:
      print('uint16_t');
      break;
    case int16_t:
      print('int16_t');
      break;
    case float32_t:
      print('float32_t');
      break;
    case int32_t:
      print('int32_t');
      break;
    case uint32_t:
      print('uint32_t');
      break;
    case float64_t:
      print('float64_t');
      break;
    case int64_t:
      print('int64_t');
      break;
    case uint64_t:
      print('uint64_t');
      break;
    case uint8_t:
      print('uint8_t');
      break;
    case int8_t:
    default:
      print('int8_t');
      break;
  }
}

TypedData getTypedList<T extends NumDataType>(Uint8List list) {
  switch (T) {
    case uint16_t:
      return list.buffer.asUint16List();
    case int16_t:
      return list.buffer.asInt16List();
    case float32_t:
      return list.buffer.asFloat32List();
    case int32_t:
      return list.buffer.asInt32List();
    case uint32_t:
      return list.buffer.asUint32List();
    case float64_t:
      return list.buffer.asFloat64List();
    case int64_t:
      return list.buffer.asInt64List();
    case uint64_t:
      return list.buffer.asUint64List();
    case uint8_t:
      return list.buffer.asUint8List();
    case int8_t:
    default:
      return list.buffer.asInt8List();
  }
}

num getElemInHostEndian<T extends NumDataType>(
    ByteData byteData, int byteOffset) {
  switch (T) {
    case uint16_t:
      return byteData.getUint16(byteOffset, Endian.host);
    case int16_t:
      return byteData.getInt16(byteOffset, Endian.host);
    case float32_t:
      return byteData.getFloat32(byteOffset, Endian.host);
    case int32_t:
      return byteData.getInt32(byteOffset, Endian.host);
    case uint32_t:
      return byteData.getUint32(byteOffset, Endian.host);
    case float64_t:
      return byteData.getFloat64(byteOffset, Endian.host);
    case int64_t:
      return byteData.getInt64(byteOffset, Endian.host);
    case uint64_t:
      return byteData.getUint64(byteOffset, Endian.host);
    case uint8_t:
      return byteData.getUint8(byteOffset);
    case int8_t:
    default:
      return byteData.getInt8(byteOffset);
  }
}
