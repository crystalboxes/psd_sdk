import 'dart:typed_data';

import 'file.dart';

const _uint16Size = 2;
const _int16Size = 2;
const _uint32Size = 4;
const _int32Size = 4;
const _float64Size = 8;

class SyncFileReader {
  SyncFileReader(File file)
      : _file = file,
        _position = 0;

  final File _file;
  int _position;

  void setPosition(int position) {
    _position = position;
  }

  int readUint32([Endian endian = Endian.big]) {
    final value = _file.byteData.getUint32(_position, endian);
    _position += _uint32Size;
    return value;
  }

  int readUint16([Endian endian = Endian.big]) {
    final value = _file.byteData.getUint16(_position, endian);
    _position += _uint16Size;
    return value;
  }

  Uint8List readBytes(int number) {
    final list = _file.buffer.asUint8List(_position, number);
    _position += number;
    return list;
  }

  void skip(int count) {
    _position += count;
  }

  int getPosition() => _position;

  int readByte([Endian endian = Endian.big]) {
    final value = _file.byteData.getUint8(_position);
    _position += 1;
    return value;
  }

  int readInt16([Endian endian = Endian.big]) {
    final value = _file.byteData.getInt16(_position);
    _position += _int16Size;
    return value;
  }

  int readInt32([Endian endian = Endian.big]) {
    final value = _file.byteData.getInt32(_position);
    _position += _int32Size;
    return value;
  }

  double readFloat64() {
    final value = _file.byteData.getFloat64(_position);
    _position += _float64Size;
    return value;
  }
}
