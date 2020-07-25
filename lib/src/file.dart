import 'dart:typed_data';

class File {
  void setByteData(Uint8List bytes) {
    _uint8list = bytes;
    _byteData = _uint8list.buffer.asByteData();
  }

  Uint8List _uint8list;
  ByteData _byteData;

  ByteBuffer get buffer => _uint8list.buffer;

  ByteData get byteData => _byteData;

  int getSize() => _uint8list.length;
}
