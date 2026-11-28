import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kimbox_tv/core/app_controller.dart';
import 'package:kimbox_tv/core/cache_cleaner.dart';
import 'package:kimbox_tv/core/category_filter.dart';
import 'package:kimbox_tv/core/config_parser.dart';
import 'package:kimbox_tv/core/db/tvbox_db.dart';
import 'package:kimbox_tv/core/hls_ad_filter.dart';
import 'package:kimbox_tv/core/local_http_server.dart';
import 'package:kimbox_tv/core/models.dart';
import 'package:kimbox_tv/core/mpv_player_service.dart';
import 'package:kimbox_tv/core/paths.dart';
import 'package:kimbox_tv/core/settings_store.dart';
import 'package:kimbox_tv/ui/player_view.dart';
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

    test('handles leading empty disc, alternating tail ad, and short edge main chunks', () {
      // Mirrors TV-神马云 / TV-非凡 / TV-爱奇艺 / TV-暴风 real playlists
      final shenma = StringBuffer()
        ..writeln('#EXTM3U')
        ..writeln('#EXT-X-PLAYLIST-TYPE:VOD')
        ..writeln('#EXT-X-DISCONTINUITY') // leading empty chunk
        ..write(segBlock(124, 4.0, 'm1')) // 496s
        ..writeln('#EXT-X-DISCONTINUITY')
        ..write(segBlock(4, 4.1, 'ad_a')) // 16.4s (4:16)
        ..writeln('#EXT-X-DISCONTINUITY')
        ..write(segBlock(230, 4.0, 'm2')) // 920s
        ..writeln('#EXT-X-DISCONTINUITY')
        ..write(segBlock(5, 3.54, 'ad_b')) // 17.7s alternating tail ad
        ..writeln('#EXT-X-ENDLIST');
      final a1 = HlsAdFilter.analyzeAdRanges(shenma.toString());
      expect(a1.chunks.where((c) => c.ad).length, 2);
      expect(a1.chunks[2].ad, true);
      expect(a1.chunks[4].ad, true);
      final c1 = HlsAdFilter.buildCutPlaylist(shenma.toString(), a1);
      expect(c1.cuts.length, 2);
      expect(c1.text.startsWith('#EXTM3U\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXTINF:'), true);

      // Mirrors TV-爱奇艺 short intro chunk (<180s) with distinct /stream/ ad path
      final iqiyi = StringBuffer()
        ..writeln('#EXTM3U')
        ..write(segBlock(25, 5.0, 'videos/main_a')) // 125s < 180s
        ..writeln('#EXT-X-DISCONTINUITY')
        ..write(segBlock(5, 3.5, 'stream/ad_mid')) // 17.5s
        ..writeln('#EXT-X-DISCONTINUITY')
        ..write(segBlock(52, 5.0, 'videos/main_b')) // 260s
        ..writeln('#EXT-X-ENDLIST');
      final a2 = HlsAdFilter.analyzeAdRanges(iqiyi.toString());
      expect(a2.ranges.length, 1);
      expect(a2.chunks[1].ad, true);
    });

    test('supports >6 mid-roll ads on long shows and repeated URIs on multi-chunk streams', () {
      // Mirrors TV-魔都 8+ ads and TV-ikun multi-discontinuity repeated ad URIs
      final modu = StringBuffer()..writeln('#EXTM3U');
      for (var i = 0; i < 8; i++) {
        modu.write(segBlock(100, 3.0, 'main_$i'));
        modu.writeln('#EXT-X-DISCONTINUITY');
        modu.writeln('#EXT-X-KEY:METHOD=NONE');
        modu.write(segBlock(6, 2.94, 'ad_shared/seg'));
        if (i < 7) modu.writeln('#EXT-X-DISCONTINUITY');
      }
      modu.writeln('#EXT-X-ENDLIST');
      final a1 = HlsAdFilter.analyzeAdRanges(modu.toString());
      expect(a1.rejected, false);
      expect(a1.chunks.where((c) => c.ad).length, 8);

      // Multi-discontinuity clean stream must NOT false-positive
      final cleanMulti = StringBuffer()..writeln('#EXTM3U');
      for (var i = 0; i < 50; i++) {
        cleanMulti.write(segBlock(5 + (i % 4), 4.0, 'seg_${i}_x'));
        if (i < 49) cleanMulti.writeln('#EXT-X-DISCONTINUITY');
      }
      cleanMulti.writeln('#EXT-X-ENDLIST');
      final a2 = HlsAdFilter.analyzeAdRanges(cleanMulti.toString());
      expect(a2.ranges, isEmpty);

      // Repeated identical ad URIs inside multi-discontinuity stream + trailing empty disc
      final ikunMulti = StringBuffer()..writeln('#EXTM3U');
      for (var i = 0; i < 12; i++) {
        if (i == 2 || i == 7 || i == 11) {
          ikunMulti.write(segBlock(6, 2.94, '20261118/ad/seg'));
        } else {
          ikunMulti.write(segBlock(12, 3.2, '20240430/main/m_${i}_'));
        }
        ikunMulti.writeln('#EXT-X-DISCONTINUITY');
      }
      ikunMulti.writeln('#EXT-X-ENDLIST');
      final a3 = HlsAdFilter.analyzeAdRanges(ikunMulti.toString());
      expect(a3.chunks[2].ad, true);
      expect(a3.chunks[7].ad, true);
      expect(a3.chunks[11].ad, true);
      final c3 = HlsAdFilter.buildCutPlaylist(ikunMulti.toString(), a3);
      expect(c3.text.contains('#EXT-X-DISCONTINUITY\n#EXT-X-ENDLIST'), false);
    });

    test('LocalHttpServer.sanitizeHeaders preserves custom spider auth headers', () {
      final cleaned = LocalHttpServer.sanitizeHeaders({
        'User-Agent': 'Mozi',
        'Badci': 'e33f120e719bb723bca70658af09ea2b',
        'Host': 'evil.example.com',
        'Referer': 'https://site.example/\r\nX-Inject: 1',
      });
      expect(cleaned['User-Agent'], 'Mozi');
      expect(cleaned['Badci'], 'e33f120e719bb723bca70658af09ea2b');
      expect(cleaned.containsKey('Host'), false);
      expect(cleaned['Referer']?.contains('\n'), false);
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
      expect((parsedBaseline['hashes'] as Map).length, 21);

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

  group('LocalSettingsStore', () {
    test('persists settings in data dir and cleans legacy nested support dir',
        () async {
      final tmp = Directory.systemTemp.createTempSync('kimbox_settings_test_');
      try {
        final appDataRoot = p.join(tmp.path, 'roaming');
        final legacyDir = Directory(p.join(appDataRoot, 'KimBoxTV', 'KimBoxTV'))
          ..createSync(recursive: true);
        File(p.join(legacyDir.path, 'shared_preferences.json')).writeAsStringSync(
          jsonEncode({'flutter.tvbox_hwdec': 'hw', 'flutter.tvbox_scope': 'site'}),
        );

        final settingsPath = p.join(tmp.path, 'data', 'settings.json');
        final store = LocalSettingsStore();
        store.load(
          customFilePath: settingsPath,
          legacyAppDataRoot: appDataRoot,
        );
        expect(store.getString('tvbox_hwdec'), 'hw');
        expect(store.getString('tvbox_scope'), 'site');
        expect(legacyDir.existsSync(), false);

        await store.setString('tvbox_admode', 'skip');
        final reloaded = LocalSettingsStore()
          ..load(customFilePath: settingsPath, legacyAppDataRoot: appDataRoot);
        expect(reloaded.getString('tvbox_admode'), 'skip');
        expect(reloaded.getString('tvbox_hwdec'), 'hw');
      } finally {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
  });

  group('Regression fixes for filter, HLS proxy, headers, and CacheCleaner', () {
    test('respects explicit empty block array in category-filter.json', () {
      final tmp = Directory.systemTemp.createTempSync('kimbox_empty_block_');
      try {
        final filterFile = File(p.join(tmp.path, 'category-filter.json'));
        filterFile.writeAsStringSync(jsonEncode({
          'version': 1,
          'block': [],
          'allow': [],
          'sites': {},
        }));
        AppPaths.categoryFilterFile = filterFile.path;
        final cfg = CategoryFilterService.load(force: true);
        expect(cfg.block, isEmpty);
        const apiSite = SiteInfo(
          key: 'cms1',
          name: 'CMS站',
          type: 1,
          api: 'https://api.example.com/vod',
        );
        expect(CategoryFilterService.isBlockedCategoryName('电影', apiSite), false);
      } finally {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('preserves data: key URIs in proxyUris and deduplicates headers', () {
      const playlist = '#EXTM3U\n'
          '#EXT-X-KEY:METHOD=AES-128,URI="data:text/plain;base64,AAAA"\n'
          'https://cdn.example.com/seg1.ts\n';
      final proxied = HlsAdFilter.proxyUris(playlist, const {}, 8899);
      expect(proxied.contains('URI="data:text/plain;base64,AAAA"'), true);
      expect(proxied.contains('http://127.0.0.1:8899/api/seg?u='), true);

      final hdr = LocalHttpServer.sanitizeHeaders({'user-agent': 'CustomUA/1.0'});
      expect(hdr.keys.where((k) => k.toLowerCase() == 'user-agent').length, 1);
      expect(hdr['user-agent'], 'CustomUA/1.0');
    });

    test('CacheCleaner scans and cleans custom app cache directory accurately',
        () {
      final tmp = Directory.systemTemp.createTempSync('kimbox_cache_clean_');
      try {
        final cacheDir = Directory(p.join(tmp.path, 'cache'))
          ..createSync(recursive: true);
        File(p.join(cacheDir.path, 'config_1.json'))
            .writeAsBytesSync(List<int>.filled(2048, 65));
        final info = CacheCleaner.getCacheInfo(
          customCacheDir: cacheDir.path,
          customAppData: tmp.path,
        );
        expect(info.sizeBytes, 2048);
        expect(info.path, cacheDir.path);
        final res = CacheCleaner.cleanCache(
          customCacheDir: cacheDir.path,
          customAppData: tmp.path,
        );
        expect(res.currentMB, 0.0);
        expect(File(p.join(cacheDir.path, 'config_1.json')).existsSync(), false);
      } finally {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('MpvPlayerService native ASS overlay escaping and backend labels', () {
      expect(
        const MpvMetaSnapshot(renderBackend: 'native_d3d11').renderBackendLabel,
        '原生直出 (vo=gpu / D3D11)',
      );
      expect(
        MpvPlayerService.escapeAssText(r'标题 {1}\n第二行'.replaceAll(r'\n', '\n')),
        r'标题 \{1\}\N第二行',
      );
      final osd = MpvPlayerService.buildNativeOsdAss(
        topLeft: 'Film - E01',
        topRight: '12:00:00',
        bottomLeft: '01:00 / 40:00',
        bottomRight: '2.0 MB/s',
      );
      expect(osd.contains(r'{\an7'), true);
      expect(osd.contains(r'{\an9'), true);
      expect(osd.contains(r'{\an1'), true);
      expect(osd.contains(r'{\an3'), true);
      expect(MpvPlayerService.buildNativeToastAss('已跳过片头').contains(r'{\an5'), true);
      expect(MpvPlayerService.buildNativeToastAss('   '), '');
    });

    testWidgets(
        'PlayerView dispose clears native callbacks, hides viewport, and avoids ref errors',
        (tester) async {
      tester.view.physicalSize = const Size(1024, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const nativeChannel = MethodChannel('kimbox/native_mpv');
      final viewportCalls = <Map<dynamic, dynamic>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, (call) async {
        if (call.method == 'setViewport' && call.arguments is Map) {
          viewportCalls.add(call.arguments as Map<dynamic, dynamic>);
        }
        return true;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(nativeChannel, null);
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ctrl = container.read(appControllerProvider.notifier);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: PlayerView()),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('主页'), findsOneWidget);
      expect(find.byIcon(Icons.bug_report_outlined), findsOneWidget);
      expect(ctrl.mpvService.onNativeTap, isNotNull);
      expect(ctrl.mpvService.onNativeDoubleTap, isNotNull);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: SizedBox.shrink()),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      expect(tester.takeException(), isNull);
      expect(ctrl.mpvService.onNativeTap, isNull);
      expect(ctrl.mpvService.onNativeDoubleTap, isNull);
      expect(ctrl.mpvService.onNativeMouseMove, isNull);
      expect(viewportCalls.any((m) => m['visible'] == false), isTrue);
    });
  });
}
