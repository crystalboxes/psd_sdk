bool IsPowerOfTwo(int x) => (x & (x - 1)) == 0;

int roundUpToMultiple(int numToRound, int multipleOf) {
  assert(IsPowerOfTwo(multipleOf), 'Expected a power-of-two.');
  return (numToRound + (multipleOf - 1)) & ~(multipleOf - 1);
}
