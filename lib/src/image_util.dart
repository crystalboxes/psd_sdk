import 'dart:typed_data';

import 'data_types.dart';

/// Copies planar layer data to a canvas. Only the parts overlapping the canvas will be copied to it.
bool copyLayerData(
    Uint8List layerData,
    Uint8List canvasData,
    int bitsPerChannel,
    int layerLeft,
    int layerTop,
    int layerRight,
    int layerBottom,
    int canvasWidth,
    int canvasHeight) {
  if (bitsPerChannel == 8) {
    _copyLayerData<Uint8T>(layerData, canvasData, layerLeft, layerTop,
        layerRight, layerBottom, canvasWidth, canvasHeight);
    return true;
  } else if (bitsPerChannel == 16) {
    _copyLayerData<Uint16T>(layerData, canvasData, layerLeft, layerTop,
        layerRight, layerBottom, canvasWidth, canvasHeight);
    return true;
  } else if (bitsPerChannel == 32) {
    _copyLayerData<Float32T>(layerData, canvasData, layerLeft, layerTop,
        layerRight, layerBottom, canvasWidth, canvasHeight);
    return true;
  } else {
    return false;
  }
}

bool _isOutside(int layerLeft, int layerTop, int layerRight, int layerBottom,
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

bool _isSameRegion(int layerLeft, int layerTop, int layerRight, int layerBottom,
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

void _copyLayerData<T extends NumDataType>(
    Uint8List layerData,
    Uint8List canvasData,
    int layerLeft,
    int layerTop,
    int layerRight,
    int layerBottom,
    int canvasWidth,
    int canvasHeight) {
  final isOutside = _isOutside(
      layerLeft, layerTop, layerRight, layerBottom, canvasWidth, canvasHeight);
  if (isOutside) {
    return;
  }

  var isSameRegion = _isSameRegion(
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
