import 'package:psd_sdk/psd_sdk.dart';
import 'package:psd_sdk/src/parse_document.dart';

int sampleReadPsd() {
  final srcPath = 'example/Sample.psd';

  var allocator = MallocAllocator();
  var file = NativeFile(allocator);

  if (!file.openRead(srcPath)) {
    print('Cannot open file.');
    return 1;
  }

  final document = createDocument(file, allocator);

  // var document = create
  return 0;
}

void main() {
  sampleReadPsd();
}
