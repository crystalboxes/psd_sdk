import 'dart:typed_data';

import 'file.dart';

class SyncFileWriter {
  SyncFileWriter(this.file);

  /// Writes \a count bytes from \a buffer synchronously, incrementing the internal write position.
  void Write<T>(T buffer, int count) {
    if (buffer is ByteBuffer) {
      bytes.addAll(buffer.asUint8List());
    } else {
      throw Error();
    }
  }

  /// Returns the internal write position.
  int GetPosition() {
    return m_position;
  }

  int m_position;

  List<int> bytes;
  File file;
}
