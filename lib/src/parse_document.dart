import 'package:psd_sdk/src/key.dart';
import 'package:psd_sdk/src/log.dart';
import 'package:psd_sdk/src/sync_file_reader.dart';

import 'document.dart';
import 'file.dart';

Document createDocument(File file) {
  final reader = SyncFileReader(file);
  reader.setPosition(0);

  // check signature, must be "8BPS"
  {
    final signature = reader.readUint32();
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
    final version = reader.readUint16();
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

  // read in the number of channels.
  // this is the number of channels contained in the document for all layers, including any alpha channels.
  // e.g. for an RGB document with 3 alpha channels, this would be 3 (RGB) + 3 (Alpha) = 6 channels.
  // however, note that individual layers can have extra channels for transparency masks, vector masks, and user masks.
  // this is different from layer to layer.
  document.channelCount = reader.readUint16();

  // read rest of header information
  document.height = reader.readUint32();
  document.width = reader.readUint32();
  document.bitsPerChannel = reader.readUint16();
  document.colorMode = reader.readUint16();

  // grab offsets into different sections
  {
    final length = reader.readUint32();

    document.colorModeDataSection.offset = reader.getPosition();
    document.colorModeDataSection.length = length;

    reader.skip(length);
  }
  {
    final length = reader.readUint32();

    document.imageResourcesSection.offset = reader.getPosition();
    document.imageResourcesSection.length = length;

    reader.skip(length);
  }
  {
    final length = reader.readUint32();

    document.layerMaskInfoSection.offset = reader.getPosition();
    document.layerMaskInfoSection.length = length;

    reader.skip(length);
  }
  {
    // note that the image data section does NOT store its length in the first 4 bytes
    document.imageDataSection.offset = reader.getPosition();
    document.imageDataSection.length = file.getSize() - reader.getPosition();
  }

  return document;
}
