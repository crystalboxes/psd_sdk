import 'dart:typed_data';

import 'package:psd_sdk/psd_sdk.dart';
import 'tga_exporter.dart' as tga_exporter;
import 'dart:io' as io;

final int CHANNEL_NOT_FOUND = -1;

int findChannel(Layer layer, int channelType) {
  for (var i = 0; i < layer.channelCount; ++i) {
    var channel = layer.channels[i];
    if (channel.data != null && channel.type == channelType) {
      return i;
    }
  }

  return CHANNEL_NOT_FOUND;
}

String getSampleInputPath() {
  return 'example/';
}

String getSampleOutputPath() {
  return 'example/sample_output/';
}

Uint8List expandChannelToCanvas(
    Document document, dynamic layer, Channel channel) {
  var canvasData = Uint8List.fromList(List.filled(
      document.bitsPerChannel ~/ 8 * document.width * document.height, 0));
  if (copyLayerData(
    channel.data,
    canvasData,
    document.bitsPerChannel,
    layer.left,
    layer.top,
    layer.right,
    layer.bottom,
    document.width,
    document.height,
  )) {
    return canvasData;
  }
  return null;
}

Uint8List expandMaskToCanvas(Document document, Mask mask) {
  var canvasData = Uint8List.fromList(List.filled(
      document.bitsPerChannel ~/ 8 * document.width * document.height, 0));

  if (copyLayerData(mask.data, canvasData, document.bitsPerChannel, mask.left,
      mask.top, mask.right, mask.bottom, document.width, document.height)) {
    return canvasData;
  }

  return null;
}

