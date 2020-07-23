import 'dart:typed_data';

import 'package:psd_sdk/psd_sdk.dart';

const int CHANNEL_NOT_FOUND = -1;

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
int FindChannel(Layer layer, int channelType) {
  for (var i = 0; i < layer.channelCount; ++i) {
    var channel = layer.channels[i];
    if (channel.data != null && channel.type == channelType) {
      return i;
    }
  }

  return CHANNEL_NOT_FOUND;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
String GetSampleInputPath() {
  return '';
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
String GetSampleOutputPath() {
  assert(false);
  return '';
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
Uint8List ExpandChannelToCanvas<T extends NumDataType>(Allocator allocator,
    BoundsRect layer, Uint8List data, int canvasWidth, int canvasHeight) {
  var canvasData = Uint8List.fromList(
      List.filled(sizeof<T>() * canvasWidth * canvasHeight, 0));

  CopyLayerData<T>(data, canvasData, layer.left, layer.top, layer.right,
      layer.bottom, canvasWidth, canvasHeight);

  return canvasData;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
Uint8List ExpandChannelToCanvas2(
    Document document, Allocator allocator, BoundsRect layer, Channel channel) {
  if (document.bitsPerChannel == 8) {
    return ExpandChannelToCanvas<uint8_t>(
        allocator, layer, channel.data, document.width, document.height);
  } else if (document.bitsPerChannel == 16) {
    return ExpandChannelToCanvas<uint16_t>(
        allocator, layer, channel.data, document.width, document.height);
  } else if (document.bitsPerChannel == 32) {
    return ExpandChannelToCanvas<float32_t>(
        allocator, layer, channel.data, document.width, document.height);
  }

  return null;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
Uint8List ExpandMaskToCanvas(
    Document document, Allocator allocator, Mask mask) {
  if (document.bitsPerChannel == 8) {
    return ExpandChannelToCanvas<uint8_t>(
        allocator, mask, mask.data, document.width, document.height);
  } else if (document.bitsPerChannel == 16) {
    return ExpandChannelToCanvas<uint16_t>(
        allocator, mask, mask.data, document.width, document.height);
  } else if (document.bitsPerChannel == 32) {
    return ExpandChannelToCanvas<float32_t>(
        allocator, mask, mask.data, document.width, document.height);
  }

  return null;
}

Uint8List CreateInterleavedImage<T extends NumDataType>(Allocator allocator,
    Uint8List srcR, Uint8List srcG, Uint8List srcB, int width, int height) {
  var image = Uint8List(width * height * 4 * sizeof<T>());

  final r = (srcR);
  final g = (srcG);
  final b = (srcB);
  InterleaveRGB(r, g, b, null, image, width, height);

  return image;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
Uint8List CreateInterleavedImageRGBA<T extends NumDataType>(
    Allocator allocator,
    Uint8List srcR,
    Uint8List srcG,
    Uint8List srcB,
    Uint8List srcA,
    int width,
    int height) {
  var image = Uint8List(width * height * 4 * sizeof<T>());

  final r = (srcR);
  final g = (srcG);
  final b = (srcB);
  final a = (srcA);
  InterleaveRGBA(r, g, b, a, image, width, height);

  return image;
}

int sampleReadPsd() {
  final srcPath = 'example/Sample.psd';

  var allocator = MallocAllocator();
  var file = NativeFile(allocator);

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

  // extract image resources section.
  // this gives access to the ICC profile, EXIF data and XMP metadata.
  {
    var imageResourcesSection =
        parseImageResourcesSection(document, file, allocator);
    print('XMP metadata:');
    print(imageResourcesSection.xmpMetadata);
    print('\n');
    destroyImageResourcesSection(imageResourcesSection, allocator);
  }

  var hasTransparencyMask = false;
  final layerMaskSection = parseLayerMaskSection(document, file, allocator);

  if (layerMaskSection != null) {
    hasTransparencyMask = layerMaskSection.hasTransparencyMask;

    // extract all layers one by one. this should be done in parallel for
    // maximum efficiency.
    for (var i = 0; i < layerMaskSection.layerCount; ++i) {
      var layer = layerMaskSection.layers[i];
      extractLayer(document, file, allocator, layer);

      // check availability of R, G, B, and A channels.
      // we need to determine the indices of channels individually, because
      // there is no guarantee that R is the first channel, G is the second, B
      // is the third, and so on.
      final indexR = FindChannel(layer, ChannelType.R);
      final indexG = FindChannel(layer, ChannelType.G);
      final indexB = FindChannel(layer, ChannelType.B);
      final indexA = FindChannel(layer, ChannelType.TRANSPARENCY_MASK);

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
        canvasData[0] = ExpandChannelToCanvas2(
            document, allocator, layer, layer.channels[indexR]);
        canvasData[1] = ExpandChannelToCanvas2(
            document, allocator, layer, layer.channels[indexG]);
        canvasData[2] = ExpandChannelToCanvas2(
            document, allocator, layer, layer.channels[indexB]);
        channelCount = 3;

        if (indexA != CHANNEL_NOT_FOUND) {
          // A channel was also found.
          canvasData[3] = ExpandChannelToCanvas2(
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
          image8 = CreateInterleavedImage<uint8_t>(allocator, canvasData[0],
              canvasData[1], canvasData[2], document.width, document.height);
        } else if (document.bitsPerChannel == 16) {
          image16 = CreateInterleavedImage<uint16_t>(allocator, canvasData[0],
              canvasData[1], canvasData[2], document.width, document.height);
        } else if (document.bitsPerChannel == 32) {
          image32 = CreateInterleavedImage<float32_t>(allocator, canvasData[0],
              canvasData[1], canvasData[2], document.width, document.height);
        }
      } else if (channelCount == 4) {
        if (document.bitsPerChannel == 8) {
          image8 = CreateInterleavedImageRGBA<uint8_t>(
              allocator,
              canvasData[0],
              canvasData[1],
              canvasData[2],
              canvasData[3],
              document.width,
              document.height);
        } else if (document.bitsPerChannel == 16) {
          image16 = CreateInterleavedImageRGBA<uint16_t>(
              allocator,
              canvasData[0],
              canvasData[1],
              canvasData[2],
              canvasData[3],
              document.width,
              document.height);
        } else if (document.bitsPerChannel == 32) {
          image32 = CreateInterleavedImageRGBA<float32_t>(
              allocator,
              canvasData[0],
              canvasData[1],
              canvasData[2],
              canvasData[3],
              document.width,
              document.height);
        }
      }

      allocator.free(canvasData[0]);
      allocator.free(canvasData[1]);
      allocator.free(canvasData[2]);
      allocator.free(canvasData[3]);

      // get the layer name.
      // Unicode data is preferred because it is not truncated by Photoshop, but
      // unfortunately it is optional. fall back to the ASCII name in case no
      // Unicode name was found.
      String layerName;
      if (layer.utf16Name != null) {
        // TODO
        // layerName << reinterpret_cast<wchar_t *>(layer.utf16Name);
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
          var filename = '${GetSampleOutputPath()}layer${layerName}.tga';
          // TODO
          // tgaExporter::SaveRGB(filename.str().c_str(), document.width,
          //                      document.height, image8);
        }
      } else if (channelCount == 4) {
        if (document.bitsPerChannel == 8) {
          var filename = '${GetSampleOutputPath()}layer${layerName}.tga';
          // TODO
          // tgaExporter::SaveRGBA(filename.str().c_str(), document.width,
          //                       document.height, image8);
        }
      }

      allocator.free(image8);
      allocator.free(image16);
      allocator.free(image32);

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
        Uint8List maskData = layer.layerMask.data;
        {
          var filename =
              '${GetSampleOutputPath()}layer${layerName}_usermask.tga';
          // TODO
          // tgaExporter::SaveMonochrome(filename.str().c_str(), width, height,
          //                             static_cast<const uint8_t *>(maskData));
        }

        // use ExpandMaskToCanvas create an image that is the same size as the
        // canvas.
        Uint8List maskCanvasData =
            ExpandMaskToCanvas(document, allocator, layer.layerMask);
        {
          var filename =
              '${GetSampleOutputPath()}canvas${layerName}_usermask.tga';
          // TODO
          // tgaExporter::SaveMonochrome(
          //     filename.str().c_str(), document.width, document.height,
          //     static_cast<const uint8_t *>(maskCanvasData));
        }

        allocator.free(maskCanvasData);
      }

      if (layer.vectorMask != null) {
        // accessing the vector mask works exactly like accessing the layer
        // mask.
        final width = (layer.vectorMask.right - layer.vectorMask.left);
        final height = (layer.vectorMask.bottom - layer.vectorMask.top);

        Uint8List maskData = layer.vectorMask.data;
        {
          var filename =
              '${GetSampleOutputPath()}layer${layerName}_vectormask.tga';
          // TODO
          // tgaExporter::SaveMonochrome(filename.str().c_str(), width, height,
          //                             static_cast<const uint8_t *>(maskData));
        }

        Uint8List maskCanvasData =
            ExpandMaskToCanvas(document, allocator, layer.vectorMask);
        {
          var filename =
              '${GetSampleOutputPath()}canvas${layerName}_vectormask.tga';
          // TODO
          // tgaExporter::SaveMonochrome(
          //     filename.str().c_str(), document.width, document.height,
          //     static_cast<const uint8_t *>(maskCanvasData));
        }

        allocator.free(maskCanvasData);
      }
    }

    destroyLayerMaskSection(layerMaskSection, allocator);

    // extract the image data section, if available. the image data section stores
    // the final, merged image, as well as additional alpha channels. this is only
    // available when saving the document with "Maximize Compatibility" turned on.
    if (document.imageDataSection.length != 0) {
      var imageData = ParseImageDataSection(document, file, allocator);
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

        Uint8List image8, image16, image32;
        if (isRgb) {
          // RGB
          if (document.bitsPerChannel == 8) {
            image8 = CreateInterleavedImage<uint8_t>(
                allocator,
                imageData.images[0].data,
                imageData.images[1].data,
                imageData.images[2].data,
                document.width,
                document.height);
          } else if (document.bitsPerChannel == 16) {
            image16 = CreateInterleavedImage<uint16_t>(
                allocator,
                imageData.images[0].data,
                imageData.images[1].data,
                imageData.images[2].data,
                document.width,
                document.height);
          } else if (document.bitsPerChannel == 32) {
            image32 = CreateInterleavedImage<float32_t>(
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
            image8 = CreateInterleavedImageRGBA<uint8_t>(
                allocator,
                imageData.images[0].data,
                imageData.images[1].data,
                imageData.images[2].data,
                imageData.images[3].data,
                document.width,
                document.height);
          } else if (document.bitsPerChannel == 16) {
            image16 = CreateInterleavedImageRGBA<uint16_t>(
                allocator,
                imageData.images[0].data,
                imageData.images[1].data,
                imageData.images[2].data,
                imageData.images[3].data,
                document.width,
                document.height);
          } else if (document.bitsPerChannel == 32) {
            image32 = CreateInterleavedImageRGBA<float32_t>(
                allocator,
                imageData.images[0].data,
                imageData.images[1].data,
                imageData.images[2].data,
                imageData.images[3].data,
                document.width,
                document.height);
          }
        }

        if (document.bitsPerChannel == 8) {
          var filename = '${GetSampleOutputPath()}merged.tga';
          // TODO
          // if (isRgb) {
          //   tgaExporter::SaveRGB(filename.str().c_str(), document.width,
          //                        document.height, image8);
          // } else {
          //   tgaExporter::SaveRGBA(filename.str().c_str(), document.width,
          //                         document.height, image8);
          // }
        }

        allocator.free(image8);
        allocator.free(image16);
        allocator.free(image32);

        // extract image resources in order to acquire the alpha channel names.
        var imageResources =
            parseImageResourcesSection(document, file, allocator);
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
              var filename =
                  '${GetSampleOutputPath()}.extra_channel_${channel.asciiName}.tga';
              // TODO
              // tgaExporter::SaveMonochrome(
              //     filename.str().c_str(), document.width, document.height,
              //     static_cast<const uint8_t *>(
              //         imageData.images[i + skipImageCount].data));
            }
          }

          destroyImageResourcesSection(imageResources, allocator);
        }

        destroyImageDataSection(imageData, allocator);
      }
    }

    // don't forget to destroy the document, and close the file.
    destroyDocument(document, allocator);
    file.close();
  }
  return 0;
}

void main() {
  sampleReadPsd();
}
