int keyValue(String key) {
  assert(key.length == 4);
  return (key.codeUnitAt(0) & 0xFFFFFFFF) << 24 |
      (key.codeUnitAt(1) & 0xFFFFFFFF) << 16 |
      (key.codeUnitAt(2) & 0xFFFFFFFF) << 8 |
      (key.codeUnitAt(3) & 0xFFFFFFFF);
}