int sampleReadPsd() {
  final srcPath = '${getSampleInputPath()}Sample.psd';

  var file = File();
  try {
    file.setByteData(io.File(srcPath).readAsBytesSync());
  } catch (e) {
    print('Cannot open file.');
    return 1;
  }

  final document = createDocument(file);
  if (document == null) {
    print('Cannot create document.');
    return 1;
  }

  // the sample only supports RGB colormode
  if (document.colorMode != ColorMode.RGB) {
    print('Document is not in RGB color mode.\n');
    return 1;
  }

  // extract image resources section.
  // this gives access to the ICC profile, EXIF data and XMP metadata.
  {
    var imageResourcesSection = parseImageResourcesSection(document, file);
    print('XMP metadata:');
    print(imageResourcesSection.xmpMetadata);
    print('\n');
  }

  var hasTransparencyMask = false;
  final layerMaskSection = parseLayerMaskSection(document, file);

  if (layerMaskSection != null) {
    hasTransparencyMask = layerMaskSection.hasTransparencyMask;

    // extract all layers one by one. this should be done in parallel for
    // maximum efficiency.
    for (var i = 0; i < layerMaskSection.layerCount; ++i) {
      var layer = layerMaskSection.layers[i];
      extractLayer(document, file, layer);

      // check availability of R, G, B, and A channels.
      // we need to determine the indices of channels individually, because
      // there is no guarantee that R is the first channel, G is the second, B
      // is the third, and so on.
      final indexR = findChannel(layer, ChannelType.R);
      final indexG = findChannel(layer, ChannelType.G);
      final indexB = findChannel(layer, ChannelType.B);
      final indexA = findChannel(layer, ChannelType.TRANSPARENCY_MASK);

      // note that channel data is only as big as the layer it belongs to, e.g.
      // it can be smaller or bigger than the canvas, depending on where it is
      // positioned. therefore, we use the provided utility functions to
      // expand/shrink the channel data to the canvas size. of course, you can
      // work with the channel data directly if you need to.
      var canvasData = List<Uint8List>(4);
      var channelCount = 0;
      if ((indexR != CHANNEL_NOT_FOUND) &&
          (indexG != CHANNEL_NOT_FOUND) &&
          (indexB != CHANNEL_NOT_FOUND)) {
        // RGB channels were found.
        canvasData[0] =
            expandChannelToCanvas(document, layer, layer.channels[indexR]);
        canvasData[1] =
            expandChannelToCanvas(document, layer, layer.channels[indexG]);
        canvasData[2] =
            expandChannelToCanvas(document, layer, layer.channels[indexB]);
        channelCount = 3;

        if (indexA != CHANNEL_NOT_FOUND) {
          // A channel was also found.
          canvasData[3] =
              expandChannelToCanvas(document, layer, layer.channels[indexA]);
          channelCount = 4;
        }
      }

      // interleave the different pieces of planar canvas data into one RGB or
      // RGBA image, depending on what channels we found, and what color mode
      // the document is stored in.
      // ignore: unused_local_variable

      final image = channelCount == 3
          ? interleaveRGB(canvasData[0], canvasData[1], canvasData[2],
              document.bitsPerChannel, 0, document.width, document.height)
          : interleaveRGBA(
              canvasData[0],
              canvasData[1],
              canvasData[2],
              canvasData[3],
              document.bitsPerChannel,
              document.width,
              document.height);

      final image8 = document.bitsPerChannel == 8 ? image : null;
      // ignore: unused_local_variable
      final image16 = document.bitsPerChannel == 16 ? image : null;
      // ignore: unused_local_variable
      final image32 = document.bitsPerChannel == 32 ? image : null;

      // get the layer name.
      // Unicode data is preferred because it is not truncated by Photoshop, but
      // unfortunately it is optional. fall back to the ASCII name in case no
      // Unicode name was found.
      String layerName;
      if (layer.utf16Name != null) {
        layerName =
            String.fromCharCodes(layer.utf16Name.where((x) => x != 0x00));
      } else {
        layerName = layer.name;
      }

      // at this point, image8, image16 or image32 store either a 8-bit, 16-bit,
      // or 32-bit image, respectively. the image data is stored in interleaved
      // RGB or RGBA, and has the size "document.width*document.height". it is
      // up to you to do whatever you want with the image data. in the sample,
      // we simply write the image to a .TGA file.
      if (channelCount == 3) {
        if (document.bitsPerChannel == 8) {
          var filename = '${getSampleOutputPath()}' 'layer${layerName}.tga';
          tga_exporter.saveRGB(
              filename, document.width, document.height, image8);
        }
      } else if (channelCount == 4) {
        if (document.bitsPerChannel == 8) {
          var filename = '${getSampleOutputPath()}' 'layer${layerName}.tga';
          tga_exporter.saveRGBA(
              filename, document.width, document.height, image8);
        }
      }

      // in addition to the layer data, we also want to extract the user and/or
      // vector mask. luckily, this has been handled already by the
      // ExtractLayer() function. we just need to check whether a mask exists.
      if (layer.layerMask != null) {
        // a layer mask exists, and data is available. work out the mask's
        // dimensions.
        final width = (layer.layerMask.right - layer.layerMask.left);
        final height = (layer.layerMask.bottom - layer.layerMask.top);

        // similar to layer data, the mask data can be smaller or bigger than
        // the canvas. the mask data is always single-channel (monochrome), and
        // has a width and height as calculated above.
        var maskData = layer.layerMask.data;
        {
          var filename =
              '${getSampleOutputPath()}' 'layer${layerName}' '_usermask.tga';
          tga_exporter.saveMonochrome(filename, width, height, maskData);
        }

        // use ExpandMaskToCanvas create an image that is the same size as the
        // canvas.
        var maskCanvasData = expandMaskToCanvas(document, layer.layerMask);
        {
          var filename =
              '${getSampleOutputPath()}canvas${layerName}_usermask.tga';
          tga_exporter.saveMonochrome(
              filename, document.width, document.height, maskCanvasData);
        }
      }

      if (layer.vectorMask != null) {
        // accessing the vector mask works exactly like accessing the layer
        // mask.
        final width = (layer.vectorMask.right - layer.vectorMask.left);
        final height = (layer.vectorMask.bottom - layer.vectorMask.top);

        var maskData = layer.vectorMask.data;
        {
          var filename =
              '${getSampleOutputPath()}' 'layer${layerName}' '_vectormask.tga';
          tga_exporter.saveMonochrome(filename, width, height, maskData);
        }

        var maskCanvasData = expandMaskToCanvas(document, layer.vectorMask);
        {
          var filename =
              '${getSampleOutputPath()}' 'canvas${layerName}' '_vectormask.tga';
          tga_exporter.saveMonochrome(
              filename, document.width, document.height, maskCanvasData);
        }
      }
    }

    // extract the image data section, if available. the image data section stores
    // the final, merged image, as well as additional alpha channels. this is only
    // available when saving the document with "Maximize Compatibility" turned on.
    if (document.imageDataSection.length != 0) {
      var imageData = parseImageDataSection(document, file);
      if (imageData != null) {
        // interleave the planar image data into one RGB or RGBA image.
        // store the rest of the (alpha) channels and the transparency mask
        // separately.
        final imageCount = imageData.imageCount;

        // note that an image can have more than 3 channels, but still no
        // transparency mask in case all extra channels are actual alpha channels.
        var isRgb = false;
        if (imageCount == 3) {
          // imageData.images[0], imageData.images[1] and imageData.images[2]
          // contain the R, G, and B channels of the merged image. they are always
          // the size of the canvas/document, so we can interleave them using
          // imageUtil::InterleaveRGB directly.
          isRgb = true;
        } else if (imageCount >= 4) {
          // check if we really have a transparency mask that belongs to the
          // "main" merged image.
          if (hasTransparencyMask) {
            // we have 4 or more images/channels, and a transparency mask.
            // this means that images 0-3 are RGBA, respectively.
            isRgb = false;
          } else {
            // we have 4 or more images stored in the document, but none of them
            // is the transparency mask. this means we are dealing with RGB (!)
            // data, and several additional alpha channels.
            isRgb = true;
          }
        }

        final image = isRgb
            ? interleaveRGB(
                imageData.images[0].data,
                imageData.images[1].data,
                imageData.images[2].data,
                0,
                document.bitsPerChannel,
                document.width,
                document.height)
            : interleaveRGBA(
                imageData.images[0].data,
                imageData.images[1].data,
                imageData.images[2].data,
                imageData.images[3].data,
                document.bitsPerChannel,
                document.width,
                document.height);

        final image8 = document.bitsPerChannel == 8 ? image : null;
        // ignore: unused_local_variable
        final image16 = document.bitsPerChannel == 16 ? image : null;
        // ignore: unused_local_variable
        final image32 = document.bitsPerChannel == 32 ? image : null;

        if (document.bitsPerChannel == 8) {
          var filename = '${getSampleOutputPath()}' 'merged.tga';
          if (isRgb) {
            tga_exporter.saveRGB(
                filename, document.width, document.height, image8);
          } else {
            tga_exporter.saveRGBA(
                filename, document.width, document.height, image8);
          }
        }

        // extract image resources in order to acquire the alpha channel names.
        var imageResources = parseImageResourcesSection(document, file);
        if (imageResources != null) {
          // store all the extra alpha channels. in case we have a transparency
          // mask, it will always be the first of the extra channels. alpha
          // channel names can be accessed using
          // imageResources.alphaChannels[index]. loop through all alpha
          // channels, and skip all channels that were already merged (either RGB
          // or RGBA).
          final skipImageCount = isRgb ? 3 : 4;
          for (var i = 0; i < imageCount - skipImageCount; ++i) {
            var channel = imageResources.alphaChannels[i];

            if (document.bitsPerChannel == 8) {
              var filename = '${getSampleOutputPath()}'
                  '.extra_channel_'
                  '${channel.asciiName}.tga';
              tga_exporter.saveMonochrome(filename, document.width,
                  document.height, imageData.images[i + skipImageCount].data);
            }
          }
        }
      }
    }
  }
  return 0;
}

