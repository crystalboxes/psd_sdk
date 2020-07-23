import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'package:psd_sdk/src/channel.dart';
import 'package:psd_sdk/src/image_util.dart';
import 'package:psd_sdk/src/key.dart';
import 'package:psd_sdk/src/log.dart';

import 'allocator.dart';
import 'bit_util.dart';
import 'channel_type.dart';
import 'compression_type.dart';
import 'data_types.dart';
import 'document.dart';
import 'file.dart';
import 'layer.dart';
import 'layer_mask.dart';
import 'layer_mask_section.dart';
import 'layer_type.dart';
import 'sync_file_reader.dart';

LayerMaskSection parseLayerMaskSection(
    Document document, File file, Allocator allocator) {
  // if there are no layers or masks, this section is just 4 bytes: the length field, which is set to zero.
  final section = document.layerMaskInfoSection;
  if (section.length == 0) {
    psdError(['PSD', 'Document does not contain a layer mask section.']);
    return null;
  }

  final reader = SyncFileReader(file);
  reader.setPosition(section.offset);

  final layerInfoSectionLength = reader.readUint32();
  final layerMaskSection = parseLayer(document, reader, allocator,
      section.offset, section.length, layerInfoSectionLength);

  // build the layer hierarchy
  if (layerMaskSection != null && layerMaskSection.layers != null) {
    var layerStack = List<Layer>(256);
    layerStack[0] = null;
    var stackIndex = 0;

    for (var i = 0; i < layerMaskSection.layerCount; ++i) {
      // note that it is much easier to build the hierarchy by traversing the layers backwards
      var layer = layerMaskSection.layers[layerMaskSection.layerCount - i - 1];

      assert(
          stackIndex >= 0 && stackIndex < 256, 'Stack index is out of bounds.');
      layer.parent = layerStack[stackIndex];

      var width = Ref(0);
      var height = Ref(0);
      GetExtents(layer, width, height);

      final isGroupStart = (layer.type == LayerType.OPEN_FOLDER) ||
          (layer.type == LayerType.CLOSED_FOLDER);
      final isGroupEnd = (layer.type == LayerType.SECTION_DIVIDER);
      if (isGroupEnd) {
        --stackIndex;
      } else if (isGroupStart) {
        ++stackIndex;
        layerStack[stackIndex] = layer;
      }
    }
  }

  return layerMaskSection;
}

