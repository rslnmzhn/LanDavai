import 'dart:io';

const Set<String> explorerImageExtensions = <String>{
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

const Set<String> explorerVideoExtensions = <String>{
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

const Set<String> explorerAudioExtensions = <String>{
  '.mp3',
  '.m4a',
  '.aac',
  '.flac',
  '.wav',
  '.ogg',
  '.opus',
  '.wma',
};

const Set<String> explorerTextExtensions = <String>{
  '.txt',
  '.md',
  '.log',
  '.json',
  '.yaml',
  '.yml',
  '.csv',
  '.xml',
};

bool get useMediaKitForPlayback =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

enum ExplorerMenuAction {
  sortNameAsc,
  sortNameDesc,
  sortModifiedNewest,
  sortModifiedOldest,
  sortChangedNewest,
  sortChangedOldest,
  sortSizeLargest,
  sortSizeSmallest,
}
