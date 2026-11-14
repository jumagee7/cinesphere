import 'dart:async';
import 'dart:io' show Platform, Directory, File, HttpStatus;
import 'package:dio/dio.dart' as dio_pkg;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'diagnostic_service.dart';
import 'download_dir_native.dart' if (dart.library.html) 'download_dir_web.dart'
    as download_dir;
import 'os_notifications.dart';
import 'platform_media_channel.dart';
import 'settings_service.dart';

/// Represents a download progress update with speed, byte counters, and formatted strings.
class DownloadProgressUpdate {
  final String id;
  final double progress; // 0.0 to 1.0
  final int receivedBytes;
  final int totalBytes;
  final int speedBytesPerSec;
  final String speedFormatted;
  final String sizeFormatted;

  const DownloadProgressUpdate({
    required this.id,
    required this.progress,
    required this.receivedBytes,
    required this.totalBytes,
    required this.speedBytesPerSec,
    required this.speedFormatted,
    required this.sizeFormatted,
  });

  int get percentage => (progress * 100).round().clamp(0, 100);
}

/// Engine responsible for the physical download transfer of media bytes to storage,
/// tracking download progress, drawing progress on UI, and dispatching native notifications.
class DownloadEngine {
  static String _sanitizeName(String name) {
    final clean = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim();
    return clean.replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Resolves the public base download directory where other apps and file managers can access media.
  static Future<String> getPublicDownloadBaseDir() async {
    if (kIsWeb) return '__web__';
    if (!kIsWeb && Platform.isAndroid) {
      final publicDownload = Directory('/storage/emulated/0/Download');
      if (publicDownload.existsSync()) {
        final cineDir = Directory('${publicDownload.path}/Vyro');
        if (_ensureWritable(cineDir)) return cineDir.path;
        _dlog('⚠️ Shared Downloads folder is not writable — using app storage');
      }
      try {
        final extDirs = await getExternalStorageDirectories(
            type: StorageDirectory.downloads);
        if (extDirs != null && extDirs.isNotEmpty) {
          final cineDir = Directory('${extDirs.first.path}/Vyro');
          if (_ensureWritable(cineDir)) return cineDir.path;
        }
      } catch (_) {}
    }

    try {
      final dlDir = await getDownloadsDirectory();
      if (dlDir != null) {
        final cineDir = Directory('${dlDir.path}/Vyro');
        if (_ensureWritable(cineDir)) return cineDir.path;
      }
    } catch (_) {}

    final docDir = await getApplicationDocumentsDirectory();
    final cineDir = Directory('${docDir.path}/Vyro');
    if (!cineDir.existsSync()) {
      cineDir.createSync(recursive: true);
    }
    return cineDir.path;
  }

  /// Creates [dir] and proves a file can actually be written inside it.
  /// Scoped storage can make the shared Downloads folder exist yet reject
  /// writes, which would otherwise surface as an opaque failed download.
  static bool _ensureWritable(Directory dir) {
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final probe = File('${dir.path}/.cine_write_probe');
      probe.writeAsStringSync('ok');
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Resolves the local absolute filesystem path for a download item.
  /// Mirrors the in-app Downloads browser:
  /// - Movies: /Vyro/Movies/<Movie Title>.mp4
  /// - Series: /Vyro/Series/<Series Title>/Season <X>/<Series Title> - S01E02 - <Episode Title>.mp4
  static Future<String> resolveDownloadPath(
    String id, {
    String? title,
    String? seriesName,
    int? season,
    int? episode,
    String? episodeTitle,
  }) async {
    if (kIsWeb) return '__web__/$id.mp4';
    return downloadPathIn(
      await getPublicDownloadBaseDir(),
      id: id,
      title: title,
      seriesName: seriesName,
      season: season,
      episode: episode,
      episodeTitle: episodeTitle,
    );
  }

  /// Path layout for a finished download under [baseDir]. Exposed so the
  /// Movies/Series tree can be asserted without touching the real disk.
  @visibleForTesting
  static String downloadPathIn(
    String baseDir, {
    required String id,
    String? title,
    String? seriesName,
    int? season,
    int? episode,
    String? episodeTitle,
  }) {
    if (season != null && episode != null) {
      final names = _episodeNames(
        title: title,
        seriesName: seriesName,
        season: season,
        episode: episode,
        episodeTitle: episodeTitle,
      );
      return '$baseDir/Series/${names.series}/${names.season}/'
          '${names.base}.mp4';
    }
    final mName = _movieName(id: id, title: title);
    return '$baseDir/Movies/$mName.mp4';
  }

  /// Resolves the local directory for an offline HLS playlist and its segments.
  /// Final files land in the same Movies/Series tree; the staging folder only
  /// survives when a stream cannot be folded into a single playable file.
  static Future<String> resolveHlsDownloadDir(
    String id, {
    String? title,
    String? seriesName,
    int? season,
    int? episode,
    String? episodeTitle,
  }) async {
    if (kIsWeb) return '__web__/$id';
    return hlsStagingDirIn(
      await getPublicDownloadBaseDir(),
      id: id,
      title: title,
      seriesName: seriesName,
      season: season,
      episode: episode,
      episodeTitle: episodeTitle,
    );
  }

  /// Staging folder layout under [baseDir]. Episodes stage beside their final
  /// file; movies stage in a hidden folder so a failed fold never leaves a
  /// stray movie directory in the flat Movies list.
  @visibleForTesting
  static String hlsStagingDirIn(
    String baseDir, {
    required String id,
    String? title,
    String? seriesName,
    int? season,
    int? episode,
    String? episodeTitle,
  }) {
    if (season != null && episode != null) {
      final names = _episodeNames(
        title: title,
        seriesName: seriesName,
        season: season,
        episode: episode,
        episodeTitle: episodeTitle,
      );
      return '$baseDir/Series/${names.series}/${names.season}/${names.base}';
    }
    final mName = _movieName(id: id, title: title);
    return '$baseDir/.staging/$mName';
  }

  static String _movieName({required String id, String? title}) =>
      _sanitizeName(title != null && title.isNotEmpty ? title : id);

  static ({String series, String season, String base}) _episodeNames({
    required String? title,
    required String? seriesName,
    required int season,
    required int episode,
    required String? episodeTitle,
  }) {
    final sName = _sanitizeName(
      (seriesName != null && seriesName.isNotEmpty)
          ? seriesName
          : (title != null ? title.split(' • ').first : 'Series'),
    );
    final epNum = episode.toString().padLeft(2, '0');
    final sNum = season.toString().padLeft(2, '0');
    final epName = (episodeTitle != null && episodeTitle.isNotEmpty)
        ? ' - ${_sanitizeName(episodeTitle)}'
        : '';
    return (
      series: sName,
      season: 'Season $season',
      base: '$sName - S${sNum}E$epNum$epName',
    );
  }

  /// Ensures the destination folder exists on disk.
  static Future<void> ensureDownloadDir(String savePath) async {
    await download_dir.createDownloadDir(savePath);
    _dlog('📁 download dir ensured for: $savePath');
  }

  /// Transfers a direct stream or file to disk with live progress, speed calculation,
  /// UI drawing callbacks, and native system notification updates.
  static Future<void> executeDownloadWithProgress({
    required String id,
    required String title,
    required String streamUrl,
    required String savePath,
    required Map<String, String>? headers,
    required void Function(DownloadProgressUpdate update) onProgress,
    required bool Function() isCancelledOrPaused,
    bool showNotification = true,
  }) async {
    if (kIsWeb) {
      throw Exception('Downloads are not supported on web.');
    }

    await ensureDownloadDir(savePath);

    int lastReceived = 0;
    int lastTimestamp = DateTime.now().millisecondsSinceEpoch;
    int speedBytesPerSec = 0;
    int lastNotificationTime = 0;
    int lastNotificationPct = -1;

    final dioClient = dio_pkg.Dio();
    try {
      await dioClient.download(
        streamUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (isCancelledOrPaused()) {
            dioClient.close(force: true);
            OsNotifications.cancelDownload(id);
            return;
          }

          final now = DateTime.now().millisecondsSinceEpoch;
          final timeDelta = now - lastTimestamp;
          if (timeDelta >= 400) {
            final bytesDelta = received - lastReceived;
            if (bytesDelta >= 0 && timeDelta > 0) {
              speedBytesPerSec = (bytesDelta * 1000 ~/ timeDelta);
            }
            lastReceived = received;
            lastTimestamp = now;
          }

          final pct = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
          final pctInt = (pct * 100).round();
          final speedStr = _formatSpeed(speedBytesPerSec);
          final sizeStr = _formatTransferSize(received, total);

          final update = DownloadProgressUpdate(
            id: id,
            progress: pct,
            receivedBytes: received,
            totalBytes: total,
            speedBytesPerSec: speedBytesPerSec,
            speedFormatted: speedStr,
            sizeFormatted: sizeStr,
          );

          // 1. Draw progress onto the UI via callback
          onProgress(update);

          // 2. Update Android notification progress bar (throttled)
          if (showNotification &&
              (now - lastNotificationTime >= 750 ||
                  (pctInt - lastNotificationPct).abs() >= 2)) {
            lastNotificationTime = now;
            lastNotificationPct = pctInt;
            final body = speedStr.isNotEmpty
                ? '$pctInt% • $speedStr • $sizeStr'
                : '$pctInt% • $sizeStr';
            OsNotifications.showDownloadProgress(
              key: id,
              title: title,
              progress: pctInt,
              body: body,
            );
          }
        },
        options: dio_pkg.Options(
          headers: headers,
          receiveTimeout: const Duration(minutes: 60),
          sendTimeout: const Duration(seconds: 30),
        ),
      );

      // On successful completion, notify with notification banner
      if (showNotification && !isCancelledOrPaused()) {
        await OsNotifications.showDownloadComplete(
          key: id,
          title: title,
          body: '"$title" is ready to watch offline',
        );
      }
    } catch (e) {
      if (isCancelledOrPaused()) {
        await OsNotifications.cancelDownload(id);
        return;
      }
      _dlog('❌ Download error: $e');
      await OsNotifications.cancelDownload(id);
      throw Exception('Download transfer failed: $e');
    } finally {
      dioClient.close(force: true);
    }
  }

  /// Downloads [streamUrl] for offline playback.
  ///
  /// HLS sources (including master playlists whose URL carries no `.m3u8`
  /// suffix) are staged as a self-contained folder: the selected video
  /// variant, the separate `#EXT-X-MEDIA` audio rendition when the stream
  /// carries one, their keys and segments, plus a rewritten local
  /// `index.m3u8` master playlist. Non-HLS sources are saved as a single file.
  /// Returns the saved path, or an empty string when cancelled/paused.
  static Future<String> downloadStreamWithProgress({
    required String id,
    required String title,
    String? seriesName,
    int? season,
    int? episode,
    String? episodeTitle,
    required String streamUrl,
    required VideoQuality quality,
    required Map<String, String>? headers,
    required void Function(DownloadProgressUpdate update) onProgress,
    required bool Function() isCancelledOrPaused,
    bool showNotification = true,
    @visibleForTesting String? overrideDir,
  }) async {
    if (kIsWeb) {
      throw Exception('Downloads are not supported on web.');
    }

    final dioClient = dio_pkg.Dio(dio_pkg.BaseOptions(
      headers: headers,
      connectTimeout: const Duration(seconds: 25),
      receiveTimeout: const Duration(seconds: 40),
    ));

    try {
      _dlog(
          'Inspecting stream for "$title": $streamUrl (Quality: ${quality.name})');
      if (!await _looksLikeHls(dioClient, streamUrl)) {
        dioClient.close(force: true);
        _dlog('Direct media stream — saving as a single file');
        final directSavePath = await resolveDownloadPath(
          id,
          title: title,
          seriesName: seriesName,
          season: season,
          episode: episode,
          episodeTitle: episodeTitle,
        );
        await executeDownloadWithProgress(
          id: id,
          title: title,
          streamUrl: streamUrl,
          savePath: directSavePath,
          headers: headers,
          onProgress: onProgress,
          isCancelledOrPaused: isCancelledOrPaused,
          showNotification: showNotification,
        );
        return directSavePath;
      }

      final resp = await dioClient.get<String>(streamUrl);
      final masterBody = resp.data ?? '';
      if (!masterBody.contains('#EXTM3U')) {
        throw Exception('Invalid HLS manifest from server');
      }

      String videoPlaylistUrl = streamUrl;
      String? variantTag;
      String? audioPlaylistUrl;

      // 1. If master playlist, select the matching variant and its audio rendition
      if (masterBody.contains('#EXT-X-STREAM-INF')) {
        final variant = _pickHlsVariant(masterBody, streamUrl, quality);
        if (variant != null) {
          videoPlaylistUrl = variant.url;
          variantTag = variant.tag;
          audioPlaylistUrl =
              _pickAudioRendition(masterBody, streamUrl, variant.audioGroup)
                  ?.url;
        }
      }
      _dlog('Selected HLS variant for ${quality.name}: $videoPlaylistUrl'
          '${audioPlaylistUrl != null ? ' (+ separate audio rendition)' : ''}');

      final hlsDir = overrideDir ??
          await resolveHlsDownloadDir(
            id,
            title: title,
            seriesName: seriesName,
            season: season,
            episode: episode,
            episodeTitle: episodeTitle,
          );
      final localPlaylistPath = '$hlsDir/index.m3u8';
      await download_dir.createDownloadDir(localPlaylistPath);

      final video = await _stagePlaylist(
        dio: dioClient,
        playlistUrl: videoPlaylistUrl,
        hlsDir: hlsDir,
        prefix: 'v_',
      );
      final audio = audioPlaylistUrl == null
          ? null
          : await _stagePlaylist(
              dio: dioClient,
              playlistUrl: audioPlaylistUrl,
              hlsDir: hlsDir,
              prefix: 'a_',
            );

      final jobs = <_SegmentJob>[...video.segments, ...?audio?.segments];
      if (jobs.isEmpty) {
        throw Exception('HLS playlist contains no media segments');
      }

      final totalSegments = jobs.length;
      await _prepareSegmentCache(hlsDir, jobs);

      var completedSegments = 0;
      var downloadedBytes = 0;
      var speedBytesPerSec = 0;
      var lastSpeedTimestamp = DateTime.now().millisecondsSinceEpoch;
      var lastSpeedBytes = 0;
      var lastEmitTimestamp = 0;
      var lastNotificationTime = 0;
      var lastNotificationPct = -1;

      void report({bool force = false}) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final speedWindow = now - lastSpeedTimestamp;
        if (speedWindow >= 400) {
          final delta = downloadedBytes - lastSpeedBytes;
          if (delta >= 0) {
            speedBytesPerSec = delta * 1000 ~/ speedWindow;
          }
          lastSpeedBytes = downloadedBytes;
          lastSpeedTimestamp = now;
        }

        final isFinal = completedSegments >= totalSegments;
        // Several workers can land in the same event-loop turn; redrawing the
        // tile and the notification for each one wastes frames for nothing.
        if (!force && !isFinal && now - lastEmitTimestamp < 150) return;
        lastEmitTimestamp = now;

        final pct = (completedSegments / totalSegments).clamp(0.0, 1.0);
        final pctInt = (pct * 100).round();
        final estimatedTotalBytes =
            pct > 0 ? (downloadedBytes / pct).round() : downloadedBytes;
        final speedStr = _formatSpeed(speedBytesPerSec);
        final sizeStr =
            _formatTransferSize(downloadedBytes, estimatedTotalBytes);

        onProgress(DownloadProgressUpdate(
          id: id,
          progress: pct,
          receivedBytes: downloadedBytes,
          totalBytes: estimatedTotalBytes,
          speedBytesPerSec: speedBytesPerSec,
          speedFormatted: speedStr,
          sizeFormatted: sizeStr,
        ));

        if (showNotification &&
            (force ||
                now - lastNotificationTime >= 1000 ||
                (pctInt - lastNotificationPct).abs() >= 5)) {
          lastNotificationTime = now;
          lastNotificationPct = pctInt;
          final body = speedStr.isNotEmpty
              ? '$pctInt% • $speedStr • $sizeStr'
              : '$pctInt% • $sizeStr';
          OsNotifications.showDownloadProgress(
            key: id,
            title: title,
            progress: pctInt,
            body: body,
          );
        }
      }

      _dlog('Beginning download of $totalSegments HLS segments to $hlsDir '
          '($_segmentConcurrency at a time)');

      var nextIndex = 0;
      Object? firstError;

      Future<void> worker() async {
        while (firstError == null) {
          if (isCancelledOrPaused()) return;
          final index = nextIndex++;
          if (index >= totalSegments) return;
          final job = jobs[index];
          final segSavePath = '$hlsDir/${job.localName}';
          try {
            var segmentBytes =
                await _cachedSegmentBytes(segSavePath, job.expectedBytes);
            if (segmentBytes == null) {
              await _downloadSegmentWithRetry(dioClient, job, segSavePath);
              segmentBytes = await File(segSavePath).length();
            }
            downloadedBytes += segmentBytes;
            completedSegments++;
            report(force: completedSegments == totalSegments);
          } catch (e) {
            if (isCancelledOrPaused()) return;
            firstError ??= e;
            return;
          }
        }
      }

      // Pausing must interrupt segments already in flight, otherwise it only
      // takes effect at the next segment boundary.
      final cancelWatcher =
          Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (isCancelledOrPaused()) dioClient.close(force: true);
      });
      try {
        final workerCount = totalSegments < _segmentConcurrency
            ? totalSegments
            : _segmentConcurrency;
        await Future.wait(
            List<Future<void>>.generate(workerCount, (_) => worker()));
      } finally {
        cancelWatcher.cancel();
      }

