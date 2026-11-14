import 'dart:io';

/// Creates the parent directory for [savePath] if it doesn't exist.
/// Native-only implementation using dart:io.
Future<void> createDownloadDir(String savePath) async {
  final dir = File(savePath).parent;
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
}

/// Writes string [content] to [filePath], ensuring parent directories exist.
Future<void> writeTextFile(String filePath, String content) async {
  final file = File(filePath);
  if (!file.parent.existsSync()) {
    file.parent.createSync(recursive: true);
  }
  await file.writeAsString(content);
}

/// Checks whether [filePath] exists on the local filesystem.
bool fileExists(String filePath) {
  try {
    return File(filePath).existsSync();
  } catch (_) {
    return false;
  }
}
