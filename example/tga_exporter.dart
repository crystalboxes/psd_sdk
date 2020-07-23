import 'dart:io';
import 'dart:typed_data';

import 'package:psd_sdk/psd_sdk.dart';

class TgaType {
  // TGA file contains BGR triplets of color data.
  static const BGR_UNCOMPRESSED = 2;

  // TGA file contains grayscale values.
  static const MONO_UNCOMPRESSED = 3;
}

class TgaHeader {
  /* uint8_t */
  int idLength;
  /* uint8_t */
  int paletteType;
  /* uint8_t */
  int type;
  /* uint16_t */
  int paletteOffset;
  /* uint16_t */
  int paletteLength;
  /* uint8_t */
  int bitsPerPaletteEntry;
  /* uint16_t */
  int originX;
  /* uint16_t */
  int originY;
  /* uint16_t */
  int width;
  /* uint16_t */
  int height;
  /* uint8_t */
  int bitsPerPixel;
  /* uint8_t */
  int attributes;
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
TgaHeader createHeader(int width, int height, int type, int bitsPerPixel) {
  var header = TgaHeader();
  header.idLength = 0;
  header.paletteType = 0;
  header.type = type;
  header.paletteOffset = 0;
  header.paletteLength = 0;
  header.bitsPerPaletteEntry = 0;
  header.originX = 0;
  header.originY = 0;
  header.width = width;
  header.height = height;
  header.bitsPerPixel = bitsPerPixel;
  header.attributes = 0x20;
  return header;
}

class TgaFile {
  String filename;
  File _file;

  TgaFile(this.filename) {
    _file = File(filename);
  }

  void write<T extends NumDataType>(num value) {
    var length = sizeof<T>();
    var bd = ByteData(length);
    setByteData<T>(bd, value);

    for (var x = 0; x < length; x++) {
      list.add(bd.getUint8(x));
    }
  }

  void writeHeader(TgaHeader header) {
    write<uint8_t>(header.idLength);
    write<uint8_t>(header.paletteType);
    write<uint8_t>(header.type);
    write<uint16_t>(header.paletteOffset);
    write<uint16_t>(header.paletteLength);
    write<uint8_t>(header.bitsPerPaletteEntry);
    write<uint16_t>(header.originX);
    write<uint16_t>(header.originY);
    write<uint16_t>(header.width);
    write<uint16_t>(header.height);
    write<uint8_t>(header.bitsPerPixel);
    write<uint8_t>(header.attributes);
  }

  var list = <int>[];

  void writeBytes(Uint8List bytes) {
    list.addAll(bytes);
    _bytes = Uint8List.fromList(list);
  }

  bool close() {
    try {
      _file.writeAsBytesSync(_bytes);
      return true;
    } catch (e) {
      return false;
    }
  }

  Uint8List _bytes;
}

TgaFile createFile(String filename) {
  return TgaFile(filename);
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
void saveMonochrome(String filename, int width, int height, Uint8List data) {
  var file = createFile(filename);

  var header = createHeader(width, height, TgaType.MONO_UNCOMPRESSED, 8);
  file.writeHeader(header);
  file.writeBytes(data);
  if (!file.close()) {
    print("Couldn't write the file");
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
void saveRGB(String filename, int width, int height, Uint8List data) {
  var file = createFile(filename);

  var header = createHeader(width, height, TgaType.BGR_UNCOMPRESSED, 24);
  file.writeHeader(header);

  final colors = Uint8List(width * height * 3);
  for (var i = 0; i < height; ++i) {
    for (var j = 0; j < width; ++j) {
      final r = data[(i * width + j) * 4 + 0];
      final g = data[(i * width + j) * 4 + 1];
      final b = data[(i * width + j) * 4 + 2];

      colors[(i * width + j) * 3 + 2] = r;
      colors[(i * width + j) * 3 + 1] = g;
      colors[(i * width + j) * 3 + 0] = b;
    }
  }

  file.writeBytes(colors);
  if (!file.close()) {
    print("Couldn't write the file");
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// ---------------------------------------------------------------------------------------------------------------------
void saveRGBA(String filename, int width, int height, Uint8List data) {
  var file = createFile(filename);

  var header = createHeader(width, height, TgaType.BGR_UNCOMPRESSED, 32);
  file.writeHeader(header);

  final colors = Uint8List(width * height * 4);
  for (var i = 0; i < height; ++i) {
    for (var j = 0; j < width; ++j) {
      final r = data[(i * width + j) * 4 + 0];
      final g = data[(i * width + j) * 4 + 1];
      final b = data[(i * width + j) * 4 + 2];
      final a = data[(i * width + j) * 4 + 3];

      colors[(i * width + j) * 4 + 2] = r;
      colors[(i * width + j) * 4 + 1] = g;
      colors[(i * width + j) * 4 + 0] = b;
      colors[(i * width + j) * 4 + 3] = a;
    }
  }
  file.writeBytes(colors);
  if (!file.close()) {
    print("Couldn't write the file");
  }
}
