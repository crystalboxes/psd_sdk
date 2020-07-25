import 'dart:typed_data';

import 'package:test/test.dart';

void canvasDataTest(List<Uint8List> canvasData, Uint8List image8) {
  group('canvas data', () {
    test('canvas data 0', () {
      // test cavnas data 0
      expect(canvasData[0][0], 102);
      expect(canvasData[0][20971], 255);
      expect(canvasData[0][41942], 0);
      expect(canvasData[0][62913], 255);
      expect(canvasData[0][83884], 0);
      expect(canvasData[0][104855], 255);
      expect(canvasData[0][125826], 0);
    });

    test('canvas data 1', () {
      expect(canvasData[1][0], 43);
      expect(canvasData[1][1923], 0);
      expect(canvasData[1][3846], 0);
      expect(canvasData[1][5769], 0);
      expect(canvasData[1][7692], 0);
      expect(canvasData[1][9615], 255);
      expect(canvasData[1][11538], 39);
      expect(canvasData[1][13461], 44);
      expect(canvasData[1][15384], 175);
    });

    test('canvas data 2', () {
      expect(canvasData[2][0], 14);
      expect(canvasData[2][1024], 9);
      expect(canvasData[2][2048], 11);
      expect(canvasData[2][3072], 14);
      expect(canvasData[2][4096], 14);
      expect(canvasData[2][5120], 16);
      expect(canvasData[2][6144], 14);
      expect(canvasData[2][7168], 13);

      expect(canvasData[2][31744], 67);
      expect(canvasData[2][32768], 67);
      expect(canvasData[2][33792], 57);
    });

    test('canvas data 3', () {
      expect(canvasData[3][0], 255);
      expect(canvasData[3][1349], 255);
      expect(canvasData[3][2698], 0);
      expect(canvasData[3][4047], 0);
      expect(canvasData[3][5396], 255);
      expect(canvasData[3][6745], 0);
      expect(canvasData[3][8094], 0);
      expect(canvasData[3][9443], 255);
      expect(canvasData[3][10792], 0);
      expect(canvasData[3][12141], 0);
      expect(canvasData[3][13490], 255);
      expect(canvasData[3][14839], 0);
      expect(canvasData[3][16188], 0);
      expect(canvasData[3][17537], 255);
    });
  });

  test('image8', () {
    expect(image8[0], 102);
    expect(image8[1], 43);
    expect(image8[2], 14);
    expect(image8[3], 255);
    expect(image8[4], 128);
    expect(image8[5], 65);
    expect(image8[6], 35);
    expect(image8[7], 255);

    expect(image8[496974], 53);
    expect(image8[497313], 255);
    expect(image8[497652], 255);
    expect(image8[497991], 0);
    expect(image8[498330], 0);
    expect(image8[498669], 0);
    expect(image8[499008], 0);
    expect(image8[499347], 0);
    expect(image8[499686], 0);
  });
}
