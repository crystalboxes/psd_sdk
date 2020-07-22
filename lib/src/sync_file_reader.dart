import 'dart:typed_data';

import 'file.dart';

const _uint16Size = 2;
const _uint32Size = 4;

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
}
