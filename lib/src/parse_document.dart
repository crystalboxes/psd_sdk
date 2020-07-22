import 'dart:typed_data';

import 'package:psd_sdk/src/key.dart';
import 'package:psd_sdk/src/log.dart';
import 'package:psd_sdk/src/sync_file_reader.dart';

import 'allocator.dart';
import 'document.dart';
import 'file.dart';

Document createDocument(File file, Allocator allocator) {
  final reader = SyncFileReader(file);
  reader.setPosition(0);

  // check signature, must be "8BPS"
  {
    final signature = reader.readUint32(Endian.big);
    if (signature != keyValue('8BPS')) {
      psdError([
        'PsdExtract',
        'File seems to be corrupt, signature does not match "8BPS".'
      ]);
      return null;
    }
  }

  // check version, must be 1
  {
    final version = reader.readUint16(Endian.big);
    if (version != 1) {
      psdError([
        'PsdExtract',
        'File seems to be corrupt, version does not match 1.'
      ]);
      return null;
    }
  }

  // check reserved bytes, must be zero
  {
    final zeroes = reader.readBytes(6);

    if (!zeroes
        .map((e) => e == 0)
        .reduce((value, element) => value && element)) {
      psdError([
        'PsdExtract',
        'File seems to be corrupt, reserved bytes are not zero.'
      ]);
      return null;
    }
  }

  final document = Document();
}

void destroyDocument(Document document, Allocator allocator) {}
