import 'dart:typed_data';

class Channel {
  /// The offset from the start of the file where the channel's data is stored.
  int fileOffset;

  /// The size of the channel data to be read from the file.
  int size;

  /// Planar data the size of the layer the channel belongs to. Data is only valid if the type member indicates so.
  Uint8List data;

  /// One of the \ref channelType constants denoting the type of data.
  int type;
}