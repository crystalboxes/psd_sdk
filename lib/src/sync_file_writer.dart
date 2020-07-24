import 'dart:typed_data';

import 'file.dart';

class SyncFileWriter {
  SyncFileWriter(this.file);

  /// Writes \a count bytes from \a buffer synchronously, incrementing the internal write position.
  void Write<T>(T buffer, [int count]) {
    if (buffer is ByteBuffer) {
      count ??= buffer.lengthInBytes;
      _bytes.addAll(buffer.asUint8List());
    } else if (buffer is ByteData && count != null) {
      for (var x = 0; x < count; x++) {
        _bytes.add(buffer.getUint8(x));
      }
    } else if (buffer is Uint8List) {
      count ??= buffer.length;
      _bytes.addAll(buffer);
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
    return m_position;
  }

  int get m_position => _bytes.length;

  List<int> _bytes = [];
  File file;
}
