import 'dart:typed_data';
import 'data_types.dart';

/// Turns planar 8-bit RGB data into interleaved RGBA data with a constant, predefined alpha.
/// The destination buffer dest must hold "width*height*4" bytes.
/// All given buffers (both source and destination) must be aligned to 16 bytes.
Uint8List interleaveRGB(Uint8List srcR, Uint8List srcG, Uint8List srcB,
    num alpha, int bitsPerChannel, int width, int height,
    [int blockSize = 4]) {
  if (bitsPerChannel == 8) {
    return _interleaveRGB<Uint8T>(srcR, srcG, srcB, alpha, width, height);
  } else if (bitsPerChannel == 16) {
    return _interleaveRGB<Uint16T>(srcR, srcG, srcB, alpha, width, height);
  } else if (bitsPerChannel == 32) {
    return _interleaveRGB<Float32T>(srcR, srcG, srcB, alpha, width, height);
  }
  return null;
}

/// Turns planar 8-bit RGBA data into interleaved RGBA data.
/// The destination buffer dest must hold "width*height*4" bytes.
/// All given buffers (both source and destination) must be aligned to 16 bytes.
Uint8List interleaveRGBA(Uint8List srcR, Uint8List srcG, Uint8List srcB,
    Uint8List srcA, int bitsPerChannel, int width, int height,
    [int blockSize = 4]) {
  if (bitsPerChannel == 8) {
    return _interleaveRGBA<Uint8T>(srcR, srcG, srcB, srcA, width, height);
  } else if (bitsPerChannel == 16) {
    return _interleaveRGBA<Uint16T>(srcR, srcG, srcB, srcA, width, height);
  } else if (bitsPerChannel == 32) {
    return _interleaveRGBA<Float32T>(srcR, srcG, srcB, srcA, width, height);
  }
  return null;
}

Uint8List _interleaveRGB<T extends NumDataType>(Uint8List srcR, Uint8List srcG,
    Uint8List srcB, num alpha, int width, int height,
    [int blockSize = 4]) {
  final r = getTypedList<T>(srcR) as List;
  final g = getTypedList<T>(srcG) as List;
  final b = getTypedList<T>(srcB) as List;

  if (isDouble<T>()) {
    alpha = alpha.toDouble();
  }
  var dest = Uint8List(width * height * 4 * sizeof<T>());
  var destTyped = getTypedList<T>(dest) as List;

  for (var x = 0; x < width * height; x++) {
    destTyped[x * 4 + 0] = r[x];
    destTyped[x * 4 + 1] = g[x];
    destTyped[x * 4 + 2] = b[x];
    destTyped[x * 4 + 3] = alpha;
  }
  return dest;
}

Uint8List _interleaveRGBA<T extends NumDataType>(Uint8List srcR, Uint8List srcG,
    Uint8List srcB, Uint8List srcA, int width, int height,
    [int blockSize = 4]) {
  final r = getTypedList<T>(srcR) as List;
  final g = getTypedList<T>(srcG) as List;
  final b = getTypedList<T>(srcB) as List;
  final a = getTypedList<T>(srcA) as List;

  var dest = Uint8List(width * height * 4 * sizeof<T>());
  var destTyped = getTypedList<T>(dest) as List;

  for (var x = 0; x < width * height; x++) {
    destTyped[x * 4 + 0] = r[x];
    destTyped[x * 4 + 1] = g[x];
    destTyped[x * 4 + 2] = b[x];
    destTyped[x * 4 + 3] = a[x];
  }
  return dest;
}