      if (isCancelledOrPaused()) {
        dioClient.close(force: true);
        OsNotifications.cancelDownload(id);
        return '';
      }
      if (firstError != null) {
        throw firstError!;
      }

      // Write rewritten playlists and the local master that ties them together.
      await download_dir.writeTextFile(
          '$hlsDir/video.m3u8', video.lines.join('\n'));
      if (audio != null) {
        await download_dir.writeTextFile(
            '$hlsDir/audio.m3u8', audio.lines.join('\n'));
      }
      await download_dir.writeTextFile(
        localPlaylistPath,
        _buildLocalMaster(variantTag, hasAudio: audio != null),
      );
      _dlog('✅ HLS offline playlist saved: $localPlaylistPath');

      // Fold the staged segments into one playable file, so a download shows
      // up as a single video instead of a folder of .ts chunks.
      final singleFile = await _foldIntoSingleFile(
        id: id,
        title: title,
        seriesName: seriesName,
        season: season,
        episode: episode,
        episodeTitle: episodeTitle,
        hlsDir: hlsDir,
        video: video,
        audio: audio,
      );
      if (singleFile != null) {
        _dlog('✅ Single-file download saved: $singleFile');
      }

      if (showNotification && !isCancelledOrPaused()) {
        await OsNotifications.showDownloadComplete(
          key: id,
          title: title,
          body: '"$title" is ready to watch offline',
        );
      }

