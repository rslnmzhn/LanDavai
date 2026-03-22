part of '../file_explorer_page.dart';

const Set<String> _supportedImageExtensions = <String>{
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.gif',
  '.bmp',
  '.heic',
  '.heif',
  '.tif',
  '.tiff',
};

const Set<String> _supportedVideoExtensions = <String>{
  '.mp4',
  '.mov',
  '.mkv',
  '.avi',
  '.webm',
  '.m4v',
  '.3gp',
  '.mpeg',
  '.mpg',
};

const Set<String> _supportedAudioExtensions = <String>{
  '.mp3',
  '.m4a',
  '.aac',
  '.flac',
  '.wav',
  '.ogg',
  '.opus',
  '.wma',
};

const Set<String> _supportedTextExtensions = <String>{
  '.txt',
  '.md',
  '.log',
  '.json',
  '.yaml',
  '.yml',
  '.csv',
  '.xml',
};

bool get _useMediaKitForPlayback =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

enum _ExplorerMenuAction {
  sortNameAsc,
  sortNameDesc,
  sortModifiedNewest,
  sortModifiedOldest,
  sortChangedNewest,
  sortChangedOldest,
  sortSizeLargest,
  sortSizeSmallest,
}
