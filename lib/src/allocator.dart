abstract class Allocator {
  dynamic allocate(int size, int alignment);
  void free(dynamic ptr);
}
