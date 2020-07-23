import 'dart:typed_data';
import 'data_types.dart';

Uint8List interleaveRGB<T extends NumDataType>(Uint8List srcR, Uint8List srcG,
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

Uint8List interleaveRGBA<T extends NumDataType>(Uint8List srcR, Uint8List srcG,
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
