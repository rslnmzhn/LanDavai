import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class FileHashService {
  Future<String> computeSha256ForPath(String filePath) async {
    final file = File(filePath);
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  String buildStableId(String raw) {
    return sha256.convert(utf8.encode(raw)).toString();
  }
}
