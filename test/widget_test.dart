import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kimbox_tv/core/config_parser.dart';
import 'package:kimbox_tv/core/db/tvbox_db.dart';
import 'package:kimbox_tv/core/hls_ad_filter.dart';
import 'package:kimbox_tv/core/mpv_player_service.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ConfigParser', () {
    test('parses JSON with // and /* */ comments without breaking https://', () {
      const raw = '''
      // leading comment
      {
        "spider": "https://example.com/spider.jar",
        /* block comment */
        "sites": [
          {"key": "s1", "name": "站1", "type": 1, "api": "https://a.com/vod"},
          {"key": "s1", "name": "站1重名", "type": 3, "api": "csp_Demo"}
        ]
      }
      ''';
      final parsed = ConfigParser.parseText(raw);
      expect(parsed.spider, 'https://example.com/spider.jar');
      expect(parsed.sites.length, 2);
      expect(parsed.sites[0].key, 's1');
      expect(parsed.sites[1].key, 's1_2');
      expect(parsed.sites[1].isDexSpider, true);
    });

    test('parses ** prefixed base64 config', () {
      final json = jsonEncode({
        'sites': [
          {'key': 'k1', 'name': 'Test', 'type': 1, 'api': 'https://b.com/vod'},
        ],
      });
      final encoded = 'abc**${base64.encode(utf8.encode(json))}';
      final parsed = ConfigParser.parseText(encoded);
      expect(parsed.sites.length, 1);
      expect(parsed.sites.first.name, 'Test');
    });
  });

  group('HlsAdFilter', () {
    String segBlock(int count, double durEach, String prefix) {
      final buf = StringBuffer();
      for (var i = 0; i < count; i++) {
        buf.writeln('#EXTINF:$durEach,');
        buf.writeln('https://cdn.example.com/$prefix-$i.ts');
      }
      return buf.toString();
    }

    test('detects middle, head, and tail ads and builds cut playlist', () {
      final m3u8 = StringBuffer()
        ..writeln('#EXTM3U')
        ..writeln('#EXT-X-VERSION:3')
        ..writeln('#EXT-X-TARGETDURATION:10')
        ..write(segBlock(3, 5.0, 'head_ad'))
        ..writeln('#EXT-X-DISCONTINUITY')
        ..write(segBlock(40, 6.0, 'main1')) // 240s
        ..writeln('#EXT-X-DISCONTINUITY')
        ..write(segBlock(3, 5.0, 'mid_ad')) // 15s
        ..writeln('#EXT-X-DISCONTINUITY')
        ..write(segBlock(40, 6.0, 'main2')) // 240s
        ..writeln('#EXT-X-DISCONTINUITY')
        ..write(segBlock(3, 5.0, 'tail_ad')) // 15s
        ..writeln('#EXT-X-ENDLIST');

      final raw = m3u8.toString();
      final analysis = HlsAdFilter.analyzeAdRanges(raw);
      expect(analysis.ranges.length, 3);
      expect(analysis.ranges[0].start, 0);
      expect(analysis.ranges[0].end, 15);
      expect(analysis.ranges[1].start, 255);
      expect(analysis.ranges[1].end, 270);
      expect(analysis.ranges[2].isTail, true);

      final cut = HlsAdFilter.buildCutPlaylist(raw, analysis);
      expect(cut.cuts.length, 3);
      expect(cut.removed, 45);
      expect(cut.text.contains('#EXTM3U'), true);
      expect(cut.text.contains('#EXT-X-ENDLIST'), true);
      expect(cut.text.contains('mid_ad'), false);
      expect(cut.text.contains('head_ad'), false);
      expect(cut.text.contains('tail_ad'), false);
      expect(cut.text.contains('main1-0.ts'), true);
      expect(cut.text.contains('main2-0.ts'), true);
    });
  });

  group('TvboxDb', () {
    test('CRUD and VACUUM INTO backup & restore', () {
      final tmp = Directory.systemTemp.createTempSync('kimbox_test_');
      try {
        final dbPath = p.join(tmp.path, 'tvbox.db');
        final bakDir = p.join(tmp.path, 'backups');
        TvboxDb.open(dbPath);

        final cfg = TvboxDb.addConfig('https://example.com/a.json', '主源');
        expect(cfg.name, '主源');
        TvboxDb.setDefaultSite(cfg.id, 'site_a');
        expect(TvboxDb.getConfig(cfg.id)?.defaultSite, 'site_a');

        TvboxDb.saveHistory(
          siteKey: 'site_a',
          vodId: '100',
          vodName: '测试剧',
          position: 123.5,
          duration: 2400,
        );
        expect(TvboxDb.getHistory('site_a', '100')?.position, 123.5);

        expect(
          TvboxDb.toggleFavorite(
            siteKey: 'site_a',
            vodId: '100',
            vodName: '测试剧',
          ),
          true,
        );
        expect(TvboxDb.hasFavorite('site_a', '100'), true);

        final bak = TvboxDb.backup('manual', bakDir);
        expect(bak.file, isNotNull);

        TvboxDb.clearFavorites();
        expect(TvboxDb.hasFavorite('site_a', '100'), false);

        final restored = TvboxDb.restoreBackup(
          bak.file!,
          backupsDir: bakDir,
          customDbPath: dbPath,
        );
        expect(restored['favorite'], 1);
        expect(TvboxDb.hasFavorite('site_a', '100'), true);

        TvboxDb.close();
      } finally {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
  });

  group('MpvPlayerService render resolution clamp', () {
    test('returns null in auto mode or when source fits cap', () {
      expect(
        MpvPlayerService.computeClampedRenderSize(3840, 2160, 'auto'),
        isNull,
      );
      expect(
        MpvPlayerService.computeClampedRenderSize(1280, 720, '1080'),
        isNull,
      );
      expect(
        MpvPlayerService.computeClampedRenderSize(1280, 720, '720'),
        isNull,
      );
    });

    test('downscales landscape, ultrawide, and portrait preserving aspect', () {
      final uhdTo720 =
          MpvPlayerService.computeClampedRenderSize(3840, 2160, '720');
      expect(uhdTo720, (width: 1280, height: 720));

      final ultrawide =
          MpvPlayerService.computeClampedRenderSize(2560, 1080, '720');
      expect(ultrawide, (width: 1280, height: 540));

      final portrait =
          MpvPlayerService.computeClampedRenderSize(1080, 1920, '720');
      expect(portrait, (width: 720, height: 1280));

      final uhdTo1080 =
          MpvPlayerService.computeClampedRenderSize(3840, 2160, '1080');
      expect(uhdTo1080, (width: 1920, height: 1080));
    });
  });
}
