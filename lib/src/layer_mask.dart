import 'dart:typed_data';
import 'layer_rect.dart';

class Mask implements LayerRect {
  /// Top coordinate of the rectangle that encloses the mask.
  @override
  int top;

  /// Left coordinate of the rectangle that encloses the mask.
  @override
  int left;

  /// Bottom coordinate of the rectangle that encloses the mask.
  @override
  int bottom;

  /// Right coordinate of the rectangle that encloses the mask.
  @override
  int right;

  /// The offset from the start of the file where the channel's data is stored.
  int fileOffset;

  /// Planar data, having a size of (right-left)*(bottom-top)*bytesPerPixel.
  Uint8List data;

  /// The mask's feather value.
  double feather;

  /// The mask's density value.
  int density;

  /// The mask's default color regions outside the enclosing rectangle.
  int defaultColor;
}

/// A struct representing a layer mask as stored in the layers of the Layer Mask section.
class LayerMask extends Mask {}

/// A struct representing a vector mask as stored in the layers of the Layer Mask section.
class VectorMask extends Mask {}
