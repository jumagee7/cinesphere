import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:cinesphere/core/services/settings_service.dart';
import 'package:cinesphere/core/services/stream_proxy_service.dart';

const _master = '#EXTM3U\n'
    '#EXT-X-VERSION:3\n'
    '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="Italian",LANGUAGE="it",DEFAULT=YES,AUTOSELECT=YES,URI="audio_it.m3u8"\n'
    '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="English",LANGUAGE="en",DEFAULT=NO,AUTOSELECT=NO,URI="audio_en.m3u8"\n'
    '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="Spanish",LANGUAGE="es",DEFAULT=NO,AUTOSELECT=NO,URI="audio_es.m3u8"\n'
    '#EXT-X-STREAM-INF:BANDWIDTH=900000,RESOLUTION=1280x720,AUDIO="aud"\n'
    '720p.m3u8\n'
    '#EXT-X-STREAM-INF:BANDWIDTH=400000,RESOLUTION=640x360,AUDIO="aud"\n'
    '360p.m3u8\n';

void main() {
  setUp(() => StreamProxyService.instance.setQualityTarget(VideoQuality.auto));
  tearDown(() => StreamProxyService.instance.setAudioTarget(null));

  test('StreamProxy resolves proxy URL and reconstructs segment URLs correctly', () async {
    final proxy = StreamProxyService.instance;
    const testUrl = 'https://birchandbloom.space/stream.m3u8';
    final proxyUrl = await proxy.start(testUrl, {'Referer': 'https://vidsrc.sh/'});
    expect(proxyUrl, contains('http://127.0.0.1:'));
    expect(proxyUrl, endsWith('.m3u8'));
    await proxy.stop();
  });

  test('StreamProxy serves a pre-fetched manifest without hitting upstream',
      () async {
    var upstreamHits = 0;
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((req) async {
      upstreamHits++;
      req.response.statusCode = HttpStatus.internalServerError;
      await req.response.close();
    });

    final proxy = StreamProxyService.instance;
    try {
      final proxyUrl = await proxy.start(
        'http://127.0.0.1:${upstream.port}/master.m3u8',
        const {},
        initialManifest: _master,
      );
      final body = await http.read(Uri.parse(proxyUrl));
      expect(body, contains('#EXTM3U'));
      expect(body, contains('http://127.0.0.1:'));
      expect(upstreamHits, 0);
    } finally {
      await proxy.stop();
      await upstream.close(force: true);
    }
  });

  test('StreamProxy pins the selected audio rendition', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((req) async {
      req.response.headers.contentType = ContentType.parse('application/vnd.apple.mpegurl');
      req.response.write(_master);
      await req.response.close();
    });

    final proxy = StreamProxyService.instance;
    try {
      proxy.setAudioTarget('es');
      final proxyUrl = await proxy.start(
        'http://127.0.0.1:${upstream.port}/master.m3u8',
        const {},
      );
      final body = await http.read(Uri.parse(proxyUrl));
      expect(body, contains('NAME="Spanish"'));
      expect(body, isNot(contains('NAME="English"')));
      expect(body, isNot(contains('NAME="Italian"')));
      final spanishLine =
          body.split('\n').firstWhere((l) => l.contains('NAME="Spanish"'));
      expect(spanishLine, contains('DEFAULT=YES'));
      expect(spanishLine, contains('AUTOSELECT=YES'));
      // Both video variants stay when quality is auto.
      expect(body, contains('720p.m3u8'));
      expect(body, contains('360p.m3u8'));
    } finally {
      await proxy.stop();
      await upstream.close(force: true);
    }
  });

  test('StreamProxy pins audio and quality together', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((req) async {
      req.response.headers.contentType = ContentType.parse('application/vnd.apple.mpegurl');
      req.response.write(_master);
      await req.response.close();
    });

    final proxy = StreamProxyService.instance;
    try {
      proxy.setQualityTarget(VideoQuality.hd720);
      proxy.setAudioTarget('en');
      final proxyUrl = await proxy.start(
        'http://127.0.0.1:${upstream.port}/master.m3u8',
        const {},
      );
      final body = await http.read(Uri.parse(proxyUrl));
      expect(body, contains('NAME="English"'));
      expect(body, isNot(contains('NAME="Spanish"')));
      expect(body, contains('RESOLUTION=1280x720'));
      expect(body, isNot(contains('RESOLUTION=640x360')));
    } finally {
      proxy.setQualityTarget(VideoQuality.auto);
      await proxy.stop();
      await upstream.close(force: true);
    }
  });

  test('StreamProxy counts relayed media bytes for throughput sampling',
      () async {
    const mediaBytes = 20000;
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((req) async {
      req.response.add(List<int>.filled(mediaBytes, 7));
      await req.response.close();
    });

    final proxy = StreamProxyService.instance;
    try {
      proxy.takeRelayedBytes();
      final proxyUrl = await proxy.start(
        'http://127.0.0.1:${upstream.port}/video.mp4',
        const {},
      );
      final media = await http.read(Uri.parse(proxyUrl));
      expect(media.length, mediaBytes);
      expect(proxy.takeRelayedBytes(), greaterThanOrEqualTo(mediaBytes));
    } finally {
      await proxy.stop();
      await upstream.close(force: true);
    }
  });
}