LayerMaskSection parseLayer(
    Document document,
    SyncFileReader reader,
    Allocator allocator,
    int sectionOffset,
    int sectionLength,
    int layerLength) {
  var layerMaskSection = LayerMaskSection();
  layerMaskSection.layers = null;
  layerMaskSection.overlayColorSpace = 0;
  layerMaskSection.opacity = 0;
  layerMaskSection.kind = 128;
  layerMaskSection.hasTransparencyMask = false;

  if (layerLength != 0) {
    // read the layer count. if it is a negative number, its absolute value is the number of layers and the
    // first alpha channel contains the transparency data for the merged result.
    // this will also be reflected in the channelCount of the document.
    var layerCount = reader.readInt16();

    layerMaskSection.hasTransparencyMask = (layerCount < 0);
    if (layerCount < 0) {
      layerCount = -layerCount;
    }

    layerMaskSection.layers = List(layerCount);

    // read layer record for each layer
    for (var i = 0; i < layerMaskSection.layerCount; ++i) {
      layerMaskSection.layers[i] = Layer();
      final layer = layerMaskSection.layers[i];

      layer.parent = null;
      layer.utf16Name = null;
      layer.layerMask = null;
      layer.vectorMask = null;
      layer.type = LayerType.ANY;

      layer.top = reader.readInt32();
      layer.left = reader.readInt32();
      layer.bottom = reader.readInt32();
      layer.right = reader.readInt32();

      // number of channels in the layer.
      // this includes channels for transparency, layer, and vector masks, if any.
      final channelCount = reader.readUint16();
      layer.channels = List(channelCount);

      // parse each channel
      for (var j = 0; j < channelCount; ++j) {
        layer.channels[j] = Channel();
        final channel = layer.channels[j];
        channel.fileOffset = 0;
        channel.data = null;
        channel.type = reader.readInt16();
        channel.size = reader.readUint32();
      }

      // blend mode signature must be '8BIM'
      final blendModeSignature = reader.readUint32();
      if (blendModeSignature != keyValue('8BIM')) {
        psdError([
          'LayerMaskSection',
          'Layer mask info section seems to be corrupt, signature does not match "8BIM".'
        ]);
        return layerMaskSection;
      }

      layer.blendModeKey = reader.readUint32();
      layer.opacity = reader.readByte();
      layer.clipping = reader.readByte();

      // extract flag information into layer struct
      {
        final flags = reader.readByte();
        layer.isVisible = !((flags & (1 << 1)) != 0);
      }

      // skip filler byte
      {
        // ignore: unused_local_variable
        final filler = reader.readByte();
      }

      final extraDataLength = reader.readUint32();
      final layerMaskDataLength = reader.readUint32();

      // the layer mask data section is weird. it may contain extra data for masks, such as density and feather parameters.
      // there are 3 main possibilities:
      //	*) length == zero		.	skip this section
      //	*) length == [20, 28]	.	there is one mask, and that could be either a layer or vector mask.
      //								the mask flags give rise to mask parameters. they store the mask type, and additional parameters, if any.
      //								there might be some padding at the end of this section, and its size depends on which parameters are there.
      //	*) length == [36, 56]	.	there are two masks. the first mask has parameters, but does NOT store flags yet.
      //								instead, there comes a second section with the same info (flags, default color, rectangle), and
      //								the parameters follow after that. there is also padding at the end of this second section.
      if (layerMaskDataLength != 0) {
        // there can be at most two masks, one layer and one vector mask
        final maskData = <MaskData>[MaskData(), MaskData()];
        var maskCount = 1;

        var layerFeather = Ref(0.0);
        var vectorFeather = Ref(0.0);
        var layerDensity = Ref(0);
        var vectorDensity = Ref(0);

        var toRead = layerMaskDataLength;

        // enclosing rectangle
        toRead -= readMaskRectangle(reader, maskData[0]);

        maskData[0].defaultColor = reader.readByte();
        toRead -= sizeof<uint8_t>();

        final maskFlags = reader.readByte();
        toRead -= sizeof<uint8_t>();

        maskData[0].isVectorMask = (maskFlags & (1 << 3)) != 0;
        var maskHasParameters = (maskFlags & (1 << 4)) != 0;
        if (maskHasParameters && (layerMaskDataLength <= 28)) {
          toRead -= readMaskParameters(
              reader, layerDensity, layerFeather, vectorDensity, vectorFeather);
        }

        // check if there is enough data left for another section of mask data
        if (toRead >= 18) {
          // in case there is still data left to read, the following values are for the real layer mask.
          // the data we just read was for the vector mask.
          maskCount = 2;

          final realFlags = reader.readByte();
          toRead -= sizeof<uint8_t>();

          maskData[1].defaultColor = reader.readByte();
          toRead -= sizeof<uint8_t>();

          toRead -= readMaskRectangle(reader, maskData[1]);

          maskData[1].isVectorMask = (realFlags & (1 << 3)) != 0;

          // note the OR here. whether the following section has mask parameter data or not is influenced by
          // the availability of parameter data of the previous mask!
          maskHasParameters |= ((realFlags & (1 << 4)) != 0);
          if (maskHasParameters) {
            toRead -= readMaskParameters(reader, layerDensity, layerFeather,
                vectorDensity, vectorFeather);
          }
        }

        // skip the remaining padding bytes, if any
        assert(toRead >= 0, 'Parsing failed, $toRead bytes left.');
        reader.skip(toRead);

        // apply mask data to our own data structures
        for (var mask = 0; mask < maskCount; ++mask) {
          final isVectorMask = maskData[mask].isVectorMask;
          if (isVectorMask) {
            assert(layer.vectorMask == null, 'A vector mask already exists.');
            layer.vectorMask = VectorMask();
            layer.vectorMask.data = null;
            layer.vectorMask.fileOffset = 0;
            applyMaskData(maskData[mask], vectorFeather.value,
                vectorDensity.value, layer.vectorMask);
          } else {
            assert(layer.layerMask == null, 'A layer mask already exists.');
            layer.layerMask = LayerMask();
            layer.layerMask.data = null;
            layer.layerMask.fileOffset = 0;
            applyMaskData(maskData[mask], layerFeather.value,
                layerDensity.value, layer.layerMask);
          }
        }
      }

      // skip blending ranges data, we are not interested in that for now
      final layerBlendingRangesDataLength = reader.readUint32();
      reader.skip(layerBlendingRangesDataLength);

      // the layer name is stored as pascal string, padded to a multiple of 4
      final nameLength = reader.readByte();
      final paddedNameLength = roundUpToMultiple(nameLength + 1, 4);

      layer.name = String.fromCharCodes(
          reader.readBytes(paddedNameLength - 1).where((x) => x != 0x00));

      // read Additional Layer Information that exists since Photoshop 4.0.
      // getting the size of this data is a bit awkward, because it's not stored explicitly somewhere. furthermore,
      // the PSD format sometimes includes the 4-byte length in its section size, and sometimes not.
      final additionalLayerInfoSize = extraDataLength -
          layerMaskDataLength -
          layerBlendingRangesDataLength -
          paddedNameLength -
          8;
      var toRead = additionalLayerInfoSize;

      while (toRead > 0) {
        final signature = reader.readUint32();
        if (signature != keyValue('8BIM')) {
          psdError([
            'LayerMaskSection',
            'Additional Layer Information section seems to be corrupt, signature does not match "8BIM".'
          ]);
          return layerMaskSection;
        }

        final key = reader.readUint32();

        // length needs to be rounded to a multiple of 4
        var length = reader.readUint32();
        length = roundUpToMultiple(length, 4);

        // read "Section divider setting" to identify whether a layer is a group, or a section divider
        if (key == keyValue('lsct')) {
          layer.type = reader.readUint32();

          // skip the rest of the data
          reader.skip(length - 4);
        }
        // read Unicode layer name
        else if (key == keyValue('luni')) {
          // PSD Unicode strings store 4 bytes for the number of characters, NOT bytes, followed by
          // 2-byte UTF16 Unicode data without the terminating null.
          final characterCountWithoutNull = reader.readUint32();
          layer.utf16Name = Uint16List(characterCountWithoutNull + 1);

          for (var c = 0; c < characterCountWithoutNull; ++c) {
            layer.utf16Name[c] = reader.readUint16();
          }
          layer.utf16Name[characterCountWithoutNull] = 0;

          // skip possible padding bytes
          reader.skip(
              length - 4 - characterCountWithoutNull * sizeof<uint16_t>());
        } else {
          reader.skip(length);
        }

        toRead -= 3 * sizeof<uint32_t>() + length;
      }
    }

    // walk through the layers and channels, but don't extract their data just yet. only save the file offset for extracting the
    // data later.
    for (var i = 0; i < layerMaskSection.layerCount; ++i) {
      final layer = layerMaskSection.layers[i];
      final channelCount = layer.channelCount;
      for (var j = 0; j < channelCount; ++j) {
        var channel = layer.channels[j];
        channel.fileOffset = reader.getPosition();
        reader.skip(channel.size);
      }
    }
  }

  if (sectionLength > 0) {
    // start loading at the global layer mask info section, located after the Layer Information Section.
    // note that the 4 bytes that stored the length of the section are not included in the length itself.
    final globalInfoSectionOffset = sectionOffset + layerLength + 4;
    reader.setPosition(globalInfoSectionOffset);

    // work out how many bytes are left to read at this point. we need that to figure out the size of the last
    // optional section, the Additional Layer Information.
    if (sectionOffset + sectionLength > globalInfoSectionOffset) {
      var toRead = sectionOffset + sectionLength - globalInfoSectionOffset;
      final globalLayerMaskLength = reader.readUint32();
      toRead -= sizeof<uint32_t>();

      if (globalLayerMaskLength != 0) {
        layerMaskSection.overlayColorSpace = reader.readUint16();

        // 4*2 byte color components
        reader.skip(8);

        layerMaskSection.opacity = reader.readUint16();
        layerMaskSection.kind = reader.readByte();

        toRead -= 2 * sizeof<uint16_t>() + sizeof<uint8_t>() + 8;

        // filler bytes (zeroes)
        final remaining = globalLayerMaskLength -
            2 * sizeof<uint16_t>() -
            sizeof<uint8_t>() -
            8;
        reader.skip(remaining);

        toRead -= remaining;
      }

      // are there still bytes left to read? then this is the Additional Layer Information that exists since Photoshop 4.0.
      while (toRead > 0) {
        final signature = reader.readUint32();
        if (signature != keyValue('8BIM')) {
          psdError([
            'AdditionalLayerInfo',
            'Additional Layer Information section seems to be corrupt, signature does not match "8BIM".'
          ]);
          return layerMaskSection;
        }

        final key = reader.readUint32();

        // again, length is rounded to a multiple of 4
        var length = reader.readUint32();
        length = roundUpToMultiple(length, 4);

        if (key == keyValue('Lr16')) {
          final offset = reader.getPosition();
          destroyLayerMaskSection(layerMaskSection, allocator);
          layerMaskSection =
              parseLayer(document, reader, allocator, 0, 0, length);
          reader.setPosition(offset + length);
        } else if (key == keyValue('Lr32')) {
          final offset = reader.getPosition();
          destroyLayerMaskSection(layerMaskSection, allocator);
          layerMaskSection =
              parseLayer(document, reader, allocator, 0, 0, length);
          reader.setPosition(offset + length);
        } else if (key == keyValue('vmsk')) {
          // TODO: could read extra vector mask data here
          reader.skip(length);
        } else if (key == keyValue('lnk2')) {
          // TODO: could read individual smart object layer data here
          reader.skip(length);
        } else {
          reader.skip(length);
        }

        toRead -= 3 * sizeof<uint32_t>() + length;
      }
    }
  }

  return layerMaskSection;
}

