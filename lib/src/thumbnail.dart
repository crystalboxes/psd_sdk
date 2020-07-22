import 'dart:typed_data';

/// A struct representing a thumbnail as stored in the image resources section.
class Thumbnail {
  int width;
  int height;
  int binaryJpegSize;
  Uint8List binaryJpeg;
}
