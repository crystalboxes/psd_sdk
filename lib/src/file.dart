import 'dart:typed_data';

class File {
  bool setByteData(Uint8List bytes) {
    try {
      _uint8list = bytes;
      _byteData = _uint8list.buffer.asByteData();
    } catch (e) {
      return false;
    }

    return true;
  }

  Uint8List _uint8list;
  ByteData _byteData;

  ByteBuffer get buffer => _uint8list.buffer;

  ByteData get byteData => _byteData;

  int getSize() => _uint8list.length;

  void close() {}
}
