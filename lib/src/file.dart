import 'dart:typed_data';

class File {
  Uint8List get bytes => _uint8list;
  ByteBuffer get buffer => _uint8list.buffer;
  ByteData get byteData => _byteData;

  void setByteData(Uint8List bytes) {
    _uint8list = bytes;
    _byteData = _uint8list.buffer.asByteData();
  }

  int getSize() => _uint8list.length;

  Uint8List _uint8list;
  ByteData _byteData;
}
