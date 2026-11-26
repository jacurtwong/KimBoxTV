import 'dart:convert';
import 'dart:io';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kimbox_tv/core/app_controller.dart';
import 'package:kimbox_tv/core/category_filter.dart';
import 'package:kimbox_tv/core/config_parser.dart';
import 'package:kimbox_tv/core/db/tvbox_db.dart';
import 'package:kimbox_tv/core/hls_ad_filter.dart';
import 'package:kimbox_tv/core/models.dart';
import 'package:kimbox_tv/core/mpv_player_service.dart';
import 'package:kimbox_tv/core/paths.dart';
import 'package:kimbox_tv/ui/widgets/poster_image_provider.dart';
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

  group('CategoryFilterService', () {
    test('filters API sites but excludes csp_ spider sites', () {
      final tmp = Directory.systemTemp.createTempSync('kimboxtv_filter_test_');
      try {
        final filterFile = File(p.join(tmp.path, 'category-filter.json'));
        filterFile.writeAsStringSync(jsonEncode({
          'version': 1,
          'block': ['伦理', '电影'],
          'allow': [],
          'sites': {},
        }));
        AppPaths.categoryFilterFile = filterFile.path;
        CategoryFilterService.load(force: true);

        const apiSite = SiteInfo(
          key: 'cms1',
          name: 'CMS站',
          type: 1,
          api: 'https://api.example.com/vod',
          isDexSpider: false,
        );
        const cspSite = SiteInfo(
          key: 'csp1',
          name: 'CSP站',
          type: 3,
          api: 'csp_Demo',
          isDexSpider: true,
        );
        const cspApiOnly = SiteInfo(
          key: 'csp2',
          name: 'CSP站2',
          type: 3,
          api: 'csp_Other',
          isDexSpider: false,
        );

        expect(CategoryFilterService.isBlockedCategoryName('电影', apiSite), true);
        expect(CategoryFilterService.isBlockedCategoryName('剧集', apiSite), false);
        expect(CategoryFilterService.isBlockedCategoryName('电影', cspSite), false);
        expect(CategoryFilterService.isBlockedCategoryName('伦理', cspSite), false);
        expect(CategoryFilterService.isBlockedCategoryName('电影', cspApiOnly), false);
        expect(
          CategoryFilterService.defaultBlock,
          containsAll(['电影', '电影片', '连续剧', '综艺片', '动漫片']),
        );
      } finally {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
  });

  group('AppController playback resume helper', () {
    test('preserves playback position across decode reload and transient 0 polls', () {
      expect(
        AppController.resolveActivePlaybackPosition(
          currentPos: 245.6,
          lastGoodPos: 240.0,
        ),
        245.6,
      );
      expect(
        AppController.resolveActivePlaybackPosition(
          currentPos: 0,
          lastGoodPos: 18.4,
        ),
        18.4,
      );
      expect(
        AppController.resolveActivePlaybackPosition(
          currentPos: 0.5,
          lastGoodPos: 0,
        ),
        0,
      );
    });
  });

  group('PosterImageProvider routing and resize', () {
    test('parses @Referer/@Headers/relay and routes providers correctly', () {
      expect(posterImageProvider(''), isNull);
      expect(posterImageProvider('not-a-url'), isNull);

      final plain = posterImageProvider('https://cdn.example.com/a.jpg');
      expect(plain, isA<ResizeImage>());
      final resized = plain! as ResizeImage;
      expect(resized.width, kPosterTargetWidth);
      expect(resized.imageProvider, isA<NetworkImage>());

      final plainFallback = posterImageProvider(
        'https://cdn.example.com/a.jpg',
        forceRefererFallback: true,
      );
      expect(plainFallback, isA<SitePosterImage>());
      final fallbackSite = plainFallback! as SitePosterImage;
      expect(fallbackSite.retryWithoutReferer, true);
      expect(fallbackSite.source.headers['Referer'], 'https://cdn.example.com/');

      final douban = posterImageProvider(
        'https://img1.doubanio.com/view/photo/s_ratio_poster/public/p1.jpg',
      );
      expect(douban, isA<DoubanPosterImage>());
      expect(
        DoubanPosterImage.candidateUrls(
          'https://img1.doubanio.com/view/photo/s_ratio_poster/public/p1.jpg',
        ),
        [
          'https://img1.doubanio.com/view/photo/s_ratio_poster/public/p1.webp',
          'https://img1.doubanio.com/view/photo/s_ratio_poster/public/p1.jpg',
        ],
      );

      final withHeaders = posterImageProvider(
        'https://img.site.com/p.jpg@Referer=https://site.com/@Headers={"ua":"CustomUA"}',
      );
      expect(withHeaders, isA<SitePosterImage>());
      final siteSrc = (withHeaders! as SitePosterImage).source;
      expect(siteSrc.url, 'https://img.site.com/p.jpg');
      expect(siteSrc.headers['Referer'], 'https://site.com/');
      expect(siteSrc.headers['User-Agent'], 'CustomUA');

      final relay = PosterSource.parse(
        'https://proxy.site.com/img.php?url=https%3A%2F%2Fimg2.doubanio.com%2Fp2.jpg',
      );
      expect(relay.fallbackUrl, 'https://img2.doubanio.com/p2.jpg');

      final scaled = scalePosterTargetSize(1024, 1536, 512);
      expect(scaled.width, 512);
      expect(scaled.height, 768);
      final unscaled = scalePosterTargetSize(300, 450, 512);
      expect(unscaled.width, 300);
      expect(unscaled.height, 450);
    });
  });

  group('CategoryScanner hashed baseline & negative cache', () {
    test('seeds empty categories by SHA-256 API hash without plaintext URLs',
        () async {
      final baselineRaw = File('assets/category-baseline.json').readAsStringSync();
      expect(baselineRaw.contains('http://'), false);
      expect(baselineRaw.contains('https://'), false);
      final parsedBaseline = jsonDecode(baselineRaw) as Map<String, dynamic>;
      expect(parsedBaseline['version'], 2);
      expect((parsedBaseline['hashes'] as Map).length, 20);

      final tmp = Directory.systemTemp.createTempSync('kimbox_cat_scan_test_');
      try {
        AppPaths.appRoot = tmp.path;
        AppPaths.cacheDir = p.join(tmp.path, 'cache');
        Directory(AppPaths.cacheDir).createSync(recursive: true);

        const apiA = 'https://Vod.Example.com/api.php/provide/vod///';
        final hashA = CategoryScanner.hashApi('https://vod.example.com/api.php/provide/vod');
        expect(CategoryScanner.hashApi(apiA), hashA);

        File(p.join(tmp.path, 'category-baseline.json')).writeAsStringSync(
          jsonEncode({
            'version': 2,
            'at': 12345,
            'hashes': {
              hashA: {
                'total': 10,
                'empty': ['1', '2'],
                'alive': ['6'],
              },
            },
          }),
        );
        CategoryScanner.resetBaselineCacheForTesting();

        const s1 = SiteInfo(
          key: 'site_hashed',
          name: '测试站',
          type: 1,
          api: apiA,
        );
        const sFail = SiteInfo(
          key: 'site_failed',
          name: '失败站',
          type: 1,
          api: 'https://down.example.com/api',
        );

        await CategoryScanner.seedFromBaseline(99, const [s1, sFail]);
        final emptyRec = CategoryScanner.getSiteEmptyCache(99, 'site_hashed');
        expect(emptyRec.fresh, true);
        expect(emptyRec.empty, ['1', '2']);

        // Negative cache entry should not be treated as valid or counted in summary
        final catCache = CategoryScanner.loadCatCache(99);
        (catCache['sites'] as Map)['site_failed'] = {
          'at': DateTime.now().millisecondsSinceEpoch,
          'failed': true,
          'fp': sFail.fingerprint,
        };
        CategoryScanner.saveCatCache(99, catCache);

        expect(CategoryScanner.getSiteEmptyCache(99, 'site_failed').fresh, false);
        final sum = CategoryScanner.summary(99, const [s1, sFail]);
        expect(sum.cms, 2);
        expect(sum.cached, 1);
      } finally {
        CategoryScanner.resetBaselineCacheForTesting();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
  });
}
