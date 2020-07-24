import 'dart:typed_data';

abstract class File {
  ByteBuffer get buffer;
  ByteData get byteData;

  bool openRead(String filename);
  void close();

  int getSize();
}
