import 'layer.dart';

/// A struct representing the information extracted from the Layer Mask section.
class LayerMaskSection {
  /// An array of layers, having layerCount entries.
  List<Layer> layers;

  /// The number of layers stored in the array.
  int get layerCount => layers.length;

  /// The color space of the overlay (undocumented, not used yet).
  int overlayColorSpace;

  /// The global opacity level (0 = transparent, 100 = opaque, not used yet).
  int opacity;

  /// The global kind of layer (not used yet).
  int kind;

  /// Whether the layer data contains a transparency mask or not.
  bool hasTransparencyMask;
}
