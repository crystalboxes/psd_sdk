import 'dart:io';
import 'dart:typed_data';

import 'package:psd_sdk/src/log.dart';

import 'allocator.dart';
import 'file.dart' as psd;

class nativeFile extends psd.File {
  nativeFile(Allocator allocator) : super(allocator);

  File file;

  @override
  bool openRead(String filename) {
    file = File(filename);

    try {
      _uint8list = file.readAsBytesSync();
      _byteData = _uint8list.buffer.asByteData();
    } catch (e) {
      psdError(['NativeFile', 'Cannot obtain handle for file $filename.']);
      return false;
    }

    return true;
  }

  Uint8List _uint8list;
  ByteData _byteData;

  @override
  ByteBuffer get buffer => _uint8list.buffer;

  @override
  ByteData get byteData => _byteData;

  @override
  int getSize() => _uint8list.length;

  @override
  void close() {}
}
