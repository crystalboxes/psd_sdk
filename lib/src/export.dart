import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:psd_sdk/psd_sdk.dart';
import 'package:psd_sdk/src/export_layer.dart';
import 'package:psd_sdk/src/sync_file_writer.dart';

import 'bit_util.dart';
import 'compression_type.dart';
import 'data_types.dart';
import 'decompress_rle.dart';
import 'export_channel.dart';
import 'export_color_mode.dart';
import 'export_document.dart';
import 'export_metadata_attribute.dart';
import 'image_resource_type.dart';
import 'key.dart';

ExportDocument createExportDocument(
    int canvasWidth, int canvasHeight, int bitsPerChannel, int colorMode) {
  var document = ExportDocument();

  document.width = canvasWidth;
  document.height = canvasHeight;
  document.bitsPerChannel = bitsPerChannel;
  document.colorMode = colorMode;

  document.attributes = [];
  document.layers = [];

  document.alphaChannels = [];

  document.iccProfile;

  document.exifData;

  document.thumbnail;

  return document;
}

int addMetaData(ExportDocument document, String name, String value) {
  final index = document.attributeCount;
  document.attributes.add(ExportMetaDataAttribute());
  _updateMetaData(document, index, name, value);

  return index;
}

String _createString(String str) {
  return str;
}

void _updateMetaData(
    ExportDocument document, int index, String name, String value) {
  var attribute = document.attributes[index];
  attribute.name = _createString(name);
  attribute.value = _createString(value);
}

int addLayer(ExportDocument document, String name) {
  final index = document.layerCount;
  document.layers.add(ExportLayer());

  var layer = document.layers[index];
  layer.name = _createString(name);
  return index;
}

int _getChannelIndex(int channel) {
  switch (channel) {
    case ExportChannel.GRAY:
      return 0;

    case ExportChannel.RED:
      return 0;

    case ExportChannel.GREEN:
      return 1;

    case ExportChannel.BLUE:
      return 2;

    case ExportChannel.ALPHA:
      return 3;

    default:
      return 0;
  }
}

void updateLayer<T extends TypedData>(
    ExportDocument document,
    int layerIndex,
    int channel,
    int left,
    int top,
    int right,
    int bottom,
    TypedData planarData,
    int compression) {
  if (planarData is Uint8List) {
    _updateLayerImpl<Uint8T>(document, layerIndex, channel, left, top, right,
        bottom, planarData, compression);
  } else if (planarData is Uint16List) {
    _updateLayerImpl<Uint16T>(document, layerIndex, channel, left, top, right,
        bottom, planarData, compression);
  } else if (planarData is Float32List) {
    _updateLayerImpl<Float32T>(document, layerIndex, channel, left, top, right,
        bottom, planarData, compression);
  } else {
    print('not supported');
  }
}

