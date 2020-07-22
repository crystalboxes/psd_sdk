import 'package:psd_sdk/src/section.dart';

/// A struct storing the document-wide information and sections contained in a .PSD file.
class Document {
  int width;
  int height;
  int channelCount;
  int bitsPerChannel;
  int colorMode;

  /// Color mode data section.
  Section colorModeDataSection;

  /// Image Resources section.
  Section imageResourcesSection;

  /// Layer Mask Info section.
  Section layerMaskInfoSection;

  /// Image Data section.
  Section imageDataSection;
}
