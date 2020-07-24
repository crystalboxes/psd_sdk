import 'dart:typed_data';

/// A struct representing a layer as exported to the Layer Mask section.
class ExportLayer {
  // the SDK currently supports R, G, B, A
  static const int MAX_CHANNEL_COUNT = 4;

  int top;
  int left;
  int bottom;
  int right;
  String name;

  var channelData = List<Uint8List>(MAX_CHANNEL_COUNT);
  var channelSize = Uint32List(MAX_CHANNEL_COUNT);
  var channelCompression = Uint16List(MAX_CHANNEL_COUNT);
}