final IMAGE_WIDTH = 256;
final IMAGE_HEIGHT = 256;

final gMultiplyData = Uint8List(IMAGE_WIDTH * IMAGE_HEIGHT);
final gXorData = Uint8List(IMAGE_WIDTH * IMAGE_HEIGHT);
final gOrData = Uint8List(IMAGE_WIDTH * IMAGE_HEIGHT);
final gAndData = Uint8List(IMAGE_WIDTH * IMAGE_HEIGHT);
final gCheckerBoardData = Uint8List(IMAGE_WIDTH * IMAGE_HEIGHT);

final gMultiplyData16 = Uint16List(IMAGE_HEIGHT * IMAGE_WIDTH);
final gXorData16 = Uint16List(IMAGE_HEIGHT * IMAGE_WIDTH);
final gOrData16 = Uint16List(IMAGE_HEIGHT * IMAGE_WIDTH);
final gAndData16 = Uint16List(IMAGE_HEIGHT * IMAGE_WIDTH);
final gCheckerBoardData16 = Uint16List(IMAGE_HEIGHT * IMAGE_WIDTH);

final gMultiplyData32 = Float32List(IMAGE_WIDTH * IMAGE_HEIGHT);
final gXorData32 = Float32List(IMAGE_WIDTH * IMAGE_HEIGHT);
final gOrData32 = Float32List(IMAGE_WIDTH * IMAGE_HEIGHT);
final gAndData32 = Float32List(IMAGE_WIDTH * IMAGE_HEIGHT);
final gCheckerBoardData32 = Float32List(IMAGE_WIDTH * IMAGE_HEIGHT);

