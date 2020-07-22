import 'dart:typed_data';

import 'package:psd_sdk/src/alpha_channel.dart';

import 'thumbnail.dart';

/// A struct representing the information extracted from the Image Resources section.
class ImageResourcesSection {
  /// An array of alpha channels, having alphaChannelCount entries.
  List<AlphaChannel> alphaChannels;

  /// The number of alpha channels stored in the array.
  int get alphaChannelCount => alphaChannels.length;

  /// Raw data of the ICC profile.
  Uint8List iccProfile;
  int sizeOfICCProfile;

  /// Raw EXIF data.
  Uint8List exifData;
  int sizeOfExifData;

  /// Whether the PSD contains real merged data.
  bool containsRealMergedData;

  /// Raw XMP metadata.
  String xmpMetadata;

  /// JPEG thumbnail.
  Thumbnail thumbnail;
}
