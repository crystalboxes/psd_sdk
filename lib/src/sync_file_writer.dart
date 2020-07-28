import 'dart:typed_data';

import 'file.dart';

class SyncFileWriter {
  SyncFileWriter(File file) : _file = file;

  /// Writes count bytes from buffer synchronously, incrementing the internal write position.
  void write<T>(T buffer, [int count]) {
    if (buffer is ByteBuffer) {
      count ??= buffer.lengthInBytes;
      _bytes.addAll(buffer.asUint8List().sublist(0, count));
    } else if (buffer is ByteData && count != null) {
      for (var x = 0; x < count; x++) {
        _bytes.add(buffer.getUint8(x));
      }
    } else if (buffer is Uint8List) {
      count ??= buffer.length;
      _bytes.addAll(buffer.sublist(0, count));
    } else if (buffer is String) {
      count ??= buffer.length;
      var buf = Uint8List(count);
      for (var x = 0; x < count; x++) {
        if (x >= buffer.length) {
          buf[x] = 0;
        } else {
          buf[x] = buffer.codeUnitAt(x);
        }
      }
      _bytes.addAll(buf);
    } else {
      throw Error();
    }
  }

  /// Returns the internal write position.
  int getPosition() {
    return _position;
  }

  void save() {
    _file.setByteData(Uint8List.fromList(_bytes));
  }

  int get _position => _bytes.length;
  final List<int> _bytes = [];
  final File _file;
}
