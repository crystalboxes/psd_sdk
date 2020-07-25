import 'dart:typed_data';

import 'package:psd_sdk/psd_sdk.dart';
import 'package:psd_sdk/src/file.dart';
import '../example/psd_sdk_example.dart';
import 'package:test/test.dart';
import 'dart:io' as io;
import 'canvas_data_test.dart';

const int CHANNEL_NOT_FOUND = -1;

int testA() {
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

  final layerMaskSection = parseLayerMaskSection(document, file);
  var hasTransparencyMask = layerMaskSection.hasTransparencyMask;
  var layer = layerMaskSection.layers[0];

  test('Document ', () {
    expect(document.bitsPerChannel, 8);
    expect(document.width, 1024);
    expect(document.height, 1024);
  });
  test('layer ', () {
    expect(layer.name, 'UpperLeft');
    expect(layer.channelCount, 4);
    expect(layer.right, 512);
    expect(layer.layerMask, null);
    expect(layer.opacity, 255);
  });

  // extract all layers one by one. this should be done in parallel for
  // maximum efficiency.

  var imageData = ParseImageDataSection(document, file);
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

  Uint8List image8;
  Uint8List image16;
  Uint8List image32;

  if (isRgb) {
    // RGB
    if (document.bitsPerChannel == 8) {
      image8 = createInterleavedImage<Uint8T>(
          imageData.images[0].data,
          imageData.images[1].data,
          imageData.images[2].data,
          document.width,
          document.height);
    } else if (document.bitsPerChannel == 16) {
      image16 = createInterleavedImage<Uint16T>(
          imageData.images[0].data,
          imageData.images[1].data,
          imageData.images[2].data,
          document.width,
          document.height);
    } else if (document.bitsPerChannel == 32) {
      image32 = createInterleavedImage<Float32T>(
          imageData.images[0].data,
          imageData.images[1].data,
          imageData.images[2].data,
          document.width,
          document.height);
    }
  } else {
    // RGBA
    if (document.bitsPerChannel == 8) {
      image8 = createInterleavedImageRGBA<Uint8T>(
          imageData.images[0].data,
          imageData.images[1].data,
          imageData.images[2].data,
          imageData.images[3].data,
          document.width,
          document.height);
    } else if (document.bitsPerChannel == 16) {
      image16 = createInterleavedImageRGBA<Uint16T>(
          imageData.images[0].data,
          imageData.images[1].data,
          imageData.images[2].data,
          imageData.images[3].data,
          document.width,
          document.height);
    } else if (document.bitsPerChannel == 32) {
      image32 = createInterleavedImageRGBA<Float32T>(
          imageData.images[0].data,
          imageData.images[1].data,
          imageData.images[2].data,
          imageData.images[3].data,
          document.width,
          document.height);
    }
  }

  test('Merged image', () {
    expect(image8 != null, true);
    expect(image16, null);
    expect(image32, null);
  });

  test('image section image8', () {
    expect(image8[0], 102);
    expect(image8[1], 43);
    expect(image8[2], 14);

    expect(image8[6], 35);
    expect(image8[7], 255);

    expect(image8[16], 201);
    expect(image8[17], 82);

    expect(image8[21], 81);
    expect(image8[22], 24);

    expect(image8[49], 80);
  });

  group('Canvas data group', () {
    testCanvasData(document, file, layer);
  });
  return 0;
}

void testCanvasData(Document document, File file, Layer layer) {
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
        expandChannelToCanvas2(document, layer, layer.channels[indexR]);
    canvasData[1] =
        expandChannelToCanvas2(document, layer, layer.channels[indexG]);
    canvasData[2] =
        expandChannelToCanvas2(document, layer, layer.channels[indexB]);
    channelCount = 3;

    if (indexA != CHANNEL_NOT_FOUND) {
      // A channel was also found.
      canvasData[3] =
          expandChannelToCanvas2(document, layer, layer.channels[indexA]);
      channelCount = 4;
    }
  }

  // interleave the different pieces of planar canvas data into one RGB or
  // RGBA image, depending on what channels we found, and what color mode
  // the document is stored in.
  Uint8List image8;
  if (channelCount == 3) {
    if (document.bitsPerChannel == 8) {
      image8 = createInterleavedImage<Uint8T>(canvasData[0], canvasData[1],
          canvasData[2], document.width, document.height);
    } else if (document.bitsPerChannel == 16) {
    } else if (document.bitsPerChannel == 32) {}
  } else if (channelCount == 4) {
    if (document.bitsPerChannel == 8) {
      image8 = createInterleavedImageRGBA<Uint8T>(canvasData[0], canvasData[1],
          canvasData[2], canvasData[3], document.width, document.height);
    } else if (document.bitsPerChannel == 16) {
    } else if (document.bitsPerChannel == 32) {}
  }

  test('Channel indices', () {
    expect(indexR, 1);
    expect(indexG, 2);
    expect(indexB, 3);
    expect(indexA, 0);
  });

  canvasDataTest(canvasData, image8);
}

void main() {
  testA();
}
