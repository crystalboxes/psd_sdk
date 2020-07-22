import 'package:psd_sdk/psd_sdk.dart';

int sampleReadPsd() {
  final srcPath = 'example/Sample.psd';

  var allocator = MallocAllocator();
  var file = NativeFile(allocator);

  if (!file.openRead(srcPath)) {
    print('Cannot open file.');
    return 1;
  }

  final document = createDocument(file, allocator);
  if (document == null) {
    print('Cannot create document.');
    file.close();
    return 1;
  }

  // the sample only supports RGB colormode
  if (document.colorMode != ColorMode.RGB) {
    print('Document is not in RGB color mode.\n');
    destroyDocument(document, allocator);
    file.close();
    return 1;
  }

  // extract image resources section.
  // this gives access to the ICC profile, EXIF data and XMP metadata.
  {
    var imageResourcesSection =
        parseImageResourcesSection(document, file, allocator);
    print('XMP metadata:');
    print(imageResourcesSection.xmpMetadata);
    print('\n');
    destroyImageResourcesSection(imageResourcesSection, allocator);
  }

  // var document = create
  return 0;
}

void main() {
  sampleReadPsd();
}
