import 'dart:convert';
import 'dart:io';

import 'package:cinesphere/core/services/download_engine.dart';
import 'package:cinesphere/core/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _master = '''#EXTM3U
#EXT-X-VERSION:3
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="English",LANGUAGE="en",DEFAULT=YES,AUTOSELECT=YES,URI="/audio.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,CODECS="avc1.4d401e",AUDIO="audio"
/360p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1280x720,CODECS="avc1.4d401f",AUDIO="audio",SUBTITLES="subs"
/720p.m3u8
''';

const _playlist360p = '''#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:4
#EXT-X-KEY:METHOD=AES-128,URI="/key.bin",IV=0x0123456789ABCDEF0123456789ABCDEF
#EXTINF:4.0,
/v360_0.ts
#EXTINF:4.0,
/v360_1.ts
#EXT-X-ENDLIST
''';

const _playlist720p = '''#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:4
#EXT-X-KEY:METHOD=AES-128,URI="/key.bin",IV=0x0123456789ABCDEF0123456789ABCDEF
#EXTINF:4.0,
/v720_0.ts
#EXTINF:4.0,
/v720_1.ts
#EXT-X-ENDLIST
''';

const _audio = '''#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:4
#EXT-X-KEY:METHOD=AES-128,URI="/audio_key.bin",IV=0x0123456789ABCDEF0123456789ABCDEF
#EXTINF:4.0,
/a0.ts
#EXT-X-ENDLIST
''';

const _ranged = '''#EXTM3U
#EXT-X-VERSION:4
#EXT-X-TARGETDURATION:4
#EXTINF:4.0,
#EXT-X-BYTERANGE:5@0
/range.ts
#EXTINF:4.0,
#EXT-X-BYTERANGE:5@5
/range.ts
#EXT-X-ENDLIST
''';

class _Server {
  late final HttpServer _server;

  /// Requests served per path, reset by tests that count refetches.
  final Map<String, int> hits = {};

  /// Paths that answer 500 on their next request (one-shot failure).
  final Set<String> failNext = {};

  String get base => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      try {
        final path = req.uri.path;
        hits[path] = (hits[path] ?? 0) + 1;
        if (failNext.remove(path)) {
          req.response.statusCode = HttpStatus.internalServerError;
          await req.response.close();
          return;
        }
        if (path == '/master.m3u8') return await _write(req, _master);
        if (path == '/360p.m3u8') return await _write(req, _playlist360p);
        if (path == '/720p.m3u8') return await _write(req, _playlist720p);
        if (path == '/audio.m3u8') return await _write(req, _audio);
        if (path == '/ranged.m3u8') return await _write(req, _ranged);
        if (path == '/key.bin') return await _bytes(req, List.filled(16, 7));
        if (path == '/audio_key.bin') {
          return await _bytes(req, List.filled(16, 9));
        }
        if (path == '/v360_0.ts') {
          return await _bytes(req, utf8.encode('V360-0'));
        }
        if (path == '/v360_1.ts') {
          return await _bytes(req, utf8.encode('V360-1'));
        }
        if (path == '/v720_0.ts') {
          return await _bytes(req, utf8.encode('V720-0'));
        }
        if (path == '/v720_1.ts') {
          return await _bytes(req, utf8.encode('V720-1'));
        }
        if (path == '/a0.ts') return await _bytes(req, utf8.encode('AUDIO-0'));
        if (path == '/range.ts') {
          const body = 'AAAAABBBBBCCCCC';
          final range = req.headers.value('range');
          if (range != null) {
            final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range);
            if (m != null) {
              final start = int.parse(m.group(1)!);
              final end = int.parse(m.group(2)!);
              final slice = utf8.encode(body).sublist(start, end + 1);
              req.response.statusCode = HttpStatus.partialContent;
              return await _bytes(req, slice);
            }
          }
          return await _bytes(req, utf8.encode(body));
        }
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
      } catch (_) {
        // Client aborted early during the HLS sniff; nothing to do.
      }
    });
  }

  Future<void> _write(HttpRequest req, String body) async {
    req.response.headers.contentType =
        ContentType('application', 'vnd.apple.mpegurl');
    req.response.write(body);
    await req.response.close();
  }

  Future<void> _bytes(HttpRequest req, List<int> bytes) async {
    req.response.headers.contentType = ContentType('video', 'mp2t');
    req.response.add(bytes);
    await req.response.close();
  }

  Future<void> stop() => _server.close(force: true);
}

Future<List<DownloadProgressUpdate>> _download(
  _Server server,
  String path, {
  required String dir,
  required VideoQuality quality,
}) async {
  final updates = <DownloadProgressUpdate>[];
  final saved = await DownloadEngine.downloadStreamWithProgress(
    id: 'test',
    title: 'Test Movie',
    streamUrl: '${server.base}$path',
    quality: quality,
    headers: null,
    onProgress: updates.add,
    isCancelledOrPaused: () => false,
    showNotification: false,
    overrideDir: dir,
  );
  expect(saved, '$dir/index.m3u8');
  return updates;
}

void main() {
  late _Server server;
  late Directory tempDir;

  setUp(() async {
    server = _Server();
    await server.start();
    tempDir = Directory.systemTemp.createTempSync('cinesphere_dl_test_');
  });

  tearDown(() async {
    await server.stop();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('downloads the matching variant plus its separate audio rendition',
      () async {
    final updates = await _download(server, '/master.m3u8',
        dir: tempDir.path, quality: VideoQuality.hd720);

    expect(updates, isNotEmpty);
    expect(updates.last.progress, 1.0);

    final master = File('${tempDir.path}/index.m3u8').readAsStringSync();
    expect(master, contains('URI="audio.m3u8"'));
    expect(master, contains('AUDIO="audio"'));
    expect(master, contains('video.m3u8'));
    expect(master, contains('RESOLUTION=1280x720'));
    expect(master, isNot(contains('SUBTITLES')));
    expect(master, isNot(contains('CLOSED-CAPTIONS')));

    final video = File('${tempDir.path}/video.m3u8').readAsStringSync();
    expect(video, contains('URI="v_key_0.bin"'));
    expect(video, contains('v_seg_0000.ts'));
    expect(video, contains('v_seg_0001.ts'));
    expect(video, contains('IV=0x0123456789ABCDEF0123456789ABCDEF'));

    final audio = File('${tempDir.path}/audio.m3u8').readAsStringSync();
    expect(audio, contains('URI="a_key_0.bin"'));
    expect(audio, contains('a_seg_0000.ts'));

    expect(File('${tempDir.path}/v_key_0.bin').lengthSync(), 16);
    expect(File('${tempDir.path}/a_key_0.bin').lengthSync(), 16);

    // The 720p variant was chosen, and the audio track was fetched.
    expect(File('${tempDir.path}/v_seg_0000.ts').readAsStringSync(), 'V720-0');
    expect(File('${tempDir.path}/v_seg_0001.ts').readAsStringSync(), 'V720-1');
    expect(File('${tempDir.path}/a_seg_0000.ts').readAsStringSync(), 'AUDIO-0');
  });

  test('honours HTTP byte ranges as standalone local segments', () async {
    await _download(server, '/ranged.m3u8',
        dir: tempDir.path, quality: VideoQuality.auto);

    final video = File('${tempDir.path}/video.m3u8').readAsStringSync();
    expect(video, isNot(contains('#EXT-X-BYTERANGE')));
    expect(video, contains('v_seg_0000.ts'));
    expect(video, contains('v_seg_0001.ts'));

    expect(File('${tempDir.path}/v_seg_0000.ts').readAsStringSync(), 'AAAAA');
    expect(File('${tempDir.path}/v_seg_0001.ts').readAsStringSync(), 'BBBBB');
  });

  test('retries a segment that fails once', () async {
    server.failNext.add('/v720_1.ts');

    final updates = await _download(server, '/master.m3u8',
        dir: tempDir.path, quality: VideoQuality.hd720);

    expect(updates.last.progress, 1.0);
    expect(File('${tempDir.path}/v_seg_0001.ts').readAsStringSync(), 'V720-1');
    expect(server.hits['/v720_1.ts'], 2);
  });

  test('resuming reuses staged segments instead of refetching them', () async {
    await _download(server, '/master.m3u8',
        dir: tempDir.path, quality: VideoQuality.hd720);
    server.hits.clear();

    await _download(server, '/master.m3u8',
        dir: tempDir.path, quality: VideoQuality.hd720);

    expect(server.hits['/v720_0.ts'] ?? 0, 0);
    expect(server.hits['/v720_1.ts'] ?? 0, 0);
    expect(server.hits['/a0.ts'] ?? 0, 0);
    // The playlists still have to be read to know the staged set is current.
    expect(server.hits['/720p.m3u8'], greaterThan(0));
    expect(server.hits['/audio.m3u8'], greaterThan(0));
  });

  test('a different playlist drops stale staged segments', () async {
    await _download(server, '/master.m3u8',
        dir: tempDir.path, quality: VideoQuality.hd720);
    expect(File('${tempDir.path}/v_seg_0000.ts').readAsStringSync(), 'V720-0');

    await _download(server, '/360p.m3u8',
        dir: tempDir.path, quality: VideoQuality.hd720);

    expect(File('${tempDir.path}/v_seg_0000.ts').readAsStringSync(), 'V360-0');
  });

  test('finished files mirror the in-app Movies and Series folders', () {
    const base = '/sdcard/Download/Vyro';
    expect(
      DownloadEngine.downloadPathIn(base, id: '42', title: 'Dune: Part Two'),
      '$base/Movies/Dune Part Two.mp4',
    );
    expect(
      DownloadEngine.downloadPathIn(
        base,
        id: '7',
        title: 'Carrie',
        seriesName: 'Carrie',
        season: 1,
        episode: 9,
        episodeTitle: 'The End',
      ),
      '$base/Series/Carrie/Season 1/Carrie - S01E09 - The End.mp4',
    );
  });

  test('episodes stage beside their file, movies stage out of the flat list',
      () {
    const base = '/sdcard/Download/Vyro';
    expect(
      DownloadEngine.hlsStagingDirIn(
        base,
        id: '7',
        title: 'Carrie',
        seriesName: 'Carrie',
        season: 1,
        episode: 9,
        episodeTitle: 'The End',
      ),
      '$base/Series/Carrie/Season 1/Carrie - S01E09 - The End',
    );
    expect(
      DownloadEngine.hlsStagingDirIn(base, id: '42', title: 'Heat'),
      '$base/.staging/Heat',
    );
  });
}
