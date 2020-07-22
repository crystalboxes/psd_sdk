import 'dart:typed_data';

import 'allocator.dart';

class MallocAllocator implements Allocator {
  @override
  dynamic allocate(int size, int alignment) {
    return ByteData(size);
  }

  @override
  void free(dynamic ptr) {}
}
