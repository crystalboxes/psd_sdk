import 'package:psd_sdk/src/key.dart';
import 'package:psd_sdk/src/log.dart';

import 'allocator.dart';
import 'bit_util.dart';
import 'document.dart';
import 'file.dart';
import 'image_resource_type.dart';
import 'image_resources_section.dart';
import 'sync_file_reader.dart';
import 'thumbnail.dart';

ImageResourcesSection parseImageResourcesSection(
    Document document, File file, Allocator allocator) {
  final imageResources = ImageResourcesSection();

  imageResources.alphaChannels = null;
  imageResources.iccProfile = null;
  imageResources.sizeOfICCProfile = 0;
  imageResources.exifData = null;
  imageResources.sizeOfExifData = 0;
  imageResources.containsRealMergedData = true;
  imageResources.xmpMetadata = null;
  imageResources.thumbnail = null;

  final reader = SyncFileReader(file);
  reader.setPosition(document.imageResourcesSection.offset);

  var leftToRead = document.imageResourcesSection.length;
  while (leftToRead > 0) {
    final signature = reader.readUint32();
    if ((signature != keyValue('8BIM')) && (signature != keyValue('psdM'))) {
      psdError([
        'ImageResources',
        'Image resources section seems to be corrupt, signature does not match "8BIM".'
      ]);
      return imageResources;
    }

    final id = reader.readUint16();

    // the resource name is stored as a Pascal string. note that the string is padded to make the size even.
    final nameLength = reader.readByte();
    final paddedNameLength = roundUpToMultiple(nameLength + 1, 2);
    final name = reader.readBytes(paddedNameLength - 1);

    // the resource data size is also padded to make the size even
    var resourceSize = reader.readUint32();
    resourceSize = roundUpToMultiple(resourceSize, 2);

    switch (id) {
      case ImageResource.IPTC_NAA:
      case ImageResource.CAPTION_DIGEST:
      case ImageResource.PRINT_INFORMATION:
      case ImageResource.PRINT_STYLE:
      case ImageResource.PRINT_SCALE:
      case ImageResource.PRINT_FLAGS:
      case ImageResource.PRINT_FLAGS_INFO:
      case ImageResource.PRINT_INFO:
      case ImageResource.RESOLUTION_INFO:
        // we are currently not interested in this resource, skip it
        reader.skip(resourceSize);
        break;

      case ImageResource.DISPLAY_INFO:
        {
          // the display info resource stores color information and opacity for extra channels contained
          // in the document. these extra channels could be alpha/transparency, as well as spot color
          // channels used for printing.

          // check whether storage for alpha channels has been allocated yet
          // (imageResource::ALPHA_CHANNEL_ASCII_NAMES stores the channel names)
          if (imageResources.alphaChannels == null) {
            // note that this assumes RGB mode
            final channelCount = document.channelCount - 3;
            imageResources.alphaChannels = List(channelCount);
          }

          // ignore: unused_local_variable
          final version = reader.readUint32();

          for (var i = 0; i < imageResources.alphaChannelCount; ++i) {
            var channel = imageResources.alphaChannels[0];
            channel.colorSpace = reader.readUint16();
            channel.color[0] = reader.readUint16();
            channel.color[1] = reader.readUint16();
            channel.color[2] = reader.readUint16();
            channel.color[3] = reader.readUint16();
            channel.opacity = reader.readUint16();
            channel.mode = reader.readByte();
          }
        }
        break;

      case ImageResource.GLOBAL_ANGLE:
      case ImageResource.GLOBAL_ALTITUDE:
      case ImageResource.COLOR_HALFTONING_INFO:
      case ImageResource.COLOR_TRANSFER_FUNCTIONS:
      case ImageResource.MULTICHANNEL_HALFTONING_INFO:
      case ImageResource.MULTICHANNEL_TRANSFER_FUNCTIONS:
      case ImageResource.LAYER_STATE_INFORMATION:
      case ImageResource.LAYER_GROUP_INFORMATION:
      case ImageResource.LAYER_GROUP_ENABLED_ID:
      case ImageResource.LAYER_SELECTION_ID:
      case ImageResource.GRID_GUIDES_INFO:
      case ImageResource.URL_LIST:
      case ImageResource.SLICES:
      case ImageResource.PIXEL_ASPECT_RATIO:
      case ImageResource.ICC_UNTAGGED_PROFILE:
      case ImageResource.ID_SEED_NUMBER:
      case ImageResource.BACKGROUND_COLOR:
      case ImageResource.ALPHA_CHANNEL_UNICODE_NAMES:
      case ImageResource.ALPHA_IDENTIFIERS:
      case ImageResource.COPYRIGHT_FLAG:
      case ImageResource.PATH_SELECTION_STATE:
      case ImageResource.ONION_SKINS:
      case ImageResource.TIMELINE_INFO:
      case ImageResource.SHEET_DISCLOSURE:
      case ImageResource.WORKING_PATH:
      case ImageResource.MAC_PRINT_MANAGER_INFO:
      case ImageResource.WINDOWS_DEVMODE:
        // we are currently not interested in this resource, skip it
        reader.skip(resourceSize);
        break;

      case ImageResource.VERSION_INFO:
        {
          // ignore: unused_local_variable
          final version = reader.readUint32();

          final hasRealMergedData = reader.readByte();
          imageResources.containsRealMergedData = (hasRealMergedData != 0);
          reader.skip(resourceSize - 5);
        }
        break;

      case ImageResource.THUMBNAIL_RESOURCE:
        {
          var thumbnail = Thumbnail();
          imageResources.thumbnail = thumbnail;

          // ignore: unused_local_variable
          final format = reader.readUint32();

          final width = reader.readUint32();
          final height = reader.readUint32();

          // ignore: unused_local_variable
          final widthInBytes = reader.readUint32();

          // ignore: unused_local_variable
          final totalSize = reader.readUint32();

          final binaryJpegSize = reader.readUint32();

          // ignore: unused_local_variable
          final bitsPerPixel = reader.readUint16();
          // ignore: unused_local_variable
          final numberOfPlanes = reader.readUint16();

          thumbnail.width = width;
          thumbnail.height = height;
          thumbnail.binaryJpegSize = binaryJpegSize;
          thumbnail.binaryJpeg = reader.readBytes(binaryJpegSize);

          final bytesToSkip = resourceSize - 28 - binaryJpegSize;
          reader.skip(bytesToSkip);
        }
        break;

      case ImageResource.XMP_METADATA:
        {
          // load the XMP metadata as raw data
          assert(imageResources.xmpMetadata != null,
              'File contains more than one XMP metadata resource.');
          final xmpMetadata = reader.readBytes(resourceSize);
          imageResources.xmpMetadata = String.fromCharCodes(xmpMetadata);
        }
        break;

      case ImageResource.ICC_PROFILE:
        {
          // load the ICC profile as raw data
          assert(imageResources.iccProfile != null,
              'File contains more than one ICC profile.');
          imageResources.sizeOfICCProfile = resourceSize;
          imageResources.iccProfile = reader.readBytes(resourceSize);
        }
        break;

      case ImageResource.EXIF_DATA:
        {
          // load the EXIF data as raw data
          assert(imageResources.exifData != null,
              'File contains more than one EXIF data block.');
          imageResources.sizeOfExifData = resourceSize;
          imageResources.exifData = reader.readBytes(resourceSize);
        }
        break;

      case ImageResource.ALPHA_CHANNEL_ASCII_NAMES:
        {
          // check whether storage for alpha channels has been allocated yet
          // (imageResource::DISPLAY_INFO stores the channel color data)
          if (imageResources.alphaChannels == null) {
            // note that this assumes RGB mode
            final channelCount = document.channelCount - 3;
            imageResources.alphaChannels = List(channelCount);
          }

          // the names of the alpha channels are stored as a series of Pascal strings
          var channel = 0;
          var remaining = resourceSize;
          while (remaining > 0) {
            String channelName;
            final channelNameLength = reader.readByte();
            if (channelNameLength > 0) {
              var channelNameUint8List = reader.readBytes(channelNameLength);
              channelName = String.fromCharCodes(channelNameUint8List);
            }

            remaining -= 1 + channelNameLength;

            if (channel < imageResources.alphaChannelCount) {
              imageResources.alphaChannels[channel].asciiName = channelName;
              ++channel;
            }
          }
        }
        break;

      default:
        // this is a resource we know nothing about, so skip it
        reader.skip(resourceSize);
        break;
    }
    leftToRead -= 10 + paddedNameLength + resourceSize;
  }
  return imageResources;
}

void destroyImageResourcesSection(
    ImageResourcesSection section, Allocator allocator) {}
