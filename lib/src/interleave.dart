import 'dart:typed_data';
import 'data_types.dart';

int InterleaveBlocks(Uint8List srcR, Uint8List srcG, Uint8List srcB, num alpha,
    Uint8List dest, int width, int height, int blockSize) {
  final pixelCount = width * height;
  final blockCount = pixelCount / blockSize;

  assert(false);
  // Int32x4 va;
  // if (alpha is double) {
  //   va = Int32x4.fromFloat32x4Bits(Float32x4(alpha, alpha, alpha, alpha));
  // } else {
  //   va = Int32x4(alpha, alpha, alpha, alpha);
  // }
  // var srcROffset = 0;
  // var destOffset = 0;

  // for (var i = 0;
  //     i < blockCount;
  //     ++i, srcROffset += blockSize, destOffset += blockSize * 4) {
  //   // load pixels from R, G, B
  //   final vr = srcR.buffer.asInt32x4List(srcROffset, 1)[0];
  //   final vg = srcG.buffer.asInt32x4List(srcROffset, 1)[0];
  //   final vb = srcB.buffer.asInt32x4List(srcROffset, 1)[0];

  // 		// interleave R and G
  // 		final rg_interleaved_lo = InterleaveLo<sizeof(T)>(vr, vg);
  // 		final rg_interleaved_hi = InterleaveHi<sizeof(T)>(vr, vg);

  // 		// interleave B and A
  // 		final ba_interleaved_lo = InterleaveLo<sizeof(T)>(vb, va);
  // 		final ba_interleaved_hi = InterleaveHi<sizeof(T)>(vb, va);
  // }
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
void InterleaveRGB<T extends NumDataType>(Uint8List srcR, Uint8List srcG,
    Uint8List srcB, num alpha, Uint8List dest, int width, int height,
    [int blockSize = 4]) {
  assert(false);
  // do blocks first, and then copy remaining pixels
  // const unsigned int blockCount = InterleaveBlocks(srcR, srcG, srcB, alpha, dest, width, height, blockSize);
  // const unsigned int remaining = width*height - blockCount*blockSize;
  // CopyRemainingPixels(srcR + blockCount*blockSize, srcG + blockCount*blockSize, srcB + blockCount*blockSize, alpha, dest + blockCount*blockSize*4u, remaining);
}
// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------

void InterleaveRGBA<T extends NumDataType>(Uint8List srcR, Uint8List srcG,
    Uint8List srcB, Uint8List srcA, Uint8List dest, int width, int height,
    [int blockSize = 4]) {
  // do blocks first, and then copy remaining pixels
  // final blockCount = InterleaveBlocks(srcR, srcG, srcB, srcA, dest, width, height, blockSize);
  final blockCount = 0;
  final remaining = width * height - blockCount * blockSize;
  CopyRemainingPixels<T>(
      srcR.sublist(blockCount * blockSize),
      srcG.sublist(blockCount * blockSize),
      srcB.sublist(blockCount * blockSize),
      srcA.sublist(blockCount * blockSize),
      dest,
      remaining,
      blockCount * blockSize);
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
void CopyRemainingPixels<T extends NumDataType>(Uint8List srcR, Uint8List srcG,
    Uint8List srcB, Uint8List srcA, Uint8List dest, int count, int offset) {
  var srcR2 = getTypedList<T>(srcR) as List;
  var srcG2 = getTypedList<T>(srcG) as List;
  var srcB2 = getTypedList<T>(srcB) as List;
  var srcA2 = getTypedList<T>(srcA) as List;
  var destTyped = getTypedList<T>(dest) as List;

  for (var i = 0; i < count; ++i) {
    destTyped[offset + i * 4 + 0] = srcR2[i];
    destTyped[offset + i * 4 + 1] = srcG2[i];
    destTyped[offset + i * 4 + 2] = srcB2[i];
    destTyped[offset + i * 4 + 3] = srcA2[i];
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
void CopyRemainingPixelsRGB<T extends NumDataType>(
    Uint8List srcR,
    Uint8List srcG,
    Uint8List srcB,
    int alpha,
    Uint8List dest,
    int count,
    int offset) {
  var srcR2 = getTypedList<T>(srcR) as List;
  var srcG2 = getTypedList<T>(srcG) as List;
  var srcB2 = getTypedList<T>(srcB) as List;
  var destTyped = getTypedList<T>(dest) as List;

  for (var i = 0; i < count; ++i) {
    destTyped[offset + i * 4 + 0] = srcR2[i];
    destTyped[offset + i * 4 + 1] = srcG2[i];
    destTyped[offset + i * 4 + 2] = srcB2[i];
    destTyped[offset + i * 4 + 3] = alpha;
  }
}
