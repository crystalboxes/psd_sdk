import 'dart:typed_data';

import 'log.dart';

void decompressRle(Uint8List srcData, int srcSize, Uint8List dest, int size) {
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

int compressRle(Uint8List src, Uint8List dest, int size) {
  var runLength = 0;
  var nonRunLength = 0;

  var rleDataSize = 0;

  var dstPos = 0;
  for (var i = 1; i < size; ++i) {
    final previous = src[i - 1];
    final current = src[i];
    if (previous == current) {
      if (nonRunLength != 0) {
        // first repeat of a character

        // write non-run bytes so far
        dest[dstPos++] = (nonRunLength - 1);
        for (var x = 0; x < nonRunLength; x++) {
          dest[dstPos + x] = src[x + i - nonRunLength - 1];
        }
        dstPos += nonRunLength;
        rleDataSize += 1 + nonRunLength;

        nonRunLength = 0;
      }

      // belongs to the same run
      ++runLength;

      // maximum length of a run is 128
      if (runLength == 128) {
        // need to manually stop this run and write to output
        dest[dstPos++] = (257 - runLength);
        dest[dstPos++] = current;
        rleDataSize += 2;

        runLength = 0;
      }
    } else {
      if (runLength != 0) {
        // include first character and encode this run
        ++runLength;

        dest[dstPos++] = (257 - runLength);
        dest[dstPos++] = previous;
        rleDataSize += 2;

        runLength = 0;
      } else {
        ++nonRunLength;
      }

      // maximum length of a non-run is 128 bytes
      if (nonRunLength == 128) {
        dest[dstPos++] = (nonRunLength - 1);
        for (var x = 0; x < nonRunLength; x++) {
          dest[dstPos + x] = src[x + i - nonRunLength];
        }
        dstPos += nonRunLength;
        rleDataSize += 1 + nonRunLength;

        nonRunLength = 0;
      }
    }
  }

  if (runLength != 0) {
    ++runLength;

    dest[dstPos++] = (257 - runLength);
    dest[dstPos++] = src[size - 1];
    rleDataSize += 2;
  } else {
    ++nonRunLength;
    dest[dstPos++] = (nonRunLength - 1);
    for (var x = 0; x < nonRunLength; x++) {
      dest[dstPos + x] = src[x + size - nonRunLength];
    }
    dstPos += nonRunLength;
    rleDataSize += 1 + nonRunLength;
  }

  // pad to an even number of bytes
  if (rleDataSize & 1 != 0) {
    dest[dstPos++] = 0x80;
    ++rleDataSize;
  }

  return rleDataSize;
}
