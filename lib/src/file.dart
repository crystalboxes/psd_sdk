import 'dart:typed_data';

import 'allocator.dart';

abstract class File {
  Allocator allocator;
  File(this.allocator);

  ByteBuffer get buffer;
  ByteData get byteData;

  bool openRead(String filename);
  void close();

  int getSize();
}
