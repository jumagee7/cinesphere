import 'dart:io';
import 'package:video_player/video_player.dart';

VideoPlayerController? createLocalFilePlayerController(String path) {
  try {
    final file = File(path);
    if (file.existsSync()) {
      return VideoPlayerController.file(file);
    }
  } catch (_) {}
  return null;
}

