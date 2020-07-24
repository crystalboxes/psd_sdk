import 'dart:typed_data';

import 'package:psd_sdk/psd_sdk.dart';
import 'package:psd_sdk/src/file.dart';
import '../example/psd_sdk_example.dart';
import 'package:test/test.dart';

import 'canvas_data_test.dart';

const int CHANNEL_NOT_FOUND = -1;

int testA() {
  final srcPath = '${getSampleInputPath()}Sample.psd';
  var allocator = mallocAllocator();
  var file = nativeFile(allocator);

  if (!file.openRead(srcPath)) {
    print('Cannot open file.');
    return 1;
  }

  final document = createDocument(file, allocator);
  if (document == null) {
    print('Cannot create document.');
    file.close();
    return 1;
  }

  // the sample only supports RGB colormode
  if (document.colorMode != ColorMode.RGB) {
    print('Document is not in RGB color mode.\n');
    destroyDocument(document, allocator);
    file.close();
    return 1;
  }

  final layerMaskSection = parseLayerMaskSection(document, file, allocator);
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

  var imageData = ParseImageDataSection(document, file, allocator);
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
      image8 = createInterleavedImage<uint8_t>(
          allocator,
          imageData.images[0].data,
          imageData.images[1].data,
          imageData.images[2].data,
          document.width,
          document.height);
    } else if (document.bitsPerChannel == 16) {
      image16 = createInterleavedImage<uint16_t>(
          allocator,
          imageData.images[0].data,
          imageData.images[1].data,
          imageData.images[2].data,
          document.width,
          document.height);
    } else if (document.bitsPerChannel == 32) {
      image32 = createInterleavedImage<float32_t>(
          allocator,
          imageData.images[0].data,
          imageData.images[1].data,
          imageData.images[2].data,
          document.width,
          document.height);
    }
  } else {
    // RGBA
    if (document.bitsPerChannel == 8) {
      image8 = createInterleavedImageRGBA<uint8_t>(
          allocator,
          imageData.images[0].data,
          imageData.images[1].data,
          imageData.images[2].data,
          imageData.images[3].data,
          document.width,
          document.height);
    } else if (document.bitsPerChannel == 16) {
      image16 = createInterleavedImageRGBA<uint16_t>(
          allocator,
          imageData.images[0].data,
          imageData.images[1].data,
          imageData.images[2].data,
          imageData.images[3].data,
          document.width,
          document.height);
    } else if (document.bitsPerChannel == 32) {
      image32 = createInterleavedImageRGBA<float32_t>(
          allocator,
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
    expect(image8[3], 255);
    expect(image8[4], 128);
    expect(image8[5], 65);
    expect(image8[6], 35);
    expect(image8[7], 255);
    expect(image8[8], 163);
    expect(image8[9], 88);
    expect(image8[10], 45);
    expect(image8[11], 255);
    expect(image8[12], 201);
    expect(image8[13], 91);
    expect(image8[14], 26);
    expect(image8[15], 255);
    expect(image8[16], 201);
    expect(image8[17], 82);
    expect(image8[18], 20);
    expect(image8[19], 255);
    expect(image8[20], 195);
    expect(image8[21], 81);
    expect(image8[22], 24);
    expect(image8[23], 255);
    expect(image8[24], 194);
    expect(image8[25], 80);
    expect(image8[26], 23);
    expect(image8[27], 255);
    expect(image8[28], 199);
    expect(image8[29], 80);
    expect(image8[30], 19);
    expect(image8[31], 255);
    expect(image8[32], 198);
    expect(image8[33], 81);
    expect(image8[34], 20);
    expect(image8[35], 255);
    expect(image8[36], 197);
    expect(image8[37], 81);
    expect(image8[38], 21);
    expect(image8[39], 255);
    expect(image8[40], 197);
    expect(image8[41], 81);
    expect(image8[42], 20);
    expect(image8[43], 255);
    expect(image8[44], 201);
    expect(image8[45], 79);
    expect(image8[46], 16);
    expect(image8[47], 255);
    expect(image8[48], 201);
    expect(image8[49], 80);
  });

  group('Canvas data group', () {
    testCanvasData(document, file, allocator, layer);
  });
}

void testCanvasData(
    Document document, File file, Allocator allocator, Layer layer) {
  extractLayer(document, file, allocator, layer);

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
    canvasData[0] = expandChannelToCanvas2(
        document, allocator, layer, layer.channels[indexR]);
    canvasData[1] = expandChannelToCanvas2(
        document, allocator, layer, layer.channels[indexG]);
    canvasData[2] = expandChannelToCanvas2(
        document, allocator, layer, layer.channels[indexB]);
    channelCount = 3;

    if (indexA != CHANNEL_NOT_FOUND) {
      // A channel was also found.
      canvasData[3] = expandChannelToCanvas2(
          document, allocator, layer, layer.channels[indexA]);
      channelCount = 4;
    }
  }

  // interleave the different pieces of planar canvas data into one RGB or
  // RGBA image, depending on what channels we found, and what color mode
  // the document is stored in.
  Uint8List image8, image16, image32;
  if (channelCount == 3) {
    if (document.bitsPerChannel == 8) {
      image8 = createInterleavedImage<uint8_t>(allocator, canvasData[0],
          canvasData[1], canvasData[2], document.width, document.height);
    } else if (document.bitsPerChannel == 16) {
      image16 = createInterleavedImage<uint16_t>(allocator, canvasData[0],
          canvasData[1], canvasData[2], document.width, document.height);
    } else if (document.bitsPerChannel == 32) {
      image32 = createInterleavedImage<float32_t>(allocator, canvasData[0],
          canvasData[1], canvasData[2], document.width, document.height);
    }
  } else if (channelCount == 4) {
    if (document.bitsPerChannel == 8) {
      image8 = createInterleavedImageRGBA<uint8_t>(
          allocator,
          canvasData[0],
          canvasData[1],
          canvasData[2],
          canvasData[3],
          document.width,
          document.height);
    } else if (document.bitsPerChannel == 16) {
      image16 = createInterleavedImageRGBA<uint16_t>(
          allocator,
          canvasData[0],
          canvasData[1],
          canvasData[2],
          canvasData[3],
          document.width,
          document.height);
    } else if (document.bitsPerChannel == 32) {
      image32 = createInterleavedImageRGBA<float32_t>(
          allocator,
          canvasData[0],
          canvasData[1],
          canvasData[2],
          canvasData[3],
          document.width,
          document.height);
    }
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
