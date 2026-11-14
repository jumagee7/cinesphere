/// Web stub — no file system available.
Future<void> createDownloadDir(String savePath) async {
  // No-op on web: dart:io is unavailable.
}

/// Web stub — no file system available.
Future<void> writeTextFile(String filePath, String content) async {
  // No-op on web.
}

/// Web stub — no file system available.
bool fileExists(String filePath) => false;
