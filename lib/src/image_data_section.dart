import 'dart:typed_data';

/// A struct representing a planar image as stored in the Image Data section.
class PlanarImage {
  /// Planar data the size of the document's canvas.
  Uint8List data;
}

/// A struct representing the information extracted from the Image Data section.
class ImageDataSection {
  /// An array of planar images, having imageCount entries.
  List<PlanarImage> images;

  /// The number of planar images stored in the array.
  int get imageCount => images.length;
}
