import 'dart:typed_data';

import 'decompress_rle.dart';
import 'log.dart';

import 'compression_type.dart';
import 'data_types.dart';
import 'document.dart';
import 'file.dart';
import 'image_data_section.dart';
import 'sync_file_reader.dart';

/// Parses the image data section in the document, and returns a newly created instance.
/// It is valid to parse different sections of a document (e.g. using parseImageResourcesSection, parseImageDataSection,
/// or parseLayerMaskSection) in parallel from different threads.
ImageDataSection parseImageDataSection(Document document, File file) {
  // this is the merged image. it is only stored if "maximize compatibility" is turned on when saving a PSD file.
  // image data is stored in planar order: first red data, then green data, and so on.
  // each plane is stored in scan-line order, with no padding bytes.

  // 8-bit values are stored directly.
  // 16-bit values are stored directly, even though they are stored as 15-bit+1 integers in the range 0...32768
  // internally in Photoshop, see https://forums.adobe.com/message/3472269
  // 32-bit values are stored directly as IEEE 32-bit floats.
  var section = document.imageDataSection;
  if (section.length == 0) {
    psdError(['PSD', 'Document does not contain an image data section.']);
    return null;
  }

  var reader = SyncFileReader(file);
  reader.setPosition(section.offset);

  var imageData = ImageDataSection();
  final width = document.width;
  final height = document.height;
  final bitsPerChannel = document.bitsPerChannel;
  final channelCount = document.channelCount;
  final compressionType = reader.readUint16();
  if (compressionType == CompressionType.RAW) {
    imageData = _readImageDataSectionRaw(
        reader, width, height, channelCount, bitsPerChannel ~/ 8);
  } else if (compressionType == CompressionType.RLE) {
    imageData = _readImageDataSectionRLE(
        reader, width, height, channelCount, bitsPerChannel ~/ 8);
  } else {
    psdError(['ImageData', 'Unhandled compression type ${compressionType}.']);
  }

  if (imageData == null) {
    return null;
  }

  if (imageData.images == null) {
    return imageData;
  }

  // endian-convert the data
  switch (bitsPerChannel) {
    case 8:
      _endianConvert<Uint8T>(imageData.images, width, height, channelCount);
      break;

    case 16:
      _endianConvert<Uint16T>(imageData.images, width, height, channelCount);
      break;

    case 32:
      _endianConvert<Float32T>(imageData.images, width, height, channelCount);
      break;

    default:
      psdError(['ImageData', 'Unhandled bits per channel: $bitsPerChannel.']);
      break;
  }

  return imageData;
}

ImageDataSection _readImageDataSectionRaw(SyncFileReader reader, int width,
    int height, int channelCount, int bytesPerPixel) {
  final size = width * height;
  if (size == 0) {
    return null;
  }

  var imageData = ImageDataSection();
  imageData.images = List(channelCount);

  // read data for all channels at once
  for (var i = 0; i < channelCount; ++i) {
    imageData.images[i] = PlanarImage();
    imageData.images[i].data = reader.readBytes(size * bytesPerPixel);
  }

  return imageData;
}

ImageDataSection _readImageDataSectionRLE(SyncFileReader reader, int width,
    int height, int channelCount, int bytesPerPixel) {
  // the RLE-compressed data is preceded by a 2-byte data count for each scan line, per channel.
  // we store the size of the RLE data per channel, and assume a maximum of 256 channels.
  assert(channelCount < 256,
      'Image data section has too many channels ($channelCount).');
  var channelSize = List<int>(256);
  var totalSize = 0;
  for (var i = 0; i < channelCount; ++i) {
    var size = 0;
    for (var j = 0; j < height; ++j) {
      final dataCount = reader.readUint16();
      size += dataCount;
    }

    channelSize[i] = size;
    totalSize += size;
  }

  if (totalSize == 0) {
    return null;
  }

  final size = width * height;
  var imageData = ImageDataSection();
  imageData.images = List(channelCount);

  for (var i = 0; i < channelCount; ++i) {
    imageData.images[i] = PlanarImage();
    imageData.images[i].data = Uint8List(size * bytesPerPixel);

    // read RLE data, and uncompress into planar buffer
    final rleSize = channelSize[i];
    var rleData = reader.readBytes(rleSize);

    decompressRle(rleData, rleSize, imageData.images[i].data,
        width * height * bytesPerPixel);
  }

  return imageData;
}

void _endianConvert<T extends NumDataType>(
    List<PlanarImage> images, int width, int height, int channelCount) {
  final size = width * height;
  for (var i = 0; i < channelCount; ++i) {
    var byteData = images[i].data.buffer.asByteData();

    final sizeofT = sizeof<T>();
    var copied = Uint8List(size * sizeofT);
    var data = getTypedList<T>(copied) as List;

    for (var j = 0; j < size; ++j) {
      var pos = sizeofT * j;
      data[j] = getElemHostEndian<T>(byteData, pos);
    }
    images[i].data = copied;
  }
}
