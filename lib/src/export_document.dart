import 'dart:typed_data';

import 'alpha_channel.dart';
import 'export_layer.dart';
import 'export_metadata_attribute.dart';
import 'thumbnail.dart';

/// A struct representing a document to be exported.
class ExportDocument {
  static const MAX_ATTRIBUTE_COUNT = 128;
  static const MAX_LAYER_COUNT = 128;
  static const MAX_ALPHA_CHANNEL_COUNT = 128;

  int width;
  int height;
  int bitsPerChannel;
  int colorMode;

  List<ExportMetaDataAttribute> attributes;
  int get attributeCount => attributes.length;

  List<ExportLayer> layers;
  int get layerCount => layers.length;

  List<Uint8List> mergedImageData = List(3);

  List<AlphaChannel> alphaChannels = List(MAX_ALPHA_CHANNEL_COUNT);
  int get alphaChannelCount => alphaChannels.length;
  List<Uint8List> alphaChannelData = List(MAX_ALPHA_CHANNEL_COUNT);

  Uint8List iccProfile;
  int get sizeOfICCProfile => iccProfile.length;

  Uint8List exifData;
  int get sizeOfExifData => exifData.length;

  Thumbnail thumbnail;
}
