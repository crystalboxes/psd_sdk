// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
import 'dart:ffi';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:psd_sdk/psd_sdk.dart';
import 'package:psd_sdk/src/export_layer.dart';
import 'package:psd_sdk/src/sync_file_writer.dart';

import 'allocator.dart';
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

ExportDocument createExportDocument(Allocator allocator, int canvasWidth,
    int canvasHeight, int bitsPerChannel, int colorMode) {
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

int addMetaData(
    ExportDocument document, Allocator allocator, String name, String value) {
  final index = document.attributeCount;
  document.attributes.add(ExportMetaDataAttribute());
  UpdateMetaData(document, allocator, index, name, value);

  return index;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
String CreateString(Allocator allocator, String str) {
  // final length = str.length;
  // final paddedLength = roundUpToMultiple(length + 1, 4);
  // final newString = Uint8List(paddedLength);
  // for (var x = 0; x < length; x++) {
  //   newString[x] = str.codeUnitAt(x);
  // }

  // return newString;
  return str;
}

void UpdateMetaData(ExportDocument document, Allocator allocator, int index,
    String name, String value) {
  var attribute = document.attributes[index];
  attribute.name = CreateString(allocator, name);
  attribute.value = CreateString(allocator, value);
}

int addLayer(ExportDocument document, Allocator allocator, String name) {
  final index = document.layerCount;
  document.layers.add(ExportLayer());

  var layer = document.layers[index];
  layer.name = CreateString(allocator, name);
  return index;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int getChannelIndex(int channel) {
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
    Allocator allocator,
    int layerIndex,
    int channel,
    int left,
    int top,
    int right,
    int bottom,
    TypedData planarData,
    int compression) {
  if (planarData is Uint8List) {
    UpdateLayerImpl<uint8_t>(document, allocator, layerIndex, channel, left,
        top, right, bottom, planarData, compression);
  } else if (planarData is Uint16List) {
    UpdateLayerImpl<uint16_t>(document, allocator, layerIndex, channel, left,
        top, right, bottom, planarData, compression);
  } else if (planarData is Float32List) {
    UpdateLayerImpl<float32_t>(document, allocator, layerIndex, channel, left,
        top, right, bottom, planarData, compression);
  } else {
    print('not supported');
  }
}

void UpdateLayerImpl<T extends NumDataType>(
    ExportDocument document,
    Allocator allocator,
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
  final channelIndex = getChannelIndex(channel);

  // free old data
  {
    if (layer.channelData != null) {
      layer.channelData = List(ExportLayer.MAX_CHANNEL_COUNT);
    }
  }

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
    CreateDataRaw<T>(allocator, layer, channelIndex, planarData, width, height);
  } else if (compression == CompressionType.RLE) {
    // compress with RLE
    CreateDataRLE<T>(allocator, layer, channelIndex, planarData, width, height);
  } else if (compression == CompressionType.ZIP) {
    // compress with ZIP
    // note that this has a template specialization for 32-bit float data that forwards to ZipWithPrediction.
    if (T == float32_t) {
      CreateDataZipPredictionF32(
          allocator, layer, channelIndex, planarData, width, height);
    } else {
      CreateDataZip<T>(
          allocator, layer, channelIndex, planarData, width, height);
    }
  } else if (compression == CompressionType.ZIP_WITH_PREDICTION) {
    if (T == float32_t) {
      CreateDataZipPredictionF32(
          allocator, layer, channelIndex, planarData, width, height);
    } else {
      // delta-encode, then compress with ZIP
      CreateDataZipPrediction<T>(
          allocator, layer, channelIndex, planarData, width, height);
    }
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
void CreateDataZipPrediction<T extends NumDataType>(
    Allocator allocator,
    ExportLayer layer,
    int channelIndex,
    TypedData planarData,
    int width,
    int height) {
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

      deltaData[deltaDataPos++] = (value & (T is uint8_t ? 0xFF : 0xFFFF));
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

void CreateDataZipPredictionF32(Allocator allocator, ExportLayer layer,
    int channelIndex, Float32List planarData, int width, int height) {
  final size = width * height;

  // float data is first converted into planar data to allow for better compression.
  // this is done row by row, so if the bytes of the floats in a row consist of "1234123412341234" they will be turned into "1111222233334444".
  // the data is also converted to big-endian in the same loop.
  var bigEndianPlanarData = Uint8List(size * sizeof<float32_t>());
  for (var y = 0; y < height; ++y) {
    for (var x = 0; x < width; ++x) {
      var asBytes = ByteData(sizeof<float32_t>());
      asBytes.setFloat32(0, planarData[y * width + x]);
      bigEndianPlanarData[y * width * sizeof<float32_t>() + x + width * 0] =
          asBytes.getUint8(3);
      bigEndianPlanarData[y * width * sizeof<float32_t>() + x + width * 1] =
          asBytes.getUint8(2);
      bigEndianPlanarData[y * width * sizeof<float32_t>() + x + width * 2] =
          asBytes.getUint8(1);
      bigEndianPlanarData[y * width * sizeof<float32_t>() + x + width * 3] =
          asBytes.getUint8(0);
    }
  }

  // now delta encode the individual bytes row by row
  var deltaData = Uint8List(size * sizeof<float32_t>());
  for (var y = 0; y < height; ++y) {
    deltaData[y * width * sizeof<float32_t>()] =
        bigEndianPlanarData[y * width * sizeof<float32_t>()];
    for (var x = 1; x < width * 4; ++x) {
      final previous =
          bigEndianPlanarData[y * width * sizeof<float32_t>() + x - 1];
      final current = bigEndianPlanarData[y * width * sizeof<float32_t>() + x];
      final value = current - previous;

      deltaData[y * width * sizeof<float32_t>() + x] = (value & 0xFF);
    }
  }

  Uint8List zipData = ZLibEncoder().encode(deltaData);

  layer.channelData[channelIndex] = zipData;
  layer.channelSize[channelIndex] = zipData.length;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
void CreateDataZip<T extends NumDataType>(
    Allocator allocator,
    ExportLayer layer,
    int channelIndex,
    TypedData planarData,
    int width,
    int height) {
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

void CreateDataRaw<T extends NumDataType>(
    Allocator allocator,
    ExportLayer layer,
    int channelIndex,
    TypedData planarData,
    int width,
    int height) {
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

void CreateDataRLE<T extends NumDataType>(
    Allocator allocator,
    ExportLayer layer,
    int channelIndex,
    TypedData planarData,
    int width,
    int height) {
  final size = width * height;

  // each row needs two additional bytes for storing the size of the row's data.
  // we pack the data row by row, and copy it into the final buffer.
  var rleData = Uint8List(height * sizeof<uint16_t>() + size * sizeof<T>() * 2);

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
        .setUint16(y * sizeof<uint16_t>(), compressedSize, Endian.big);

    for (var i = 0; i < compressedSize; i++) {
      rleData[i + height * sizeof<uint16_t>() + offset] = rleRowData[i];
    }

    offset += compressedSize;
  }

  layer.channelData[channelIndex] = rleData;
  layer.channelSize[channelIndex] = offset + height * sizeof<uint16_t>();
}

void updateMergedImage(ExportDocument document, Allocator allocator,
    TypedData planarDataR, TypedData planarDataG, TypedData planarDataB) {
  if (planarDataR is Uint8List) {
    _updateMergedImageImpl<uint8_t>(
        document, allocator, planarDataR, planarDataG, planarDataB);
  } else if (planarDataR is Uint16List) {
    _updateMergedImageImpl<uint16_t>(
        document, allocator, planarDataR, planarDataG, planarDataB);
  } else if (planarDataR is Float32List) {
    _updateMergedImageImpl<float32_t>(
        document, allocator, planarDataR, planarDataG, planarDataB);
  } else {
    print('unsupported');
  }
}

void _updateMergedImageImpl<T extends NumDataType>(
    ExportDocument document,
    Allocator allocator,
    TypedData planarDataR,
    TypedData planarDataG,
    TypedData planarDataB) {
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

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int addAlphaChannel(ExportDocument document, Allocator allocator, String name,
    int r, int g, int b, int a, int opacity, int mode) {
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

void updateChannel(ExportDocument document, Allocator allocator,
    int channelIndex, TypedData data) {
  if (data is Uint8List) {
    _updateChannelImpl<uint8_t>(document, allocator, channelIndex, data);
  } else if (data is Uint16List) {
    _updateChannelImpl<uint16_t>(document, allocator, channelIndex, data);
  } else if (data is Float32List) {
    _updateChannelImpl<float32_t>(document, allocator, channelIndex, data);
  } else {
    print('unsupported');
  }
}

const XMP_HEADER = '''<x:xmpmeta xmlns:x = "adobe:ns:meta/">
		<rdf:RDF xmlns:rdf = "http://www.w3.org/1999/02/22-rdf-syntax-ns#">
		<rdf:Description rdf:about=""
		xmlns:xmp = "http://ns.adobe.com/xap/1.0/"
		xmlns:dc = "http://purl.org/dc/elements/1.1/"
		xmlns:photoshop = "http://ns.adobe.com/photoshop/1.0/"
		xmlns:xmpMM = "http://ns.adobe.com/xap/1.0/mm/"
		xmlns:stEvt = "http://ns.adobe.com/xap/1.0/sType/ResourceEvent#">''';

const XMP_FOOTER = '''</rdf:Description>\n
		</rdf:RDF>\n
		</x:xmpmeta>\n''';

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
void _updateChannelImpl<T extends NumDataType>(ExportDocument document,
    Allocator allocator, int channelIndex, TypedData data) {
  // free old data

  // copy raw data
  var size = document.width * document.height;
  var channelData = getTypedList<T>(Uint8List(size * sizeof<T>())) as List;
  for (var i = 0; i < size; ++i) {
    channelData[i] = nativeToBigEndian<T>((data as List)[i]);
  }
  document.alphaChannelData[channelIndex] = channelData;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int GetMetaDataResourceSize(ExportDocument document) {
  var metaDataSize = XMP_HEADER.length;
  for (var i = 0; i < document.attributeCount; ++i) {
    metaDataSize += ('<xmp:>').length;
    metaDataSize += (document.attributes[i].name.length) * 2;
    metaDataSize += (document.attributes[i].value).length;
    metaDataSize += ('</xmp:>\n').length;
  }
  metaDataSize += XMP_FOOTER.length;

  return metaDataSize;
}

void writeDocument(ExportDocument document, Allocator allocator, File file) {
  var writer = SyncFileWriter(file);

  // signature
  WriteToFileBE<uint32_t>(writer, keyValue('8BPS'));

  // version
  WriteToFileBE<uint16_t>(writer, (1));

  // reserved bytes
  final zeroes = Uint8List.fromList(<int>[0, 0, 0, 0, 0, 0]);
  WriteToFile(writer, zeroes);

  // channel count
  final documentChannelCount =
      (document.colorMode + document.alphaChannelCount);
  WriteToFileBE<uint16_t>(writer, documentChannelCount);

  // header
  final mode = (document.colorMode);
  WriteToFileBE<uint32_t>(writer, document.height);
  WriteToFileBE<uint32_t>(writer, document.width);
  WriteToFileBE<uint16_t>(writer, document.bitsPerChannel);
  WriteToFileBE<uint16_t>(writer, mode);

  if (document.bitsPerChannel == 32) {
    // in 32-bit mode, Photoshop insists on having a color mode data section with magic info.
    // this whole section is undocumented. there's no information to be found on the web.
    // we write Photoshop's default values.
    final colorModeSectionLength = 112;
    WriteToFileBE<uint32_t>(writer, colorModeSectionLength);
    {
      // tests suggest that this is some kind of HDR toning information
      final key = keyValue('hdrt');
      WriteToFileBE<uint32_t>(writer, key);

      WriteToFileBE<uint32_t>(writer, (3)); // ?
      WriteToFileBE<float32_t>(writer, (0.23)); // ?
      WriteToFileBE<uint32_t>(writer, (2)); // ?

      WriteToFileBE<uint32_t>(
          writer, 8); // length of the following Unicode string
      WriteToFileBE<uint16_t>(writer, 'D'.codeUnitAt(0));
      WriteToFileBE<uint16_t>(writer, 'e'.codeUnitAt(0));
      WriteToFileBE<uint16_t>(writer, 'f'.codeUnitAt(0));
      WriteToFileBE<uint16_t>(writer, 'a'.codeUnitAt(0));
      WriteToFileBE<uint16_t>(writer, 'u'.codeUnitAt(0));
      WriteToFileBE<uint16_t>(writer, 'l'.codeUnitAt(0));
      WriteToFileBE<uint16_t>(writer, 't'.codeUnitAt(0));
      WriteToFileBE<uint16_t>(writer, '\0'.codeUnitAt(0));

      WriteToFileBE<uint16_t>(writer, (2)); // ?
      WriteToFileBE<uint16_t>(writer, (2)); // ?
      WriteToFileBE<uint16_t>(writer, (0)); // ?
      WriteToFileBE<uint16_t>(writer, (0)); // ?
      WriteToFileBE<uint16_t>(writer, (255)); // ?
      WriteToFileBE<uint16_t>(writer, (255)); // ?

      WriteToFileBE<uint8_t>(writer, (1)); // ?
      WriteToFileBE<uint8_t>(writer, (1)); // ?
      WriteToFileBE<uint32_t>(writer, (0)); // ?
      WriteToFileBE<uint32_t>(writer, (0)); // ?

      WriteToFileBE<float32_t>(writer, (16.0)); // ?
      WriteToFileBE<uint32_t>(writer, (1)); // ?
      WriteToFileBE<uint32_t>(writer, (1)); // ?
      WriteToFileBE<float32_t>(writer, (1.0)); // ?
    }
    {
      // HDR alpha information?
      final key = keyValue('hdra');
      WriteToFileBE<uint32_t>(writer, key);

      WriteToFileBE<uint32_t>(writer, (6)); // number of following values
      WriteToFileBE<float32_t>(writer, (0.0)); // ?
      WriteToFileBE<float32_t>(writer, (20.0)); // ?
      WriteToFileBE<float32_t>(writer, (30.0)); // ?
      WriteToFileBE<float32_t>(writer, (0.0)); // ?
      WriteToFileBE<float32_t>(writer, (0.0)); // ?
      WriteToFileBE<float32_t>(writer, (1.0)); // ?

      WriteToFileBE<uint32_t>(writer, (0)); // ?
      WriteToFileBE<uint16_t>(writer, (0)); // ?
    }
  } else {
    // empty color mode data section
    WriteToFileBE<uint32_t>(writer, (0));
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
      final metaDataSize = hasMetaData ? GetMetaDataResourceSize(document) : 0;
      final iccProfileSize =
          hasIccProfile ? GetIccProfileResourceSize(document) : 0;
      final exifDataSize = hasExifData ? GetExifDataResourceSize(document) : 0;
      final thumbnailSize =
          hasThumbnail ? GetThumbnailResourceSize(document) : 0;
      final displayInfoSize =
          hasAlphaChannels ? GetDisplayInfoResourceSize(document) : 0;
      final channelNamesSize =
          hasAlphaChannels ? GetChannelNamesResourceSize(document) : 0;
      final unicodeChannelNamesSize =
          hasAlphaChannels ? GetUnicodeChannelNamesResourceSize(document) : 0;

      var sectionLength = 0;
      sectionLength += hasMetaData
          ? roundUpToMultiple(GetImageResourceSize() + metaDataSize, 2)
          : 0;
      sectionLength += hasIccProfile
          ? roundUpToMultiple(GetImageResourceSize() + iccProfileSize, 2)
          : 0;
      sectionLength += hasExifData
          ? roundUpToMultiple(GetImageResourceSize() + exifDataSize, 2)
          : 0;
      sectionLength += hasThumbnail
          ? roundUpToMultiple(GetImageResourceSize() + thumbnailSize, 2)
          : 0;
      sectionLength += hasAlphaChannels
          ? roundUpToMultiple(GetImageResourceSize() + displayInfoSize, 2)
          : 0;
      sectionLength += hasAlphaChannels
          ? roundUpToMultiple(GetImageResourceSize() + channelNamesSize, 2)
          : 0;
      sectionLength += hasAlphaChannels
          ? roundUpToMultiple(
              GetImageResourceSize() + unicodeChannelNamesSize, 2)
          : 0;

      // image resource section starts with length of the whole section
      WriteToFileBE<uint32_t>(writer, sectionLength);

      if (hasMetaData) {
        writeImageResource(writer, ImageResource.XMP_METADATA, metaDataSize);

        final start = writer.getPosition();
        {
          writer.Write(XMP_HEADER, XMP_HEADER.length);
          for (var i = 0; i < document.attributeCount; ++i) {
            writer.Write('<xmp:', 5);
            writer.Write(document.attributes[i].name,
                ((document.attributes[i].name).length));
            writer.Write('>', 1);
            writer.Write(document.attributes[i].value,
                ((document.attributes[i].value).length));
            writer.Write('</xmp:', 6);
            writer.Write(document.attributes[i].name,
                ((document.attributes[i].name).length));
            writer.Write('>\n', 2);
          }
          writer.Write(XMP_FOOTER, XMP_FOOTER.length);
        }
        final bytesWritten = writer.getPosition() - start;
        if (bytesWritten & 1 != 0) {
          // write padding byte
          WriteToFileBE<uint8_t>(writer, (0));
        }
      }

      if (hasIccProfile) {
        writeImageResource(writer, ImageResource.ICC_PROFILE, iccProfileSize);

        final start = writer.getPosition();
        {
          writer.Write(document.iccProfile, document.sizeOfICCProfile);
        }
        final bytesWritten = writer.getPosition() - start;
        if (bytesWritten & 1 != 0) {
          // write padding byte
          WriteToFileBE<uint8_t>(writer, (0));
        }
      }

      if (hasExifData) {
        writeImageResource(writer, ImageResource.EXIF_DATA, exifDataSize);

        final start = writer.getPosition();
        {
          writer.Write(document.exifData, document.sizeOfExifData);
        }
        final bytesWritten = writer.getPosition() - start;
        if (bytesWritten & 1 != 0) {
          // write padding byte
          WriteToFileBE<uint8_t>(writer, (0));
        }
      }

      if (hasThumbnail) {
        writeImageResource(
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

          WriteToFileBE<uint32_t>(writer, format);
          WriteToFileBE<uint32_t>(writer, document.thumbnail.width);
          WriteToFileBE<uint32_t>(writer, document.thumbnail.height);
          WriteToFileBE<uint32_t>(writer, widthInBytes);
          WriteToFileBE<uint32_t>(writer, totalSize);
          WriteToFileBE<uint32_t>(writer, document.thumbnail.binaryJpegSize);
          WriteToFileBE<uint16_t>(writer, bitsPerPixel);
          WriteToFileBE<uint16_t>(writer, planeCount);

          writer.Write(
              document.thumbnail.binaryJpeg, document.thumbnail.binaryJpegSize);
        }
        final bytesWritten = writer.getPosition() - start;
        if (bytesWritten & 1 != 0) {
          // write padding byte
          WriteToFileBE<uint8_t>(writer, (0));
        }
      }

      if (hasAlphaChannels) {
        // write display info
        {
          writeImageResource(
              writer, ImageResource.DISPLAY_INFO, displayInfoSize);

          final start = writer.getPosition();

          // version
          WriteToFileBE<uint32_t>(writer, (1));

          // per channel data
          for (var i = 0; i < document.alphaChannelCount; ++i) {
            var channel = document.alphaChannels[i];
            WriteToFileBE<uint16_t>(writer, channel.colorSpace);
            WriteToFileBE<uint16_t>(writer, channel.color[0]);
            WriteToFileBE<uint16_t>(writer, channel.color[1]);
            WriteToFileBE<uint16_t>(writer, channel.color[2]);
            WriteToFileBE<uint16_t>(writer, channel.color[3]);
            WriteToFileBE<uint16_t>(writer, channel.opacity);
            WriteToFileBE<uint8_t>(writer, channel.mode);
          }

          final bytesWritten = writer.getPosition() - start;
          if (bytesWritten & 1 != 0) {
            // write padding byte
            WriteToFileBE<uint8_t>(writer, (0));
          }
        }

        // write channel names
        {
          writeImageResource(writer, ImageResource.ALPHA_CHANNEL_ASCII_NAMES,
              channelNamesSize);

          final start = writer.getPosition();

          for (var i = 0; i < document.alphaChannelCount; ++i) {
            WriteToFileBE<uint8_t>(
                writer, (document.alphaChannels[i].asciiName.length));
            writer.Write(document.alphaChannels[i].asciiName,
                (document.alphaChannels[i].asciiName.length));
          }

          final bytesWritten = writer.getPosition() - start;
          if (bytesWritten & 1 != 0) {
            // write padding byte
            WriteToFileBE<uint8_t>(writer, (0));
          }
        }

        // write unicode channel names
        {
          writeImageResource(writer, ImageResource.ALPHA_CHANNEL_UNICODE_NAMES,
              unicodeChannelNamesSize);

          final start = writer.getPosition();

          for (var i = 0; i < document.alphaChannelCount; ++i) {
            // PSD expects UTF-16 strings, followed by a null terminator
            final length = document.alphaChannels[i].asciiName.length;
            WriteToFileBE<uint32_t>(writer, (length + 1));

            final asciiStr = document.alphaChannels[i].asciiName;
            for (var j = 0; j < length; ++j) {
              final unicodeGlyph = asciiStr.codeUnitAt(j);
              WriteToFileBE<uint16_t>(writer, unicodeGlyph);
            }

            WriteToFileBE<uint16_t>(writer, (0));
          }

          final bytesWritten = writer.getPosition() - start;
          if (bytesWritten & 1 != 0) {
            // write padding byte
            WriteToFileBE<uint8_t>(writer, (0));
          }
        }
      }
    } else {
      // no image resources
      WriteToFileBE<uint32_t>(writer, (0));
    }
  }

  // layer mask section
  var layerInfoSectionLength = getLayerInfoSectionLength(document);

  // layer info section must be padded to a multiple of 4
  var paddingNeeded =
      roundUpToMultiple(layerInfoSectionLength, 4) - layerInfoSectionLength;
  layerInfoSectionLength += paddingNeeded;

  final is8BitData = (document.bitsPerChannel == 8);
  if (is8BitData) {
    // 8-bit data
    // layer mask section length also includes global layer mask info marker. layer info follows directly after that
    final layerMaskSectionLength = layerInfoSectionLength + 4;
    WriteToFileBE<uint32_t>(writer, layerMaskSectionLength);
  } else {
    // 16-bit and 32-bit layer data is stored in Additional Layer Information, so we leave the following layer info section empty
    final layerMaskSectionLength = layerInfoSectionLength + 4 * 5;
    WriteToFileBE<uint32_t>(writer, layerMaskSectionLength);

    // empty layer info section
    WriteToFileBE<uint32_t>(writer, (0));

    // empty global layer mask info
    WriteToFileBE<uint32_t>(writer, (0));

    // additional layer information
    final signature = keyValue('8BIM');
    WriteToFileBE<uint32_t>(writer, signature);

    if (document.bitsPerChannel == 16) {
      final key = keyValue('Lr16');
      WriteToFileBE<uint32_t>(writer, key);
    } else if (document.bitsPerChannel == 32) {
      final key = keyValue('Lr32');
      WriteToFileBE<uint32_t>(writer, key);
    }
  }

  WriteToFileBE<uint32_t>(writer, layerInfoSectionLength);

  // layer count
  WriteToFileBE<uint16_t>(writer, document.layerCount);

  // per-layer info
  for (var i = 0; i < document.layerCount; ++i) {
    var layer = document.layers[i];
    WriteToFileBE<int32_t>(writer, layer.top);
    WriteToFileBE<int32_t>(writer, layer.left);
    WriteToFileBE<int32_t>(writer, layer.bottom);
    WriteToFileBE<int32_t>(writer, layer.right);

    final channelCount = getChannelCount(layer);
    WriteToFileBE<uint16_t>(writer, channelCount);

    // per-channel info
    for (var j = 0; j < ExportLayer.MAX_CHANNEL_COUNT; ++j) {
      if (layer.channelData[j] != null) {
        final channelId = GetChannelId(j);
        WriteToFileBE<int16_t>(writer, channelId);

        // channel data always has a 2-byte compression type in front of the data
        final channelDataSize = layer.channelSize[j] + 2;
        WriteToFileBE<uint32_t>(writer, channelDataSize);
      }
    }

    // blend mode signature
    WriteToFileBE<uint32_t>(writer, keyValue('8BIM'));

    // blend mode data
    final opacity = 255;
    final clipping = 0;
    final flags = 0;
    final filler = 0;
    WriteToFileBE<uint32_t>(writer, keyValue('norm'));
    WriteToFileBE<uint8_t>(writer, opacity);
    WriteToFileBE<uint8_t>(writer, clipping);
    WriteToFileBE<uint8_t>(writer, flags);
    WriteToFileBE<uint8_t>(writer, filler);

    // extra data, including layer name
    final extraDataLength = getExtraDataLength(layer);
    WriteToFileBE<uint32_t>(writer, extraDataLength);

    final layerMaskDataLength = 0;
    WriteToFileBE<uint32_t>(writer, layerMaskDataLength);

    final layerBlendingRangesDataLength = 0;
    WriteToFileBE<uint32_t>(writer, layerBlendingRangesDataLength);

    // the layer name is stored as pascal string, padded to a multiple of 4
    final nameLength = ((layer.name.length));
    final paddedNameLength = roundUpToMultiple(nameLength + 1, 4);
    WriteToFileBE<uint8_t>(writer, nameLength);
    writer.Write(layer.name, paddedNameLength - 1);
  }

  // per-layer data
  for (var i = 0; i < document.layerCount; ++i) {
    var layer = document.layers[i];

    // per-channel data
    for (var j = 0; j < ExportLayer.MAX_CHANNEL_COUNT; ++j) {
      if (layer.channelData[j] != null) {
        WriteToFileBE<uint16_t>(writer, layer.channelCompression[j]);
        writer.Write(layer.channelData[j], layer.channelSize[j]);
      }
    }
  }

  // add padding to align layer info section to multiple of 4
  if (paddingNeeded != 0) {
    writer.Write(zeroes, paddingNeeded);
  }

  // global layer mask info
  final globalLayerMaskInfoLength = 0;
  WriteToFileBE<uint32_t>(writer, globalLayerMaskInfoLength);

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
    WriteToFileBE<uint16_t>(writer, (CompressionType.RAW));
    if (document.colorMode == ExportColorMode.GRAYSCALE) {
      final dataGray = document.mergedImageData[0] ?? emptyMemory;
      writer.Write(dataGray, size);
    } else if (document.colorMode == ExportColorMode.RGB) {
      final dataR = document.mergedImageData[0] ?? emptyMemory;
      final dataG = document.mergedImageData[1] ?? emptyMemory;
      final dataB = document.mergedImageData[2] ?? emptyMemory;
      writer.Write(dataR, size);
      writer.Write(dataG, size);
      writer.Write(dataB, size);
    }

    // write alpha channels
    for (var i = 0; i < document.alphaChannelCount; ++i) {
      writer.Write(document.alphaChannelData[i], size);
    }
  }
}

void WriteToFile(SyncFileWriter writer, Uint8List zeroes) {
  writer.Write(zeroes);
}

void WriteToFileBE<T extends NumDataType>(SyncFileWriter writer, num i) {
  switch (T) {
    case uint8_t:
    case int8_t:
    case uint16_t:
    case int16_t:
    case float32_t:
    case int32_t:
    case uint32_t:
    case float64_t:
    case int64_t:
    case uint64_t:
      var bd = ByteData(sizeof<T>());
      setByteData<T>(bd, i, Endian.big);
      writer.Write(bd, sizeof<T>());
      break;
    default:
      throw Error();
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int GetIccProfileResourceSize(ExportDocument document) {
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

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int GetChannelId(int channelIndex) {
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

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int GetExifDataResourceSize(ExportDocument document) {
  return document.sizeOfExifData;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int GetThumbnailResourceSize(ExportDocument document) {
  return document.thumbnail.binaryJpegSize + 28;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int getExtraDataLength(ExportLayer layer) {
  final nameLength = ((layer.name.length));
  final paddedNameLength = roundUpToMultiple(nameLength + 1, 4);

  // includes the lengths of the layer mask data and layer blending ranges data
  return (4 + 4 + paddedNameLength);
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int GetDisplayInfoResourceSize(ExportDocument document) {
  // display info consists of 4-byte version, followed by 13 bytes per channel
  return sizeof<uint32_t>() + 13 * document.alphaChannelCount;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int GetChannelNamesResourceSize(ExportDocument document) {
  var size = 0;
  for (var i = 0; i < document.alphaChannelCount; ++i) {
    size += document.alphaChannels[i].asciiName.length + 1;
  }

  return (size);
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int GetUnicodeChannelNamesResourceSize(ExportDocument document) {
  var size = 0;
  for (var i = 0; i < document.alphaChannelCount; ++i) {
    // unicode strings are null terminated
    size += (document.alphaChannels[i].asciiName.length + 1) * 2 + 4;
  }

  return size;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int GetImageResourceSize() {
  var size = 0;
  size += sizeof<uint32_t>(); // signature
  size += sizeof<uint16_t>(); // resource ID
  size += 2; // padded name, 2 zero bytes
  size += sizeof<uint32_t>(); // resource size

  return size;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
void writeImageResource(SyncFileWriter writer, int id, int resourceSize) {
  final signature = keyValue('8BIM');
  WriteToFileBE<uint32_t>(writer, signature);
  WriteToFileBE<uint16_t>(writer, id);

  // padded name, unused
  WriteToFileBE<uint8_t>(writer, (0));
  WriteToFileBE<uint8_t>(writer, (0));

  WriteToFileBE<uint32_t>(writer, resourceSize);
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int getLayerInfoSectionLength(ExportDocument document) {
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
        getExtraDataLength(layer) +
        4;
    size += getChannelDataSize(layer) + getChannelCount(layer) * 2;
  }

  return size;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int getChannelDataSize(ExportLayer layer) {
  var size = 0;
  for (var i = 0; i < ExportLayer.MAX_CHANNEL_COUNT; ++i) {
    if (layer.channelData[i] != null) {
      size += layer.channelSize[i];
    }
  }

  return size;
}