void GenerateImageData() {
  for (var y = 0; y < IMAGE_HEIGHT; ++y) {
    for (var x = 0; x < IMAGE_WIDTH; ++x) {
      gMultiplyData[y * IMAGE_WIDTH + x] = (x * y >> 8) & 0xFF;
      gXorData[y * IMAGE_WIDTH + x] = (x ^ y) & 0xFF;
      gOrData[y * IMAGE_WIDTH + x] = (x | y) & 0xFF;
      gAndData[y * IMAGE_WIDTH + x] = (x & y) & 0xFF;
      gCheckerBoardData[y * IMAGE_WIDTH + x] =
          (x ~/ 8 + y ~/ 8) & 1 != 0 ? 255 : 128;

      gMultiplyData16[y * IMAGE_WIDTH + x] = (x * y) & 0xFFFF;
      gXorData16[y * IMAGE_WIDTH + x] = ((x ^ y) * 256) & 0xFFFF;
      gOrData16[y * IMAGE_WIDTH + x] = ((x | y) * 256) & 0xFFFF;
      gAndData16[y * IMAGE_WIDTH + x] = ((x & y) * 256) & 0xFFFF;
      gCheckerBoardData16[y * IMAGE_WIDTH + x] =
          (x ~/ 8 + y ~/ 8) & 1 != 0 ? 65535 : 32768;

      gMultiplyData32[y * IMAGE_WIDTH + x] = (1.0 / 65025.0) * (x * y);
      gXorData32[y * IMAGE_WIDTH + x] = (1.0 / 65025.0) * ((x ^ y) * 256);
      gOrData32[y * IMAGE_WIDTH + x] = (1.0 / 65025.0) * ((x | y) * 256);
      gAndData32[y * IMAGE_WIDTH + x] = (1.0 / 65025.0) * ((x & y) * 256);
      gCheckerBoardData32[y * IMAGE_WIDTH + x] =
          (x ~/ 8 + y ~/ 8) & 1 != 0 ? 1.0 : 0.5;
    }
  }
}