      return singleFile ?? localPlaylistPath;
    } catch (e) {
      if (isCancelledOrPaused()) {
        await OsNotifications.cancelDownload(id);
        return '';
      }
      _dlog('❌ Download error: $e');
      await OsNotifications.cancelDownload(id);
      throw Exception('Download failed: $e');
    } finally {
      dioClient.close(force: true);
    }
  }

  /// Segments are independent HTTP objects, so overlapping a handful of
  /// requests turns a latency-bound fetch into a bandwidth-bound one.
  static const int _segmentConcurrency = 6;

  /// Concatenates the downloaded segments into the item's single save path.
  ///
  /// fMP4 staging already produces a standalone file by prepending the
  /// `#EXT-X-MAP` init segment. MPEG-TS needs a remux (Android only) to carry
  /// a separate audio rendition; when that is unavailable the playlist folder
  /// stays behind, which still plays but shows one file per segment.
  static Future<String?> _foldIntoSingleFile({
    required String id,
    required String title,
    required String? seriesName,
    required int? season,
    required int? episode,
    required String? episodeTitle,
    required String hlsDir,
    required _StagedPlaylist video,
    required _StagedPlaylist? audio,
  }) async {
    // Android is the only target that can finish a TS remux, and it is also
    // the only place downloads are user-visible files. Other platforms keep
    // the staged playlist, which still plays.
    if (!Platform.isAndroid) return null;
    try {
      final outPath = await resolveDownloadPath(
        id,
        title: title,
        seriesName: seriesName,
        season: season,
        episode: episode,
        episodeTitle: episodeTitle,
      );

      // fMP4 fragments are self-contained once the init segment leads them.
      // A separate fMP4 audio rendition would need a real mux, so leave the
      // folder alone rather than saving a video-only file.
      if (video.initName != null) {
        if (audio != null) return null;
        await _concatFiles(outPath, [
          '$hlsDir/${video.initName}',
          for (final job in video.segments) '$hlsDir/${job.localName}',
        ]);
        await _cleanupStaging(hlsDir, keep: outPath);
        return outPath;
      }

      final videoTs = '$hlsDir/.vyro_video.ts';
      await _concatFiles(videoTs, [
        for (final job in video.segments) '$hlsDir/${job.localName}',
      ]);

      String? audioTs;
      if (audio != null && audio.segments.isNotEmpty) {
        audioTs = '$hlsDir/.vyro_audio.ts';
        await _concatFiles(audioTs, [
          for (final job in audio.segments) '$hlsDir/${job.localName}',
        ]);
      }

      final muxed = await PlatformMediaChannel.muxTsToMp4(
        videoPath: videoTs,
        audioPath: audioTs,
        outputPath: outPath,
      );

      for (final temp in [videoTs, audioTs]) {
        if (temp == null) continue;
        try {
          final f = File(temp);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }

      if (!muxed) return null;
      await _cleanupStaging(hlsDir, keep: outPath);
      return outPath;
    } catch (e) {
      _dlog('⚠️ Could not fold segments into a single file: $e');
      return null;
    }
  }

  /// Appends [sources] byte-for-byte into [destPath].
  static Future<void> _concatFiles(
      String destPath, List<String> sources) async {
    final out = File(destPath);
    await out.parent.create(recursive: true);
    final sink = out.openWrite();
    try {
      for (final path in sources) {
        final f = File(path);
        if (!await f.exists()) throw Exception('Missing segment $path');
        await sink.addStream(f.openRead());
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
  }

  /// Removes staging artifacts, keeping the finished media file.
  static Future<void> _cleanupStaging(String dirPath,
      {required String keep}) async {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity.path == keep) continue;
        try {
          await entity.delete(recursive: true);
        } catch (_) {}
      }
      if ((await dir.list(followLinks: false).toList()).isEmpty) {
        await dir.delete();
      }
    } catch (_) {}
  }

  /// One dropped request on a CDN edge should cost a few seconds of retry,
  /// not the whole download.
  static const int _segmentAttempts = 3;

  static const String _resumeMarker = '.vyro_resume';

  /// Reads the first bytes of [url] to tell an m3u8 playlist apart from a
  /// direct media file. Stream URLs such as `…/playlist/<id>?token=…` carry
  /// no `.m3u8` suffix, so a suffix check alone would misroute them.
  static Future<bool> _looksLikeHls(dio_pkg.Dio dio, String url) async {
    final resp = await dio.get<dio_pkg.ResponseBody>(
      url,
      options: dio_pkg.Options(
        responseType: dio_pkg.ResponseType.stream,
        headers: const {'Range': 'bytes=0-1023'},
        validateStatus: (s) => s != null && s >= 200 && s < 500,
      ),
    );
    final status = resp.statusCode ?? 0;
    if (status == HttpStatus.requestedRangeNotSatisfiable) return false;
    if (status >= 400) {
      throw Exception('Stream returned HTTP $status');
    }

    final data = resp.data;
    if (data == null) return false;
    final bytes = <int>[];
    await for (final chunk in data.stream) {
      bytes.addAll(chunk);
      if (bytes.length >= 16) break;
    }
    var start = 0;
    while (start < bytes.length &&
        (bytes[start] == 0x20 ||
            bytes[start] == 0x0A ||
            bytes[start] == 0x0D)) {
      start++;
    }
    if (start + 7 > bytes.length) return false;
    return String.fromCharCodes(bytes.sublist(start, start + 7)) == '#EXTM3U';
  }

  /// Downloads [url] to [savePath] through a `.part` file, so a segment that
  /// was interrupted by a killed process can never masquerade as complete.
  static Future<void> _downloadToFile(
    dio_pkg.Dio dio,
    String url,
    String savePath, {
    String? range,
  }) async {
    final partPath = '$savePath.part';
    try {
      await dio.download(
        url,
        partPath,
        deleteOnError: true,
        options: dio_pkg.Options(
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 20),
          headers: range == null ? null : {'Range': range},
        ),
      );
      await File(partPath).rename(savePath);
    } catch (_) {
      try {
        final part = File(partPath);
        if (await part.exists()) await part.delete();
      } catch (_) {}
      rethrow;
    }
  }

  static Future<void> _downloadSegmentWithRetry(
    dio_pkg.Dio dio,
    _SegmentJob job,
    String savePath,
  ) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _segmentAttempts; attempt++) {
      try {
        await _downloadToFile(dio, job.url, savePath, range: job.rangeHeader);
        return;
      } catch (error) {
        lastError = error;
        if (attempt == _segmentAttempts) break;
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      }
    }
    throw lastError ?? Exception('Segment download failed');
  }

  /// Bytes of an already staged segment, or null when it has to be fetched.
  static Future<int?> _cachedSegmentBytes(
      String path, int? expectedBytes) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final length = await file.length();
      if (length <= 0) return null;
      if (expectedBytes != null && length != expectedBytes) return null;
      return length;
    } catch (_) {
      return null;
    }
  }

  /// Keeps staged segments across pause/resume only while the playlist still
  /// points at the same remote objects: re-resolving a stream can hand back a
  /// different encode, where `seg_0003` is not the same video anymore.
  static Future<void> _prepareSegmentCache(
    String hlsDir,
    List<_SegmentJob> jobs,
  ) async {
    final marker = File('$hlsDir/$_resumeMarker');
    final signature =
        '${jobs.length}|${jobs.map((j) => _stableUrl(j.url)).join('|').hashCode}';
    var reusable = false;
    try {
      reusable =
          await marker.exists() && await marker.readAsString() == signature;
    } catch (_) {}

    if (!reusable) {
      try {
        await for (final entity in Directory(hlsDir).list()) {
          if (entity is! File) continue;
          final name = entity.uri.pathSegments.last;
          if (name.endsWith('.ts') ||
              name.endsWith('.m4s') ||
              name.endsWith('.part')) {
            await entity.delete();
          }
        }
      } catch (_) {}
    }
    try {
      await marker.writeAsString(signature);
    } catch (_) {}
  }

  /// Segment URLs carry rotating tokens; resume only cares that the host and
  /// path of every segment still line up with what was staged.
  static String _stableUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    return '${uri.host}${uri.path}';
  }

  /// Rewrites a media playlist so every key, init map and segment it
  /// references is a local file inside [hlsDir]. Keys and init maps are
  /// downloaded immediately; segments are returned as download jobs.
  static Future<_StagedPlaylist> _stagePlaylist({
    required dio_pkg.Dio dio,
    required String playlistUrl,
    required String hlsDir,
    required String prefix,
  }) async {
    final resp = await dio.get<String>(playlistUrl);
    final body = resp.data ?? '';
    if (!body.contains('#EXTM3U')) {
      throw Exception('Invalid HLS media playlist at $playlistUrl');
    }

    final playlistUri = Uri.parse(playlistUrl);
    final lines = <String>[];
    final segments = <_SegmentJob>[];
    final keyNames = <String, String>{};
    var initIndex = 0;
    String? initName;
    int? rangeLength;
    int? rangeOffset;
    var lastRangeEnd = 0;

    for (final raw in body.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      if (!line.startsWith('#')) {
        final start = rangeOffset ?? 0;
        final end = rangeLength != null ? start + rangeLength - 1 : null;
        final localName =
            '${prefix}seg_${segments.length.toString().padLeft(4, '0')}.ts';
        segments.add(_SegmentJob(
          url: playlistUri.resolve(line).toString(),
          localName: localName,
          rangeHeader: end == null ? null : 'bytes=$start-$end',
          expectedBytes: rangeLength,
        ));
        if (end != null) lastRangeEnd = end + 1;
        rangeLength = null;
        rangeOffset = null;
        lines.add(localName);
        continue;
      }

      if (line.startsWith('#EXT-X-KEY')) {
        final keyUri = RegExp(r'URI="([^"]+)"').firstMatch(line)?.group(1);
        if (keyUri == null || line.contains('METHOD=NONE')) {
          lines.add(line);
          continue;
        }
        final keyUrl = playlistUri.resolve(keyUri).toString();
        final keyName = keyNames.putIfAbsent(
            keyUrl, () => '${prefix}key_${keyNames.length}.bin');
        await _downloadToFile(dio, keyUrl, '$hlsDir/$keyName');
        lines.add(line.replaceFirst(RegExp(r'URI="[^"]+"'), 'URI="$keyName"'));
        continue;
      }

      if (line.startsWith('#EXT-X-MAP')) {
        final mapUri = RegExp(r'URI="([^"]+)"').firstMatch(line)?.group(1);
        if (mapUri == null) {
          lines.add(line);
          continue;
        }
        final mapUrl = playlistUri.resolve(mapUri).toString();
        final mapName = '${prefix}init_${initIndex++}.mp4';
        await _downloadToFile(dio, mapUrl, '$hlsDir/$mapName');
        initName ??= mapName;
        lines.add(line.replaceFirst(RegExp(r'URI="[^"]+"'), 'URI="$mapName"'));
        continue;
      }

      if (line.startsWith('#EXT-X-BYTERANGE')) {
        // Each remote byte range becomes its own complete local segment, so
        // the tag itself is dropped from the rewritten playlist.
        final spec = line.substring('#EXT-X-BYTERANGE:'.length).trim();
        final parts = spec.split('@');
        rangeLength = int.tryParse(parts[0].trim());
        rangeOffset = parts.length > 1
            ? int.tryParse(parts[1].trim())
            : (rangeLength != null ? lastRangeEnd : null);
        continue;
      }

      lines.add(line);
    }

    return _StagedPlaylist(
      lines: lines,
      segments: segments,
      initName: initName,
    );
  }

  /// Builds the offline master playlist pointing at the staged video (and
  /// audio) media playlists, preserving the chosen variant's attributes.
  static String _buildLocalMaster(String? variantTag,
      {required bool hasAudio}) {
    final b = StringBuffer('#EXTM3U\n#EXT-X-VERSION:3\n');
    if (hasAudio) {
      b.writeln('#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Audio",'
          'DEFAULT=YES,AUTOSELECT=YES,URI="audio.m3u8"');
    }
    b.writeln('#EXT-X-STREAM-INF:'
        '${_normalizeVariantTag(variantTag, hasAudio: hasAudio)}');
    b.writeln('video.m3u8');
    return b.toString();
  }

  /// Drops rendition references we do not stage (subtitles/captions) and
  /// points the `AUDIO` attribute at the local audio group.
  static String _normalizeVariantTag(String? tag, {required bool hasAudio}) {
    final parts = <String>[];
    if (tag != null && tag.trim().isNotEmpty) {
      final buf = StringBuffer();
      var inQuotes = false;
      for (final code in tag.trim().codeUnits) {
        final ch = String.fromCharCode(code);
        if (ch == '"') inQuotes = !inQuotes;
        if (ch == ',' && !inQuotes) {
          parts.add(buf.toString());
          buf.clear();
          continue;
        }
        buf.write(ch);
      }
      if (buf.isNotEmpty) parts.add(buf.toString());
    }

    final kept = parts.map((p) => p.trim()).where((p) {
      if (p.isEmpty) return false;
      final key = p.split('=').first.trim().toUpperCase();
      return key != 'AUDIO' && key != 'SUBTITLES' && key != 'CLOSED-CAPTIONS';
    }).toList();
    if (kept.isEmpty ||
        !kept.any((p) => p.toUpperCase().startsWith('BANDWIDTH='))) {
      kept.insert(0, 'BANDWIDTH=1');
    }
    if (hasAudio) kept.add('AUDIO="audio"');
    return kept.join(',');
  }

  /// Parses variant streams from a master playlist and selects the best match.
  static _HlsVariant? _pickHlsVariant(
      String masterBody, String baseUrl, VideoQuality quality) {
    final base = Uri.parse(baseUrl);
    final lines = masterBody.split('\n');
    final variants = <_HlsVariant>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;

      final tag = line.substring('#EXT-X-STREAM-INF:'.length);
      int height = 0;
      int bandwidth = 0;

      final resMatch = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(tag);
      if (resMatch != null) {
        height = int.tryParse(resMatch.group(1)!) ?? 0;
      }

      final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(tag);
      if (bwMatch != null) {
        bandwidth = int.tryParse(bwMatch.group(1)!) ?? 0;
      }

      // Find next non-empty, non-tag line as the variant's playlist URL
      for (int j = i + 1; j < lines.length; j++) {
        final nextLine = lines[j].trim();
        if (nextLine.isNotEmpty && !nextLine.startsWith('#')) {
          variants.add(_HlsVariant(
            url: base.resolve(nextLine).toString(),
            tag: tag,
            height: height,
            bandwidth: bandwidth,
            audioGroup: RegExp(r'AUDIO="([^"]*)"').firstMatch(tag)?.group(1),
          ));
          break;
        }
      }
    }

    if (variants.isEmpty) return null;

    int heightOf(_HlsVariant v) => v.height > 0
        ? v.height
        : (v.bandwidth > 2500000 ? 1080 : (v.bandwidth > 1200000 ? 720 : 480));

    // "Highest available" is not a height target: take the tallest rendition
    // the master actually offers, breaking ties on bandwidth.
    if (quality == VideoQuality.highest) {
      var best = variants.first;
      for (final v in variants.skip(1)) {
        final h = heightOf(v);
        final bestH = heightOf(best);
        if (h > bestH || (h == bestH && v.bandwidth > best.bandwidth)) {
          best = v;
        }
      }
      return best;
    }

    int targetHeight = 1080;
    switch (quality) {
      case VideoQuality.uhd4k:
        targetHeight = 2160;
        break;
      case VideoQuality.fullHd1080:
        targetHeight = 1080;
        break;
      case VideoQuality.hd720:
        targetHeight = 720;
        break;
      case VideoQuality.sd480:
        targetHeight = 480;
        break;
      case VideoQuality.auto:
      case VideoQuality.highest:
        targetHeight = 1080;
        break;
    }

    _HlsVariant best = variants.first;
    int minDiff = 999999;
    for (final v in variants) {
      final diff = (heightOf(v) - targetHeight).abs();
      if (diff < minDiff) {
        minDiff = diff;
        best = v;
      }
    }

    return best;
  }

  /// Selects the audio rendition to download: the one referenced by the
  /// chosen variant's AUDIO group, preferring English (matching the device
  /// language the player normally picks), then the master's DEFAULT=YES.
  static _HlsRendition? _pickAudioRendition(
      String masterBody, String baseUrl, String? groupId) {
    final base = Uri.parse(baseUrl);
    final renditions = <_HlsRendition>[];

    for (final raw in masterBody.split('\n')) {
      final line = raw.trim();
      if (!line.startsWith('#EXT-X-MEDIA:')) continue;
      final attrs = line.substring('#EXT-X-MEDIA:'.length);
      if (!RegExp(r'TYPE=AUDIO').hasMatch(attrs)) continue;

      final uri = RegExp(r'URI="([^"]+)"').firstMatch(attrs)?.group(1);
      if (uri == null || uri.isEmpty) continue;

      renditions.add(_HlsRendition(
        url: base.resolve(uri).toString(),
        groupId:
            RegExp(r'GROUP-ID="([^"]*)"').firstMatch(attrs)?.group(1) ?? '',
        language:
            RegExp(r'LANGUAGE="([^"]*)"').firstMatch(attrs)?.group(1) ?? '',
        isDefault: RegExp(r'DEFAULT=YES').hasMatch(attrs),
      ));
    }

    if (renditions.isEmpty) return null;
    final candidates = groupId == null
        ? renditions
        : renditions.where((r) => r.groupId == groupId).toList();
    final pool = candidates.isNotEmpty ? candidates : renditions;

    // Match ExoPlayer's streaming choice: the device-language track when
    // present, otherwise the rendition the master marks as default.
    for (final r in pool) {
      if (r.language.toLowerCase().startsWith('en')) return r;
    }
    for (final r in pool) {
      if (r.isDefault) return r;
    }
    return pool.first;
  }

  /// Backward-compatible download wrapper.
  static Future<void> executeDownload({
    required String streamUrl,
    required String savePath,
    required Map<String, String>? headers,
    required void Function(double progress) onProgress,
    required bool Function() isCancelledOrPaused,
  }) async {
    await executeDownloadWithProgress(
      id: savePath.hashCode.toString(),
      title: 'Downloading media',
      streamUrl: streamUrl,
      savePath: savePath,
      headers: headers,
      onProgress: (u) => onProgress(u.progress),
      isCancelledOrPaused: isCancelledOrPaused,
      showNotification: false,
    );
  }

  static String _formatSpeed(int bytesPerSec) {
    if (bytesPerSec <= 0) return '';
    final kb = bytesPerSec / 1024.0;
    if (kb >= 1024.0) {
      return '${(kb / 1024.0).toStringAsFixed(1)} MB/s';
    }
    return '${kb.toStringAsFixed(0)} KB/s';
  }

  static String _formatTransferSize(int received, int total) {
    if (total <= 0) {
      final mb = received / (1024.0 * 1024.0);
      return '${mb.toStringAsFixed(1)} MB';
    }
    final recMb = received / (1024.0 * 1024.0);
    final totMb = total / (1024.0 * 1024.0);
    if (totMb >= 1024.0) {
      return '${(recMb / 1024.0).toStringAsFixed(2)} GB / ${(totMb / 1024.0).toStringAsFixed(2)} GB';
    }
    return '${recMb.toStringAsFixed(1)} MB / ${totMb.toStringAsFixed(1)} MB';
  }

  static void _dlog(String msg, {LogLevel level = LogLevel.info}) {
    DiagnosticService.instance.log('DownloadEngine', msg, level: level);
  }
}

class _HlsVariant {
  final String url;
  final String tag;
  final int height;
  final int bandwidth;
  final String? audioGroup;

  const _HlsVariant({
    required this.url,
    required this.tag,
    required this.height,
    required this.bandwidth,
    this.audioGroup,
  });
}

class _HlsRendition {
  final String url;
  final String groupId;
  final String language;
  final bool isDefault;

  const _HlsRendition({
    required this.url,
    required this.groupId,
    required this.language,
    required this.isDefault,
  });
}

class _SegmentJob {
  final String url;
  final String localName;
  final String? rangeHeader;
  final int? expectedBytes;

  const _SegmentJob({
    required this.url,
    required this.localName,
    this.rangeHeader,
    this.expectedBytes,
  });
}

class _StagedPlaylist {
  final List<String> lines;
  final List<_SegmentJob> segments;

  /// Local file name of the `#EXT-X-MAP` init segment, when the playlist uses
  /// fMP4 fragments instead of MPEG-TS.
  final String? initName;

  const _StagedPlaylist({
    required this.lines,
    required this.segments,
    this.initName,
  });
}
