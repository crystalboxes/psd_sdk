import 'dart:typed_data';

/// A struct representing a channel as stored in the layers of the Layer Mask section.
class Channel {
  /// The offset from the start of the file where the channel's data is stored.
  int fileOffset;

  /// The size of the channel data to be read from the file.
  int size;

  /// Planar data the size of the layer the channel belongs to. Data is only valid if the type member indicates so.
  Uint8List data;

  /// One of the channelType constants denoting the type of data.
  int type;
}
