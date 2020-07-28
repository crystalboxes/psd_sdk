import 'dart:typed_data';

import 'channel.dart';
import 'layer_mask.dart';
import 'layer_rect.dart';

/// A struct representing a layer as stored in the Layer Mask Info section.
class Layer implements LayerRect {
  /// The layer's parent layer, if any.
  Layer parent;

  /// The ASCII name of the layer. Truncated to 31 characters in PSD files.
  String name;

  /// The UTF16 name of the layer.
  Uint16List utf16Name;

  /// Top coordinate of the rectangle that encloses the layer.
  @override
  int top;

  /// Left coordinate of the rectangle that encloses the layer.
  @override
  int left;

  /// Bottom coordinate of the rectangle that encloses the layer.
  @override
  int bottom;

  /// Right coordinate of the rectangle that encloses the layer.
  @override
  int right;

  /// An array of channels, having channelCount entries.
  List<Channel> channels;

  /// The number of channels stored in the array.
  int get channelCount => channels.length;

  /// The layer's user mask, if any.
  LayerMask layerMask;

  /// The layer's vector mask, if any.
  VectorMask vectorMask;

  /// The key denoting the layer's blend mode. Can be any key described in \ref blendMode::Enum.
  int blendModeKey;

  /// The layer's opacity value, with the range [0, 255] mapped to [0%, 100%].
  int opacity;

  /// The layer's clipping mode (not used yet).
  int clipping;

  /// The layer's type. Can be any of \ref layerType::Enum.
  int type;

  /// The layer's visibility.
  bool isVisible;
}
