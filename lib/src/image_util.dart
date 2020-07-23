// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
import 'dart:typed_data';

import 'package:psd_sdk/src/log.dart';

import 'data_types.dart';

void DecompressRle(Uint8List srcData, int srcSize, Uint8List dest, int size) {
  var bytesRead = 0;
  var offset = 0;

  var src = 0;
  while (offset < size) {
    if (bytesRead >= srcSize) {
      psdError(['DecompressRle', 'Malformed RLE data encountered']);
      return;
    }

    final byte = srcData[src++];
    ++bytesRead;

    if (byte == 0x80) {
      // byte == -128 (0x80) is a no-op
    }
    // 0x81 - 0XFF
    else if (byte > 0x80) {
      // next 257-byte bytes are replicated from the next source byte
      final count = (257 - byte);
      for (var j = 0; j < count; j++) {
        dest[offset + j] = srcData[src];
      }
      src += 1;
      offset += count;

      ++bytesRead;
    }
    // 0x00 - 0x7F
    else {
      // copy next byte+1 bytes 1-by-1
      final count = (byte + 1);

      for (var j = 0; j < count; j++) {
        dest[offset + j] = srcData[src + j];
      }

      src += count;
      offset += count;

      bytesRead += count;
    }
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
bool IsOutside(int layerLeft, int layerTop, int layerRight, int layerBottom,
    int canvasWidth, int canvasHeight) {
  // layer data can be completely outside the canvas, or overlapping, or completely inside.
  // find the overlapping rectangle first.
  final w = (canvasWidth);
  final h = (canvasHeight);
  if ((layerLeft >= w) ||
      (layerTop >= h) ||
      (layerRight < 0) ||
      (layerBottom < 0)) {
    // layer data is completely outside
    return true;
  }

  return false;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
bool IsSameRegion(int layerLeft, int layerTop, int layerRight, int layerBottom,
    int canvasWidth, int canvasHeight) {
  final w = (canvasWidth);
  final h = (canvasHeight);
  if ((layerLeft == 0) &&
      (layerTop == 0) &&
      (layerRight == w) &&
      (layerBottom == h)) {
    // layer region exactly matches the canvas
    return true;
  }

  return false;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
void CopyLayerData<T extends NumDataType>(
    Uint8List layerData,
    Uint8List canvasData,
    int layerLeft,
    int layerTop,
    int layerRight,
    int layerBottom,
    int canvasWidth,
    int canvasHeight) {
  final isOutside = IsOutside(
      layerLeft, layerTop, layerRight, layerBottom, canvasWidth, canvasHeight);
  if (isOutside) {
    return;
  }

  var isSameRegion = IsSameRegion(
      layerLeft, layerTop, layerRight, layerBottom, canvasWidth, canvasHeight);
  if (isSameRegion) {
    // fast path, the layer is exactly the same size as the canvas

    for (var x = 0; x < canvasWidth * canvasHeight * sizeof<T>(); x++) {
      canvasData[x] = layerData[x];
    }
    return;
  }

  // slower path, find the extents of the overlapping region to copy
  final w = (canvasWidth);
  final h = (canvasHeight);
  final left = layerLeft > 0 ? layerLeft : 0;
  final top = layerTop > 0 ? layerTop : 0;
  final right = layerRight < w ? layerRight : w;
  final bottom = layerBottom < h ? layerBottom : h;

  // setup source and destination data so we can copy row by row
  final regionWidth = right - left;
  final regionHeight = bottom - top;
  final planarWidth = layerRight - layerLeft;
  var srcOffset = 0 + (top - layerTop) * planarWidth + (left - layerLeft);
  var dstOffset = 0 + top * canvasWidth + (left);

  for (var y = 0; y < regionHeight; ++y) {
    for (var x = 0; x < (regionWidth) * sizeof<T>(); x++) {
      canvasData[dstOffset + x] = layerData[srcOffset + x];
    }
    dstOffset += canvasWidth;
    srcOffset += planarWidth;
  }
}