void _updateLayerImpl<T extends NumDataType>(
    ExportDocument document,
    int layerIndex,
    int channel,
    int left,
    int top,
    int right,
    int bottom,
    TypedData planarData,
    int compression) {
  if (document.colorMode == ExportColorMode.GRAYSCALE) {
    assert((channel == ExportChannel.GRAY) || (channel == ExportChannel.ALPHA),
        'Wrong channel for this color mode.');
  } else if (document.colorMode == ExportColorMode.RGB) {
    assert(
        (channel == ExportChannel.RED) ||
            (channel == ExportChannel.GREEN) ||
            (channel == ExportChannel.BLUE) ||
            (channel == ExportChannel.ALPHA),
        'Wrong channel for this color mode.');
  }

  final layer = document.layers[layerIndex];
  final channelIndex = _getChannelIndex(channel);

  // prepare new data
  layer.top = top;
  layer.left = left;
  layer.bottom = bottom;
  layer.right = right;
  layer.channelCompression[channelIndex] = (compression);

  assert(right >= left, 'Invalid layer bounds.');
  assert(bottom >= top, 'Invalid layer bounds.');
  final width = (right - left);
  final height = (bottom - top);

  if (compression == CompressionType.RAW) {
    // raw data, copy directly and convert to big endian
    _createDataRaw<T>(layer, channelIndex, planarData, width, height);
  } else if (compression == CompressionType.RLE) {
    // compress with RLE
    CreateDataRLE<T>(layer, channelIndex, planarData, width, height);
  } else if (compression == CompressionType.ZIP) {
    // compress with ZIP
    // note that this has a template specialization for 32-bit float data that forwards to ZipWithPrediction.
    if (T == Float32T) {
      _createDataZipPredictionF32(
          layer, channelIndex, planarData, width, height);
    } else {
      _createDataZip<T>(layer, channelIndex, planarData, width, height);
    }
  } else if (compression == CompressionType.ZIP_WITH_PREDICTION) {
    if (T == Float32T) {
      _createDataZipPredictionF32(
          layer, channelIndex, planarData, width, height);
    } else {
      // delta-encode, then compress with ZIP
      _createDataZipPrediction<T>(
          layer, channelIndex, planarData, width, height);
    }
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
void _createDataZipPrediction<T extends NumDataType>(ExportLayer layer,
    int channelIndex, TypedData planarData, int width, int height) {
  final size = width * height;

  var deltaData = getTypedList<T>(Uint8List(size * sizeof<T>())) as List;
  var allocation = deltaData;

  var deltaDataPos = 0;
  var planarDataPos = 0;
  for (var y = 0; y < height; ++y) {
    deltaData[deltaDataPos++] = (planarData as List)[planarDataPos++];
    for (var x = 1; x < width; ++x) {
      final previous = (planarData as List)[planarDataPos - 1];
      final current = (planarData as List)[planarDataPos + 0];
      final value = current - previous;

      deltaData[deltaDataPos++] = (value & (T is Uint8T ? 0xFF : 0xFFFF));
      ++planarDataPos;
    }
  }

  // convert to big endian
  for (var i = 0; i < size; ++i) {
    allocation[i] = nativeToBigEndian<T>(allocation[i]);
  }

  Uint8List zipData = ZLibEncoder().encode(allocation);

  layer.channelData[channelIndex] = zipData;
  layer.channelSize[channelIndex] = zipData.length;
}

void _createDataZipPredictionF32(ExportLayer layer, int channelIndex,
    Float32List planarData, int width, int height) {
  final size = width * height;

  // float data is first converted into planar data to allow for better compression.
  // this is done row by row, so if the bytes of the floats in a row consist of "1234123412341234" they will be turned into "1111222233334444".
  // the data is also converted to big-endian in the same loop.
  var bigEndianPlanarData = Uint8List(size * sizeof<Float32T>());
  for (var y = 0; y < height; ++y) {
    for (var x = 0; x < width; ++x) {
      var asBytes = ByteData(sizeof<Float32T>());
      asBytes.setFloat32(0, planarData[y * width + x], Endian.host);
      bigEndianPlanarData[y * width * sizeof<Float32T>() + x + width * 0] =
          asBytes.getUint8(3);
      bigEndianPlanarData[y * width * sizeof<Float32T>() + x + width * 1] =
          asBytes.getUint8(2);
      bigEndianPlanarData[y * width * sizeof<Float32T>() + x + width * 2] =
          asBytes.getUint8(1);
      bigEndianPlanarData[y * width * sizeof<Float32T>() + x + width * 3] =
          asBytes.getUint8(0);
    }
  }

  // now delta encode the individual bytes row by row
  var deltaData = Uint8List(size * sizeof<Float32T>());
  for (var y = 0; y < height; ++y) {
    deltaData[y * width * sizeof<Float32T>()] =
        bigEndianPlanarData[y * width * sizeof<Float32T>()];
    for (var x = 1; x < width * 4; ++x) {
      final previous =
          bigEndianPlanarData[y * width * sizeof<Float32T>() + x - 1];
      final current = bigEndianPlanarData[y * width * sizeof<Float32T>() + x];
      final value = current - previous;

      deltaData[y * width * sizeof<Float32T>() + x] = (value & 0xFF);
    }
  }

  Uint8List zipData = ZLibEncoder().encode(deltaData);

  layer.channelData[channelIndex] = zipData;
  layer.channelSize[channelIndex] = zipData.length;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
void _createDataZip<T extends NumDataType>(ExportLayer layer, int channelIndex,
    TypedData planarData, int width, int height) {
  final size = width * height;

  var bigEndianData = getTypedList<T>(Uint8List(size * sizeof<T>())) as List;

  for (var i = 0; i < size; ++i) {
    bigEndianData[i] = nativeToBigEndian<T>((planarData as List)[i]);
  }

  Uint8List zipData =
      ZLibEncoder().encode((bigEndianData as TypedData).buffer.asUint8List());

  layer.channelData[channelIndex] = zipData;
  layer.channelSize[channelIndex] = zipData.length;
}

void _createDataRaw<T extends NumDataType>(ExportLayer layer, int channelIndex,
    TypedData planarData, int width, int height) {
  final size = width * height;

  final elemSize = sizeof<T>();
  final bigEndianDataList = Uint8List(size * elemSize);
  final bigEndianData = getTypedList<T>(bigEndianDataList) as List;
  final srcByteData = planarData.buffer.asByteData();

  for (var i = 0; i < size; ++i) {
    bigEndianData[i] = getElemEndian<T>(srcByteData, i * elemSize, Endian.big);
  }

  layer.channelData[channelIndex] = bigEndianDataList;
  layer.channelSize[channelIndex] = size * elemSize;
}

void CreateDataRLE<T extends NumDataType>(ExportLayer layer, int channelIndex,
    TypedData planarData, int width, int height) {
  final size = width * height;

  // each row needs two additional bytes for storing the size of the row's data.
  // we pack the data row by row, and copy it into the final buffer.
  var rleData = Uint8List(height * sizeof<Uint16T>() + size * sizeof<T>() * 2);

  var rleRowData = Uint8List(width * sizeof<T>() * 2);
  var bigEndianRowData = getTypedList<T>(Uint8List(width * sizeof<T>()));

  var offset = 0;
  for (var y = 0; y < height; ++y) {
    for (var x = 0; x < width; ++x) {
      (bigEndianRowData as List)[x] = getElemEndian<T>(
          planarData.buffer.asByteData(),
          (y * width + x) * sizeof<T>(),
          Endian.big);
    }

    var compressedSize = compressRle(
        bigEndianRowData.buffer.asUint8List(), rleRowData, width * sizeof<T>());
    assert(compressedSize <= width * sizeof<T>() * 2,
        'RLE compressed data doesn\'t fit into provided buffer.');

    // copy 2 bytes row size, and copy RLE data
    rleData.buffer
        .asByteData()
        .setUint16(y * sizeof<Uint16T>(), compressedSize, Endian.big);

    for (var i = 0; i < compressedSize; i++) {
      rleData[i + height * sizeof<Uint16T>() + offset] = rleRowData[i];
    }

    offset += compressedSize;
  }

  layer.channelData[channelIndex] = rleData;
  layer.channelSize[channelIndex] = offset + height * sizeof<Uint16T>();
}

void updateMergedImage(ExportDocument document, TypedData planarDataR,
    TypedData planarDataG, TypedData planarDataB) {
  if (planarDataR is Uint8List) {
    _updateMergedImageImpl<Uint8T>(
        document, planarDataR, planarDataG, planarDataB);
  } else if (planarDataR is Uint16List) {
    _updateMergedImageImpl<Uint16T>(
        document, planarDataR, planarDataG, planarDataB);
  } else if (planarDataR is Float32List) {
    _updateMergedImageImpl<Float32T>(
        document, planarDataR, planarDataG, planarDataB);
  } else {
    print('unsupported');
  }
}

void _updateMergedImageImpl<T extends NumDataType>(ExportDocument document,
    TypedData planarDataR, TypedData planarDataG, TypedData planarDataB) {
  // free old data

  // copy raw data
  final size = document.width * document.height;
  var memoryR = getTypedList<T>(Uint8List(size * sizeof<T>())) as List;
  var memoryG = getTypedList<T>(Uint8List(size * sizeof<T>())) as List;
  var memoryB = getTypedList<T>(Uint8List(size * sizeof<T>())) as List;
  for (var i = 0; i < size; ++i) {
    memoryR[i] = nativeToBigEndian<T>((planarDataR as List)[i]);
    memoryG[i] = nativeToBigEndian<T>((planarDataG as List)[i]);
    memoryB[i] = nativeToBigEndian<T>((planarDataB as List)[i]);
  }
  document.mergedImageData[0] = (memoryR as TypedData).buffer.asUint8List();
  document.mergedImageData[1] = (memoryG as TypedData).buffer.asUint8List();
  document.mergedImageData[2] = (memoryB as TypedData).buffer.asUint8List();
}

int addAlphaChannel(ExportDocument document, String name, int r, int g, int b,
    int a, int opacity, int mode) {
  final index = document.alphaChannelCount;
  document.alphaChannels.add(AlphaChannel());

  var channel = document.alphaChannels[index];
  channel.asciiName = name;
  channel.colorSpace = 0;
  channel.color[0] = r;
  channel.color[1] = g;
  channel.color[2] = b;
  channel.color[3] = a;
  channel.opacity = opacity;
  channel.mode = mode;

  return index;
}

void updateChannel(ExportDocument document, int channelIndex, TypedData data) {
  if (data is Uint8List) {
    _updateChannelImpl<Uint8T>(document, channelIndex, data);
  } else if (data is Uint16List) {
    _updateChannelImpl<Uint16T>(document, channelIndex, data);
  } else if (data is Float32List) {
    _updateChannelImpl<Float32T>(document, channelIndex, data);
  } else {
    print('unsupported');
  }
}

const _XMP_HEADER = '''<x:xmpmeta xmlns:x = "adobe:ns:meta/">
		<rdf:RDF xmlns:rdf = "http://www.w3.org/1999/02/22-rdf-syntax-ns#">
		<rdf:Description rdf:about=""
		xmlns:xmp = "http://ns.adobe.com/xap/1.0/"
		xmlns:dc = "http://purl.org/dc/elements/1.1/"
		xmlns:photoshop = "http://ns.adobe.com/photoshop/1.0/"
		xmlns:xmpMM = "http://ns.adobe.com/xap/1.0/mm/"
		xmlns:stEvt = "http://ns.adobe.com/xap/1.0/sType/ResourceEvent#">''';

const _XMP_FOOTER = '''</rdf:Description>\n
		</rdf:RDF>\n
		</x:xmpmeta>\n''';

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
void _updateChannelImpl<T extends NumDataType>(
    ExportDocument document, int channelIndex, TypedData data) {
  // free old data

  // copy raw data
  var size = document.width * document.height;
  var channelData = getTypedList<T>(Uint8List(size * sizeof<T>())) as List;
  for (var i = 0; i < size; ++i) {
    channelData[i] = nativeToBigEndian<T>((data as List)[i]);
  }
  document.alphaChannelData[channelIndex] = channelData;
}

int _getMetaDataResourceSize(ExportDocument document) {
  var metaDataSize = _XMP_HEADER.length;
  for (var i = 0; i < document.attributeCount; ++i) {
    metaDataSize += ('<xmp:>').length;
    metaDataSize += (document.attributes[i].name.length) * 2;
    metaDataSize += (document.attributes[i].value).length;
    metaDataSize += ('</xmp:>\n').length;
  }
  metaDataSize += _XMP_FOOTER.length;

  return metaDataSize;
}

void writeDocument(ExportDocument document, File file) {
  var writer = SyncFileWriter(file);

  // signature
  _writeToFileBE<Uint32T>(writer, keyValue('8BPS'));

  // version
  _writeToFileBE<Uint16T>(writer, (1));

  // reserved bytes
  final zeroes = Uint8List.fromList(<int>[0, 0, 0, 0, 0, 0]);
  _writeToFile(writer, zeroes);

  // channel count
  final documentChannelCount =
      (document.colorMode + document.alphaChannelCount);
  _writeToFileBE<Uint16T>(writer, documentChannelCount);

  // header
  final mode = (document.colorMode);
  _writeToFileBE<Uint32T>(writer, document.height);
  _writeToFileBE<Uint32T>(writer, document.width);
  _writeToFileBE<Uint16T>(writer, document.bitsPerChannel);
  _writeToFileBE<Uint16T>(writer, mode);

  if (document.bitsPerChannel == 32) {
    // in 32-bit mode, Photoshop insists on having a color mode data section with magic info.
    // this whole section is undocumented. there's no information to be found on the web.
    // we write Photoshop's default values.
    final colorModeSectionLength = 112;
    _writeToFileBE<Uint32T>(writer, colorModeSectionLength);
    {
      // tests suggest that this is some kind of HDR toning information
      final key = keyValue('hdrt');
      _writeToFileBE<Uint32T>(writer, key);

      _writeToFileBE<Uint32T>(writer, (3)); // ?
      _writeToFileBE<Float32T>(writer, (0.23)); // ?
      _writeToFileBE<Uint32T>(writer, (2)); // ?

      _writeToFileBE<Uint32T>(
          writer, 8); // length of the following Unicode string
      _writeToFileBE<Uint16T>(writer, 'D'.codeUnitAt(0));
      _writeToFileBE<Uint16T>(writer, 'e'.codeUnitAt(0));
      _writeToFileBE<Uint16T>(writer, 'f'.codeUnitAt(0));
      _writeToFileBE<Uint16T>(writer, 'a'.codeUnitAt(0));
      _writeToFileBE<Uint16T>(writer, 'u'.codeUnitAt(0));
      _writeToFileBE<Uint16T>(writer, 'l'.codeUnitAt(0));
      _writeToFileBE<Uint16T>(writer, 't'.codeUnitAt(0));
      _writeToFileBE<Uint16T>(writer, '\0'.codeUnitAt(0));

      _writeToFileBE<Uint16T>(writer, (2)); // ?
      _writeToFileBE<Uint16T>(writer, (2)); // ?
      _writeToFileBE<Uint16T>(writer, (0)); // ?
      _writeToFileBE<Uint16T>(writer, (0)); // ?
      _writeToFileBE<Uint16T>(writer, (255)); // ?
      _writeToFileBE<Uint16T>(writer, (255)); // ?

      _writeToFileBE<Uint8T>(writer, (1)); // ?
      _writeToFileBE<Uint8T>(writer, (1)); // ?
      _writeToFileBE<Uint32T>(writer, (0)); // ?
      _writeToFileBE<Uint32T>(writer, (0)); // ?

      _writeToFileBE<Float32T>(writer, (16.0)); // ?
      _writeToFileBE<Uint32T>(writer, (1)); // ?
      _writeToFileBE<Uint32T>(writer, (1)); // ?
      _writeToFileBE<Float32T>(writer, (1.0)); // ?
    }
    {
      // HDR alpha information?
      final key = keyValue('hdra');
      _writeToFileBE<Uint32T>(writer, key);

      _writeToFileBE<Uint32T>(writer, (6)); // number of following values
      _writeToFileBE<Float32T>(writer, (0.0)); // ?
      _writeToFileBE<Float32T>(writer, (20.0)); // ?
      _writeToFileBE<Float32T>(writer, (30.0)); // ?
      _writeToFileBE<Float32T>(writer, (0.0)); // ?
      _writeToFileBE<Float32T>(writer, (0.0)); // ?
      _writeToFileBE<Float32T>(writer, (1.0)); // ?

      _writeToFileBE<Uint32T>(writer, (0)); // ?
      _writeToFileBE<Uint16T>(writer, (0)); // ?
    }
  } else {
    // empty color mode data section
    _writeToFileBE<Uint32T>(writer, (0));
  }

  // image resources
  {
    final hasMetaData = (document.attributeCount != 0);
    final hasIccProfile = (document.iccProfile != null);
    final hasExifData = (document.exifData != null);
    final hasThumbnail = (document.thumbnail != null);
    final hasAlphaChannels = (document.alphaChannelCount != 0);
    final hasImageResources = (hasMetaData ||
        hasIccProfile ||
        hasExifData ||
        hasThumbnail ||
        hasAlphaChannels);

    // write image resources section with optional XMP meta data, ICC profile, EXIF data, thumbnail, alpha channels
    if (hasImageResources) {
      final metaDataSize = hasMetaData ? _getMetaDataResourceSize(document) : 0;
      final iccProfileSize =
          hasIccProfile ? getIccProfileResourceSize(document) : 0;
      final exifDataSize = hasExifData ? _getExifDataResourceSize(document) : 0;
      final thumbnailSize =
          hasThumbnail ? _getThumbnailResourceSize(document) : 0;
      final displayInfoSize =
          hasAlphaChannels ? _getDisplayInfoResourceSize(document) : 0;
      final channelNamesSize =
          hasAlphaChannels ? _getChannelNamesResourceSize(document) : 0;
      final unicodeChannelNamesSize =
          hasAlphaChannels ? _getUnicodeChannelNamesResourceSize(document) : 0;

      var sectionLength = 0;
      sectionLength += hasMetaData
          ? roundUpToMultiple(_getImageResourceSize() + metaDataSize, 2)
          : 0;
      sectionLength += hasIccProfile
          ? roundUpToMultiple(_getImageResourceSize() + iccProfileSize, 2)
          : 0;
      sectionLength += hasExifData
          ? roundUpToMultiple(_getImageResourceSize() + exifDataSize, 2)
          : 0;
      sectionLength += hasThumbnail
          ? roundUpToMultiple(_getImageResourceSize() + thumbnailSize, 2)
          : 0;
      sectionLength += hasAlphaChannels
          ? roundUpToMultiple(_getImageResourceSize() + displayInfoSize, 2)
          : 0;
      sectionLength += hasAlphaChannels
          ? roundUpToMultiple(_getImageResourceSize() + channelNamesSize, 2)
          : 0;
      sectionLength += hasAlphaChannels
          ? roundUpToMultiple(
              _getImageResourceSize() + unicodeChannelNamesSize, 2)
          : 0;

      // image resource section starts with length of the whole section
      _writeToFileBE<Uint32T>(writer, sectionLength);

      if (hasMetaData) {
        _writeImageResource(writer, ImageResource.XMP_METADATA, metaDataSize);

        final start = writer.getPosition();
        {
          writer.write(_XMP_HEADER, _XMP_HEADER.length);
          for (var i = 0; i < document.attributeCount; ++i) {
            writer.write('<xmp:', 5);
            writer.write(document.attributes[i].name,
                ((document.attributes[i].name).length));
            writer.write('>', 1);
            writer.write(document.attributes[i].value,
                ((document.attributes[i].value).length));
            writer.write('</xmp:', 6);
            writer.write(document.attributes[i].name,
                ((document.attributes[i].name).length));
            writer.write('>\n', 2);
          }
          writer.write(_XMP_FOOTER, _XMP_FOOTER.length);
        }
        final bytesWritten = writer.getPosition() - start;
        if (bytesWritten & 1 != 0) {
          // write padding byte
          _writeToFileBE<Uint8T>(writer, (0));
        }
      }

      if (hasIccProfile) {
        _writeImageResource(writer, ImageResource.ICC_PROFILE, iccProfileSize);

        final start = writer.getPosition();
        {
          writer.write(document.iccProfile, document.sizeOfICCProfile);
        }
        final bytesWritten = writer.getPosition() - start;
        if (bytesWritten & 1 != 0) {
          // write padding byte
          _writeToFileBE<Uint8T>(writer, (0));
        }
      }

      if (hasExifData) {
        _writeImageResource(writer, ImageResource.EXIF_DATA, exifDataSize);

        final start = writer.getPosition();
        {
          writer.write(document.exifData, document.sizeOfExifData);
        }
        final bytesWritten = writer.getPosition() - start;
        if (bytesWritten & 1 != 0) {
          // write padding byte
          _writeToFileBE<Uint8T>(writer, (0));
        }
      }

      if (hasThumbnail) {
        _writeImageResource(
            writer, ImageResource.THUMBNAIL_RESOURCE, thumbnailSize);

        final start = writer.getPosition();
        {
          final format = 1; // format = kJpegRGB
          final bitsPerPixel = 24;
          final planeCount = 1;
          final widthInBytes =
              (document.thumbnail.width * bitsPerPixel + 31) / 32 * 4;
          final totalSize =
              widthInBytes * document.thumbnail.height * planeCount;

          _writeToFileBE<Uint32T>(writer, format);
          _writeToFileBE<Uint32T>(writer, document.thumbnail.width);
          _writeToFileBE<Uint32T>(writer, document.thumbnail.height);
          _writeToFileBE<Uint32T>(writer, widthInBytes);
          _writeToFileBE<Uint32T>(writer, totalSize);
          _writeToFileBE<Uint32T>(writer, document.thumbnail.binaryJpegSize);
          _writeToFileBE<Uint16T>(writer, bitsPerPixel);
          _writeToFileBE<Uint16T>(writer, planeCount);

          writer.write(
              document.thumbnail.binaryJpeg, document.thumbnail.binaryJpegSize);
        }
        final bytesWritten = writer.getPosition() - start;
        if (bytesWritten & 1 != 0) {
          // write padding byte
          _writeToFileBE<Uint8T>(writer, (0));
        }
      }

      if (hasAlphaChannels) {
        // write display info
        {
          _writeImageResource(
              writer, ImageResource.DISPLAY_INFO, displayInfoSize);

          final start = writer.getPosition();

          // version
          _writeToFileBE<Uint32T>(writer, (1));

          // per channel data
          for (var i = 0; i < document.alphaChannelCount; ++i) {
            var channel = document.alphaChannels[i];
            _writeToFileBE<Uint16T>(writer, channel.colorSpace);
            _writeToFileBE<Uint16T>(writer, channel.color[0]);
            _writeToFileBE<Uint16T>(writer, channel.color[1]);
            _writeToFileBE<Uint16T>(writer, channel.color[2]);
            _writeToFileBE<Uint16T>(writer, channel.color[3]);
            _writeToFileBE<Uint16T>(writer, channel.opacity);
            _writeToFileBE<Uint8T>(writer, channel.mode);
          }

          final bytesWritten = writer.getPosition() - start;
          if (bytesWritten & 1 != 0) {
            // write padding byte
            _writeToFileBE<Uint8T>(writer, (0));
          }
        }

        // write channel names
        {
          _writeImageResource(writer, ImageResource.ALPHA_CHANNEL_ASCII_NAMES,
              channelNamesSize);

          final start = writer.getPosition();

          for (var i = 0; i < document.alphaChannelCount; ++i) {
            _writeToFileBE<Uint8T>(
                writer, (document.alphaChannels[i].asciiName.length));
            writer.write(document.alphaChannels[i].asciiName,
                (document.alphaChannels[i].asciiName.length));
          }

          final bytesWritten = writer.getPosition() - start;
          if (bytesWritten & 1 != 0) {
            // write padding byte
            _writeToFileBE<Uint8T>(writer, (0));
          }
        }

        // write unicode channel names
        {
          _writeImageResource(writer, ImageResource.ALPHA_CHANNEL_UNICODE_NAMES,
              unicodeChannelNamesSize);

          final start = writer.getPosition();

          for (var i = 0; i < document.alphaChannelCount; ++i) {
            // PSD expects UTF-16 strings, followed by a null terminator
            final length = document.alphaChannels[i].asciiName.length;
            _writeToFileBE<Uint32T>(writer, (length + 1));

            final asciiStr = document.alphaChannels[i].asciiName;
            for (var j = 0; j < length; ++j) {
              final unicodeGlyph = asciiStr.codeUnitAt(j);
              _writeToFileBE<Uint16T>(writer, unicodeGlyph);
            }

            _writeToFileBE<Uint16T>(writer, (0));
          }

          final bytesWritten = writer.getPosition() - start;
          if (bytesWritten & 1 != 0) {
            // write padding byte
            _writeToFileBE<Uint8T>(writer, (0));
          }
        }
      }
    } else {
      // no image resources
      _writeToFileBE<Uint32T>(writer, (0));
    }
  }

  // layer mask section
  var layerInfoSectionLength = _getLayerInfoSectionLength(document);

  // layer info section must be padded to a multiple of 4
  var paddingNeeded =
      roundUpToMultiple(layerInfoSectionLength, 4) - layerInfoSectionLength;
  layerInfoSectionLength += paddingNeeded;

  final is8BitData = (document.bitsPerChannel == 8);
  if (is8BitData) {
    // 8-bit data
    // layer mask section length also includes global layer mask info marker. layer info follows directly after that
    final layerMaskSectionLength = layerInfoSectionLength + 4;
    _writeToFileBE<Uint32T>(writer, layerMaskSectionLength);
  } else {
    // 16-bit and 32-bit layer data is stored in Additional Layer Information, so we leave the following layer info section empty
    final layerMaskSectionLength = layerInfoSectionLength + 4 * 5;
    _writeToFileBE<Uint32T>(writer, layerMaskSectionLength);

    // empty layer info section
    _writeToFileBE<Uint32T>(writer, (0));

    // empty global layer mask info
    _writeToFileBE<Uint32T>(writer, (0));

    // additional layer information
    final signature = keyValue('8BIM');
    _writeToFileBE<Uint32T>(writer, signature);

    if (document.bitsPerChannel == 16) {
      final key = keyValue('Lr16');
      _writeToFileBE<Uint32T>(writer, key);
    } else if (document.bitsPerChannel == 32) {
      final key = keyValue('Lr32');
      _writeToFileBE<Uint32T>(writer, key);
    }
  }

  _writeToFileBE<Uint32T>(writer, layerInfoSectionLength);

  // layer count
  _writeToFileBE<Uint16T>(writer, document.layerCount);

  // per-layer info
  for (var i = 0; i < document.layerCount; ++i) {
    var layer = document.layers[i];
    _writeToFileBE<Int32T>(writer, layer.top);
    _writeToFileBE<Int32T>(writer, layer.left);
    _writeToFileBE<Int32T>(writer, layer.bottom);
    _writeToFileBE<Int32T>(writer, layer.right);

    final channelCount = getChannelCount(layer);
    _writeToFileBE<Uint16T>(writer, channelCount);

    // per-channel info
    for (var j = 0; j < ExportLayer.MAX_CHANNEL_COUNT; ++j) {
      if (layer.channelData[j] != null) {
        final channelId = _getChannelId(j);
        _writeToFileBE<Int16T>(writer, channelId);

        // channel data always has a 2-byte compression type in front of the data
        final channelDataSize = layer.channelSize[j] + 2;
        _writeToFileBE<Uint32T>(writer, channelDataSize);
      }
    }

    // blend mode signature
    _writeToFileBE<Uint32T>(writer, keyValue('8BIM'));

    // blend mode data
    final opacity = 255;
    final clipping = 0;
    final flags = 0;
    final filler = 0;
    _writeToFileBE<Uint32T>(writer, keyValue('norm'));
    _writeToFileBE<Uint8T>(writer, opacity);
    _writeToFileBE<Uint8T>(writer, clipping);
    _writeToFileBE<Uint8T>(writer, flags);
    _writeToFileBE<Uint8T>(writer, filler);

    // extra data, including layer name
    final extraDataLength = _getExtraDataLength(layer);
    _writeToFileBE<Uint32T>(writer, extraDataLength);

    final layerMaskDataLength = 0;
    _writeToFileBE<Uint32T>(writer, layerMaskDataLength);

    final layerBlendingRangesDataLength = 0;
    _writeToFileBE<Uint32T>(writer, layerBlendingRangesDataLength);

    // the layer name is stored as pascal string, padded to a multiple of 4
    final nameLength = ((layer.name.length));
    final paddedNameLength = roundUpToMultiple(nameLength + 1, 4);
    _writeToFileBE<Uint8T>(writer, nameLength);
    writer.write(layer.name, paddedNameLength - 1);
  }

  // per-layer data
  for (var i = 0; i < document.layerCount; ++i) {
    var layer = document.layers[i];

    // per-channel data
    for (var j = 0; j < ExportLayer.MAX_CHANNEL_COUNT; ++j) {
      if (layer.channelData[j] != null) {
        _writeToFileBE<Uint16T>(writer, layer.channelCompression[j]);
        writer.write(layer.channelData[j], layer.channelSize[j]);
      }
    }
  }

  // add padding to align layer info section to multiple of 4
  if (paddingNeeded != 0) {
    writer.write(zeroes, paddingNeeded);
  }

  // global layer mask info
  final globalLayerMaskInfoLength = 0;
  _writeToFileBE<Uint32T>(writer, globalLayerMaskInfoLength);

  // for some reason, Photoshop insists on having an (uncompressed) Image Data section for 32-bit files.
  // this is unfortunate, because it makes the files very large. don't think this is intentional, but rather a bug.
  // additionally, for documents of a certain size, Photoshop also expects merged data to be there.
  // hence we bite the bullet and just write the merged data section in all cases.

  // merged data section
  {
    final size =
        document.width * document.height * document.bitsPerChannel ~/ 8;
    var emptyMemory = Uint8List(size);

    // write merged image
    _writeToFileBE<Uint16T>(writer, (CompressionType.RAW));
    if (document.colorMode == ExportColorMode.GRAYSCALE) {
      final dataGray = document.mergedImageData[0] ?? emptyMemory;
      writer.write(dataGray, size);
    } else if (document.colorMode == ExportColorMode.RGB) {
      final dataR = document.mergedImageData[0] ?? emptyMemory;
      final dataG = document.mergedImageData[1] ?? emptyMemory;
      final dataB = document.mergedImageData[2] ?? emptyMemory;
      writer.write(dataR, size);
      writer.write(dataG, size);
      writer.write(dataB, size);
    }

    // write alpha channels
    for (var i = 0; i < document.alphaChannelCount; ++i) {
      writer.write(document.alphaChannelData[i], size);
    }
  }

  writer.save();
}

void _writeToFile(SyncFileWriter writer, Uint8List zeroes) {
  writer.write(zeroes);
}

void _writeToFileBE<T extends NumDataType>(SyncFileWriter writer, num i) {
  switch (T) {
    case Uint8T:
    case Int8T:
    case Uint16T:
    case Int16T:
    case Float32T:
    case Int32T:
    case Uint32T:
    case Float64T:
    case Int64T:
    case Uint64T:
      var bd = ByteData(sizeof<T>());
      setByteData<T>(bd, i, Endian.big);
      writer.write(bd, sizeof<T>());
      break;
    default:
      throw Error();
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int getIccProfileResourceSize(ExportDocument document) {
  return document.sizeOfICCProfile;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int getChannelCount(ExportLayer layer) {
  var count = 0;
  for (var i = 0; i < ExportLayer.MAX_CHANNEL_COUNT; ++i) {
    if (layer.channelData[i] != null) {
      ++count;
    }
  }

  return count;
}

int _getChannelId(int channelIndex) {
  switch (channelIndex) {
    case 0:
      return ChannelType.R;

    case 1:
      return ChannelType.G;

    case 2:
      return ChannelType.B;

    case 3:
      return ChannelType.TRANSPARENCY_MASK;

    default:
      return 0;
  }
}

int _getExifDataResourceSize(ExportDocument document) {
  return document.sizeOfExifData;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int _getThumbnailResourceSize(ExportDocument document) {
  return document.thumbnail.binaryJpegSize + 28;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int _getExtraDataLength(ExportLayer layer) {
  final nameLength = ((layer.name.length));
  final paddedNameLength = roundUpToMultiple(nameLength + 1, 4);

  // includes the lengths of the layer mask data and layer blending ranges data
  return (4 + 4 + paddedNameLength);
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int _getDisplayInfoResourceSize(ExportDocument document) {
  // display info consists of 4-byte version, followed by 13 bytes per channel
  return sizeof<Uint32T>() + 13 * document.alphaChannelCount;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int _getChannelNamesResourceSize(ExportDocument document) {
  var size = 0;
  for (var i = 0; i < document.alphaChannelCount; ++i) {
    size += document.alphaChannels[i].asciiName.length + 1;
  }

  return (size);
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int _getUnicodeChannelNamesResourceSize(ExportDocument document) {
  var size = 0;
  for (var i = 0; i < document.alphaChannelCount; ++i) {
    // unicode strings are null terminated
    size += (document.alphaChannels[i].asciiName.length + 1) * 2 + 4;
  }

  return size;
}

int _getImageResourceSize() {
  var size = 0;
  size += sizeof<Uint32T>(); // signature
  size += sizeof<Uint16T>(); // resource ID
  size += 2; // padded name, 2 zero bytes
  size += sizeof<Uint32T>(); // resource size

  return size;
}

void _writeImageResource(SyncFileWriter writer, int id, int resourceSize) {
  final signature = keyValue('8BIM');
  _writeToFileBE<Uint32T>(writer, signature);
  _writeToFileBE<Uint16T>(writer, id);

  // padded name, unused
  _writeToFileBE<Uint8T>(writer, (0));
  _writeToFileBE<Uint8T>(writer, (0));

  _writeToFileBE<Uint32T>(writer, resourceSize);
}

int _getLayerInfoSectionLength(ExportDocument document) {
  // the layer info section includes the following data:
  // - layer count (2)
  //   per layer:
  //   - top, left, bottom, right (16)
  //   - channel count (2)
  //     per channel
  //     - channel ID and size (6)
  //   - blend mode signature (4)
  //   - blend mode key (4)
  //   - opacity, clipping, flags, filler (4)
  //   - extra data (variable)
  //     - length (4)
  //     - layer mask data length (4)
  //     - layer blending ranges length (4)
  //     - padded name (variable)
  // - all channel data (variable)
  //   - compression (2)
  //   - channel data (variable)

  var size = 2 + 4;
  for (var i = 0; i < document.layerCount; ++i) {
    var layer = document.layers[i];
    size += 16 +
        2 +
        getChannelCount(layer) * 6 +
        4 +
        4 +
        4 +
        _getExtraDataLength(layer) +
        4;
    size += _getChannelDataSize(layer) + getChannelCount(layer) * 2;
  }

  return size;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int _getChannelDataSize(ExportLayer layer) {
  var size = 0;
  for (var i = 0; i < ExportLayer.MAX_CHANNEL_COUNT; ++i) {
    if (layer.channelData[i] != null) {
      size += layer.channelSize[i];
    }
  }

  return size;
}