class MaskData {
  int top;
  int left;
  int bottom;
  int right;
  int defaultColor;
  bool isVectorMask;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int readMaskRectangle(SyncFileReader reader, MaskData maskData) {
  maskData.top = reader.readInt32();
  maskData.left = reader.readInt32();
  maskData.bottom = reader.readInt32();
  maskData.right = reader.readInt32();

  return 4 * sizeof<int32_t>();
}

class Ref<T> {
  Ref([this.value]);
  T value;
  void set(T val) {
    value = val;
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
void applyMaskData<T extends Mask>(
    MaskData maskData, double feather, int density, T layerMask) {
  layerMask.top = maskData.top;
  layerMask.left = maskData.left;
  layerMask.bottom = maskData.bottom;
  layerMask.right = maskData.right;
  layerMask.feather = feather;
  layerMask.density = density;
  layerMask.defaultColor = maskData.defaultColor;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int readMaskDensity(SyncFileReader reader, Ref<int> density) {
  density.set(reader.readByte());
  return sizeof<uint8_t>();
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int readMaskFeather(SyncFileReader reader, Ref<double> feather) {
  feather.set(reader.readFloat64());
  return sizeof<float64_t>();
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int readMaskParameters(
    SyncFileReader reader,
    Ref<int> layerDensity,
    Ref<double> layerFeather,
    Ref<int> vectorDensity,
    Ref<double> vectorFeather) {
  var bytesRead = 0;

  final flags = reader.readByte();
  bytesRead += sizeof<uint8_t>();

  final hasUserDensity = (flags & (1 << 0)) != 0;
  final hasUserFeather = (flags & (1 << 1)) != 0;
  final hasVectorDensity = (flags & (1 << 2)) != 0;
  final hasVectorFeather = (flags & (1 << 3)) != 0;
  if (hasUserDensity) {
    bytesRead += readMaskDensity(reader, layerDensity);
  }
  if (hasUserFeather) {
    bytesRead += readMaskFeather(reader, layerFeather);
  }
  if (hasVectorDensity) {
    bytesRead += readMaskDensity(reader, vectorDensity);
  }
  if (hasVectorFeather) {
    bytesRead += readMaskFeather(reader, vectorFeather);
  }

  return bytesRead;
}

void destroyLayerMaskSection(LayerMaskSection section, Allocator allocator) {}

Uint8List endianConvert<T extends NumDataType>(Uint8List src, width, height) {
  var byteData = src.buffer.asByteData();

  final sizeofT = sizeof<T>();
  final size = width * height;
  var copied = Uint8List(size * sizeofT);
  var data = getTypedList<T>(copied) as List;

  for (var i = 0; i < size; ++i) {
    var pos = sizeofT * i;
    data[i] = getElemInHostEndian<T>(byteData, pos);
  }
  return copied;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
Uint8List readChannelDataRaw<T extends NumDataType>(
    SyncFileReader reader, Allocator allocator, int width, int height) {
  final size = width * height;
  if (size > 0) {
    var planarData = reader.readBytes(size * sizeof<T>());
    return endianConvert<T>(planarData, width, height);
  }

  return null;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
Uint8List readChannelDataRLE<T extends NumDataType>(
    SyncFileReader reader, Allocator allocator, int width, int height) {
  // the RLE-compressed data is preceded by a 2-byte data count for each scan line
  final size = width * height;

  var rleDataSize = 0;
  for (var i = 0; i < height; ++i) {
    final dataCount = reader.readUint16();
    rleDataSize += dataCount;
  }

  if (rleDataSize > 0) {
    var planarData = Uint8List(size * sizeof<T>());

    // decompress RLE
    var rleData = reader.readBytes(rleDataSize);
    {
      DecompressRle(rleData, rleDataSize, planarData, planarData.length);
    }
    allocator.free(rleData);

    endianConvert<T>(planarData, width, height);

    return planarData;
  }

  return null;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
Uint8List readChannelDataZip<T extends NumDataType>(SyncFileReader reader,
    Allocator allocator, int width, int height, int channelSize) {
  if (channelSize > 0) {
    final size = width * height;

    var zipData = reader.readBytes(channelSize);

    // the zipped data stream has a zlib-header
    var planarData = Uint8List.fromList(ZLibDecoder().decodeBytes(zipData));
    if (planarData == null || planarData.length != size * sizeof<T>()) {
      psdError(['PsdExtract', 'Error while unzipping channel data.']);
    }

    allocator.free(zipData);

    endianConvert<T>(planarData, width, height);

    return planarData;
  }

  return null;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
Uint8List readChannelDataZipPrediction<T extends NumDataType>(
    SyncFileReader reader,
    Allocator allocator,
    int width,
    int height,
    int channelSize) {
  if (channelSize > 0) {
    final size = width * height;

    var zipData = reader.readBytes(channelSize);

    // the zipped data stream has a zlib-header
    var planarData = Uint8List.fromList(ZLibDecoder().decodeBytes(zipData));
    if (planarData == null || planarData.length != size * sizeof<T>()) {
      // final status = tinfl_decompress_mem_to_mem(planarData, size * sizeof<T>(),
      //     zipData, channelSize, TINFL_FLAG_PARSE_ZLIB_HEADER);
      // if (status == TINFL_DECOMPRESS_MEM_TO_MEM_FAILED) {
      psdError(['PsdExtract', 'Error while unzipping channel data.']);
    }

    allocator.free(zipData);

    // the data generated by applying the prediction data is already in little-endian format, so it doesn't have to be
    // endian converted further.
    applyPrediction<T>(allocator, planarData, width, height);

    return planarData;
  }

  return null;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
void applyPrediction<T extends NumDataType>(
    Allocator allocator, Uint8List planarData, int width, int height) {
  assert(sizeof<T>() == -1, 'Unknown data type.');
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
void extractLayer(
    Document document, File file, Allocator allocator, Layer layer) {
  var reader = SyncFileReader(file);

  final channelCount = layer.channelCount;
  for (var i = 0; i < channelCount; ++i) {
    var channel = layer.channels[i];
    reader.setPosition(channel.fileOffset);

    var width = Ref(0);
    var height = Ref(0);
    GetChannelExtents(layer, channel, width, height);

    // channel data is stored in 4 different formats, which is denoted by a 2-byte integer
    assert(channel.data == null, 'Channel data has already been loaded.');
    final compressionType = reader.readUint16();
    if (compressionType == CompressionType.RAW) {
      if (document.bitsPerChannel == 8) {
        channel.data = readChannelDataRaw<uint8_t>(
            reader, allocator, width.value, height.value);
      } else if (document.bitsPerChannel == 16) {
        channel.data = readChannelDataRaw<uint16_t>(
            reader, allocator, width.value, height.value);
      } else if (document.bitsPerChannel == 32) {
        channel.data = readChannelDataRaw<float32_t>(
            reader, allocator, width.value, height.value);
      }
    } else if (compressionType == CompressionType.RLE) {
      if (document.bitsPerChannel == 8) {
        channel.data = readChannelDataRLE<uint8_t>(
            reader, allocator, width.value, height.value);
      } else if (document.bitsPerChannel == 16) {
        channel.data = readChannelDataRLE<uint16_t>(
            reader, allocator, width.value, height.value);
      } else if (document.bitsPerChannel == 32) {
        channel.data = readChannelDataRLE<float32_t>(
            reader, allocator, width.value, height.value);
      }
    } else if (compressionType == CompressionType.ZIP) {
      // note that we need to subtract 2 bytes from the channel data size because we already read the uint16_t
      // for the compression type.
      assert(channel.size >= 2, 'Invalid channel data size ${channel.size}');
      final channelDataSize = channel.size - 2;
      if (document.bitsPerChannel == 8) {
        channel.data = readChannelDataZip<uint8_t>(
            reader, allocator, width.value, height.value, channelDataSize);
      } else if (document.bitsPerChannel == 16) {
        channel.data = readChannelDataZip<uint16_t>(
            reader, allocator, width.value, height.value, channelDataSize);
      } else if (document.bitsPerChannel == 32) {
        // note that this is NOT a bug.
        // in 32-bit mode, Photoshop always interprets ZIP compression as being ZIP_WITH_PREDICTION, presumably to get better compression when writing files.
        channel.data = readChannelDataZipPrediction<float32_t>(
            reader, allocator, width.value, height.value, channelDataSize);
      }
    } else if (compressionType == CompressionType.ZIP_WITH_PREDICTION) {
      // note that we need to subtract 2 bytes from the channel data size because we already read the uint16_t
      // for the compression type.
      assert(channel.size >= 2, 'Invalid channel data size ${channel.size}');
      final channelDataSize = channel.size - 2;
      if (document.bitsPerChannel == 8) {
        channel.data = readChannelDataZipPrediction<uint8_t>(
            reader, allocator, width.value, height.value, channelDataSize);
      } else if (document.bitsPerChannel == 16) {
        channel.data = readChannelDataZipPrediction<uint16_t>(
            reader, allocator, width.value, height.value, channelDataSize);
      } else if (document.bitsPerChannel == 32) {
        channel.data = readChannelDataZipPrediction<float32_t>(
            reader, allocator, width.value, height.value, channelDataSize);
      }
    } else {
      assert(false, 'Unsupported compression type $compressionType');
      return;
    }

    // if the channel doesn't have any data assigned to it, check if it is a mask channel of any kind.
    // layer masks sometimes don't have any planar data stored for them, because they are
    // e.g. pure black or white, which means they only get assigned a default color.
    if (channel.data == null) {
      if (channel.type < 0) {
        // this is a layer mask, so create planar data for it
        final dataSize =
            width.value * height.value * document.bitsPerChannel / 8;
        final channelData = Uint8List(dataSize.toInt());
        var defaultColor = GetChannelDefaultColor(layer, channel);
        for (var x = 0; x < channelData.length; x++) {
          channelData[x] = defaultColor;
        }
        channel.data = channelData;
      } else {
        // for layers like groups and group end markers ("</Layer group>") it is ok to not store any data
      }
    }
  }

  // now move channel data to our own data structures for layer and vector masks, invalidating the info stored in
  // that channel.
  for (var i = 0; i < channelCount; ++i) {
    var channel = layer.channels[i];
    if (channel.type == ChannelType.LAYER_OR_VECTOR_MASK) {
      if (layer.vectorMask != null) {
        // layer has a vector mask, so this type always denotes the vector mask
        assert(layer.layerMask.data == null,
            'Vector mask data has already been assigned.');
        MoveChannelToMask(channel, layer.vectorMask);
      } else if (layer.layerMask != null) {
        // we don't have a vector but a layer mask, so this type denotes the layer mask
        assert(layer.layerMask.data == null,
            'Layer mask data has already been assigned.');
        MoveChannelToMask(channel, layer.layerMask);
      } else {
        assert(false,
            'The code failed to create a mask for this type internally. This should never happen.');
      }
    } else if (channel.type == ChannelType.LAYER_MASK) {
      assert(layer.layerMask != null, 'Layer mask must already exist.');
      assert(layer.layerMask.data == null,
          'Layer mask data has already been assigned.');
      MoveChannelToMask(channel, layer.layerMask);
    } else {
      // this channel is either a color channel, or the transparency mask. those should be stored in our channel array,
      // so there's nothing to do.
    }
  }
}

void GetChannelExtents(
    Layer layer, Channel channel, Ref<int> width, Ref<int> height) {
  if (channel.type == ChannelType.TRANSPARENCY_MASK) {
    // the channel is the transparency mask, which has the same size as the layer
    return GetExtents(layer, width, height);
  } else if (channel.type == ChannelType.LAYER_OR_VECTOR_MASK) {
    // the channel is either the layer or vector mask, depending on how many masks there are in the layer.
    if (layer.vectorMask != null) {
      // a vector mask exists, so this always denotes a vector mask
      return GetExtents(layer.vectorMask, width, height);
    } else if (layer.layerMask != null) {
      // no vector mask exists, so the layer mask is the only mask left
      return GetExtents(layer.layerMask, width, height);
    }

    assert(false,
        'The code failed to create a mask for this type internally. This should never happen.');
    width.set(0);
    height.set(0);
    return;
  } else if (channel.type == ChannelType.LAYER_MASK) {
    // this type is only valid when there are two masks stored, in which case this always denotes the layer mask
    return GetExtents(layer.layerMask, width, height);
  }

  // this is a color channel which has the same size as the layer
  return GetExtents(layer, width, height);
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int GetWidth<T extends BoundsRect>(T data) {
  if (data.right > data.left) {
    return (data.right - data.left);
  }

  return 0;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int GetHeight<T extends BoundsRect>(T data) {
  if (data.bottom > data.top) {
    return (data.bottom - data.top);
  }

  return 0;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
void GetExtents<T extends BoundsRect>(T data, Ref<int> width, Ref<int> height) {
  width.set(GetWidth(data));
  height.set(GetHeight(data));
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
void MoveChannelToMask<T extends Mask>(Channel channel, T mask) {
  mask.data = channel.data;
  mask.fileOffset = channel.fileOffset;

  channel.data = null;
  channel.type = ChannelType.INVALID;
  channel.fileOffset = 0;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int GetChannelDefaultColor(Layer layer, Channel channel) {
  if (channel.type == ChannelType.TRANSPARENCY_MASK) {
    return 0;
  } else if (channel.type == ChannelType.LAYER_OR_VECTOR_MASK) {
    if (layer.vectorMask != null) {
      return layer.vectorMask.defaultColor;
    } else if (layer.layerMask != null) {
      return layer.layerMask.defaultColor;
    }

    assert(false,
        'The code failed to create a mask for this type internally. This should never happen.');
    return 0;
  } else if (channel.type == ChannelType.LAYER_MASK) {
    return layer.layerMask.defaultColor;
  }

  return 0;
}