int sampleWritePsd() {
  GenerateImageData();

  {
    final dstPath = '${getSampleOutputPath()}SampleWrite_8.psd';

    var file = File();

    // write an RGB PSD file, 8-bit
    var document =
        createExportDocument(IMAGE_WIDTH, IMAGE_HEIGHT, 8, ExportColorMode.RGB);
    {
      // metadata can be added as simple key-value pairs.
      // when loading the document, they will be contained in XMP metadata such
      // as e.g. <xmp:MyAttribute>MyValue</xmp:MyAttribute>
      addMetaData(document, 'MyAttribute', 'MyValue');

      // when adding a layer to the document, you first need to get a new index
      // into the layer table. with a valid index, layers can be updated in
      // parallel, in any order. this also allows you to only update the layer
      // data that has changed, which is crucial when working with large data
      // sets.
      final layer1 = addLayer(document, 'MUL pattern');
      final layer2 = addLayer(document, 'XOR pattern');
      final layer3 = addLayer(document, 'Mixed pattern with transparency');

      // note that each layer has its own compression type. it is perfectly
      // legal to compress different channels of different layers with different
      // settings. RAW is pretty much just a raw data dump. fastest to write,
      // but large. RLE stores run-length encoded data which can be good for
      // 8-bit channels, but not so much for 16-bit or 32-bit data. ZIP is a
      // good compromise between speed and size. ZIP_WITH_PREDICTION first delta
      // encodes the data, and then zips it. slowest to write, but also smallest
      // in size for most images.
      updateLayer(document, layer1, ExportChannel.RED, 0, 0, IMAGE_WIDTH,
          IMAGE_HEIGHT, gMultiplyData, CompressionType.RAW);
      updateLayer(document, layer1, ExportChannel.GREEN, 0, 0, IMAGE_WIDTH,
          IMAGE_HEIGHT, gMultiplyData, CompressionType.RAW);
      updateLayer(document, layer1, ExportChannel.BLUE, 0, 0, IMAGE_WIDTH,
          IMAGE_HEIGHT, gMultiplyData, CompressionType.RAW);

      updateLayer(document, layer2, ExportChannel.RED, 0, 0, IMAGE_WIDTH,
          IMAGE_HEIGHT, gXorData, CompressionType.RAW);
      updateLayer(document, layer2, ExportChannel.GREEN, 0, 0, IMAGE_WIDTH,
          IMAGE_HEIGHT, gXorData, CompressionType.RAW);
      updateLayer(document, layer2, ExportChannel.BLUE, 0, 0, IMAGE_WIDTH,
          IMAGE_HEIGHT, gXorData, CompressionType.RAW);

      updateLayer(document, layer3, ExportChannel.RED, 0, 0, IMAGE_WIDTH,
          IMAGE_HEIGHT, gMultiplyData, CompressionType.RAW);
      updateLayer(document, layer3, ExportChannel.GREEN, 0, 0, IMAGE_WIDTH,
          IMAGE_HEIGHT, gXorData, CompressionType.RAW);
      updateLayer(document, layer3, ExportChannel.BLUE, 0, 0, IMAGE_WIDTH,
          IMAGE_HEIGHT, gOrData, CompressionType.RAW);

      // note that transparency information is always supported, regardless of
      // the export color mode. it is saved as true transparency, and not as
      // separate alpha channel.
      updateLayer(document, layer1, ExportChannel.ALPHA, 0, 0, IMAGE_WIDTH,
          IMAGE_HEIGHT, gMultiplyData, CompressionType.RAW);
      updateLayer(document, layer2, ExportChannel.ALPHA, 0, 0, IMAGE_WIDTH,
          IMAGE_HEIGHT, gXorData, CompressionType.RAW);
      updateLayer(document, layer3, ExportChannel.ALPHA, 0, 0, IMAGE_WIDTH,
          IMAGE_HEIGHT, gOrData, CompressionType.RAW);

      // merged image data is optional. if none is provided, black channels will
      // be exported instead.
      updateMergedImage(document, gMultiplyData, gXorData, gOrData);

      // when adding a channel to the document, you first need to get a new
      // index into the channel table. with a valid index, channels can be
      // updated in parallel, in any order. add four spot colors (red, green,
      // blue, and a mix) as additional channels.
      {
        final spotIndex = addAlphaChannel(
            document, 'Spot Red', 65535, 0, 0, 0, 100, AlphaChannelMode.SPOT);
        updateChannel(document, spotIndex, gMultiplyData);
      }
      {
        final spotIndex = addAlphaChannel(
            document, 'Spot Green', 0, 65535, 0, 0, 75, AlphaChannelMode.SPOT);
        updateChannel(document, spotIndex, gXorData);
      }
      {
        final spotIndex = addAlphaChannel(
            document, 'Spot Blue', 0, 0, 65535, 0, 50, AlphaChannelMode.SPOT);
        updateChannel(document, spotIndex, gOrData);
      }
      {
        final spotIndex = addAlphaChannel(document, 'Mix', 20000, 50000, 30000,
            0, 100, AlphaChannelMode.SPOT);
        updateChannel(document, spotIndex, gOrData);
      }

      writeDocument(document, file);
    }

    io.File(dstPath).writeAsBytesSync(file.bytes);
  }
  {
    final dstPath = '${getSampleOutputPath()}SampleWrite_16.psd';

    var file = File();

    // write a Grayscale PSD file, 16-bit.
    // Grayscale works similar to RGB, only the types of export channels change.
    final document = createExportDocument(
        IMAGE_WIDTH, IMAGE_HEIGHT, 16, ExportColorMode.GRAYSCALE);
    {
      final layer1 = addLayer(document, 'MUL pattern');
      updateLayer(document, layer1, ExportChannel.GRAY, 0, 0, IMAGE_WIDTH,
          IMAGE_HEIGHT, gMultiplyData16, CompressionType.RAW);

      final layer2 = addLayer(document, 'XOR pattern');
      updateLayer(document, layer2, ExportChannel.GRAY, 0, 0, IMAGE_WIDTH,
          IMAGE_HEIGHT, gXorData16, CompressionType.RLE);

      final layer3 = addLayer(document, 'AND pattern');
      updateLayer(document, layer3, ExportChannel.GRAY, 0, 0, IMAGE_WIDTH,
          IMAGE_HEIGHT, gAndData16, CompressionType.ZIP);

      final layer4 = addLayer(document, 'OR pattern with transparency');
      updateLayer(document, layer4, ExportChannel.GRAY, 0, 0, IMAGE_WIDTH,
          IMAGE_HEIGHT, gOrData16, CompressionType.ZIP_WITH_PREDICTION);
      updateLayer(
          document,
          layer4,
          ExportChannel.ALPHA,
          0,
          0,
          IMAGE_WIDTH,
          IMAGE_HEIGHT,
          gCheckerBoardData16,
          CompressionType.ZIP_WITH_PREDICTION);

      updateMergedImage(document, gMultiplyData16, gXorData16, gAndData16);

      writeDocument(document, file);
    }

    io.File(dstPath).writeAsBytesSync(file.bytes);
  }
  {
    final dstPath = '${getSampleOutputPath()}SampleWrite_32.psd';

    var file = File();

    // write an RGB PSD file, 32-bit
    var document = createExportDocument(
        IMAGE_WIDTH, IMAGE_HEIGHT, 32, ExportColorMode.RGB);
    {
      final layer1 = addLayer(document, 'MUL pattern');
      updateLayer(document, layer1, ExportChannel.RED, 0, 0, IMAGE_WIDTH,
          IMAGE_HEIGHT, gMultiplyData32, CompressionType.RAW);
      updateLayer(document, layer1, ExportChannel.GREEN, 0, 0, IMAGE_WIDTH,
          IMAGE_HEIGHT, gMultiplyData32, CompressionType.RLE);
      updateLayer(document, layer1, ExportChannel.BLUE, 0, 0, IMAGE_WIDTH,
          IMAGE_HEIGHT, gMultiplyData32, CompressionType.ZIP);

      final layer2 = addLayer(document, 'Mixed pattern with transparency');
      updateLayer(document, layer2, ExportChannel.RED, 0, 0, IMAGE_WIDTH,
          IMAGE_HEIGHT, gMultiplyData32, CompressionType.RLE);
      updateLayer(document, layer2, ExportChannel.GREEN, 0, 0, IMAGE_WIDTH,
          IMAGE_HEIGHT, gXorData32, CompressionType.ZIP);
      updateLayer(document, layer2, ExportChannel.BLUE, 0, 0, IMAGE_WIDTH,
          IMAGE_HEIGHT, gOrData32, CompressionType.ZIP_WITH_PREDICTION);
      updateLayer(document, layer2, ExportChannel.ALPHA, 0, 0, IMAGE_WIDTH,
          IMAGE_HEIGHT, gCheckerBoardData32, CompressionType.RAW);

      updateMergedImage(
          document, gMultiplyData32, gXorData32, gCheckerBoardData32);

      writeDocument(document, file);
    }

    io.File(dstPath).writeAsBytesSync(file.bytes);
  }

  return 0;
}

void main() {
  sampleReadPsd();
  sampleWritePsd();
}
