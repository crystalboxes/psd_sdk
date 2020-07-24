class ChannelType {
  /// Internal value. Used to denote that a channel no longer holds valid data.
  static const INVALID = 32767;

  /// Type denoting the R channel, not necessarily the first in a RGB Color Mode document.
  static const R = 0;

  /// Type denoting the G channel, not necessarily the second in a RGB Color Mode document.
  static const G = 1;

  /// Type denoting the B channel, not necessarily the third in a RGB Color Mode document.
  static const B = 2;

  /// The layer's channel data is a transparency mask.
  static const TRANSPARENCY_MASK = -1;

  /// The layer's channel data is either a layer or vector mask.
  static const LAYER_OR_VECTOR_MASK = -2;

  /// The layer's channel data is a layer mask.
  static const LAYER_MASK = -3;
}
