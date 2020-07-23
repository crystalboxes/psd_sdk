class CompressionType {
  ///< Raw data.
  static const RAW = 0;

  ///< RLE-compressed data (using the PackBits algorithm).
  static const RLE = 1;

  ///< ZIP-compressed data.
  static const ZIP = 2;

  ///< ZIP-compressed data with prediction (delta-encoding).
  static const ZIP_WITH_PREDICTION = 3;
}
