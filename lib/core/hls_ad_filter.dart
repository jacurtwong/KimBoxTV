import 'dart:convert';
import 'models.dart';

class HlsAdFilter {
  HlsAdFilter._();

  static List<List<String>> splitByDiscontinuity(String text) {
    final lines = text.split(RegExp(r'\r?\n'));
    final chunks = <List<String>>[];
    var cur = <String>[];
    for (final ln in lines) {
      if (RegExp(r'^#EXT-X-DISCONTINUITY\b', caseSensitive: false)
          .hasMatch(ln.trim())) {
        chunks.add(cur);
        cur = <String>[];
      } else {
        cur.add(ln);
      }
    }
    chunks.add(cur);
    return chunks;
  }

  static ({double dur, int segs}) chunkInfo(List<String> lines) {
    var dur = 0.0;
    var segs = 0;
    for (final ln in lines) {
      final s = ln.trim();
      if (s.startsWith('#EXTINF')) {
        final colon = s.indexOf(':');
        if (colon >= 0) {
          final rest = s.substring(colon + 1);
          final comma = rest.indexOf(',');
          final numStr = comma >= 0 ? rest.substring(0, comma) : rest;
          dur += double.tryParse(numStr.trim()) ?? 0.0;
        }
        segs++;
      }
    }
    return (dur: dur, segs: segs);
  }

  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  static AdAnalysisResult analyzeAdRanges(String text) {
    final chunks = splitByDiscontinuity(text);
    final infos = chunks.map(chunkInfo).toList();
    final totalDur = infos.fold<double>(0.0, (a, b) => a + b.dur);

    List<AdChunkInfo> chunkListOf(Set<int>? adSet) {
      return List.generate(
        infos.length,
        (i) => AdChunkInfo(
          d: _round2(infos[i].dur),
          n: infos[i].segs,
          ad: adSet != null && adSet.contains(i),
        ),
      );
    }

    if (chunks.length < 3) {
      final durR = totalDur.roundToDouble();
      return AdAnalysisResult(
        ranges: const [],
        chunks: chunkListOf(null),
        edgeAds: 0,
        totalChunks: chunks.length,
        duration: durR,
        mainDuration: durR,
      );
    }

    final picked = <({int idx, double dur, int segs})>[];
    for (var i = 1; i < chunks.length - 1; i++) {
      final info = infos[i];
      if (!(info.segs >= 1 &&
          info.segs <= 30 &&
          info.dur >= 5 &&
          info.dur <= 90)) {
        continue;
      }
      if (picked.any((p) => p.idx == i - 1)) continue;
      final need = info.dur * 3 > 180 ? info.dur * 3 : 180.0;
      final left = infos[i - 1];
      final right = infos[i + 1];
      if (!(left.segs > 0 && left.dur >= need)) continue;
      if (!(right.segs > 0 && right.dur >= need)) continue;
      picked.add((idx: i, dur: info.dur, segs: info.segs));
    }

    final adDur = picked.fold<double>(0.0, (a, b) => a + b.dur);
    if (picked.length > 6 || adDur > totalDur * 0.05) {
      return AdAnalysisResult(
        ranges: const [],
        chunks: chunkListOf(null),
        edgeAds: 0,
        totalChunks: chunks.length,
        duration: totalDur.roundToDouble(),
        mainDuration: totalDur.roundToDouble(),
        rejected: true,
      );
    }

    final adIndices = picked.map((p) => p.idx).toSet();
    var dramaAcc = 0.0;
    final chunkPtsStarts = List<double>.filled(chunks.length, 0.0);
    for (var i = 0; i < chunks.length; i++) {
      chunkPtsStarts[i] = dramaAcc;
      if (!adIndices.contains(i)) {
        dramaAcc += infos[i].dur;
      }
    }

    final ranges = picked.map((p) {
      final start = chunkPtsStarts[p.idx];
      final end = start + p.dur;
      final target = end + 0.4;
      return AdRange(
        start: _round2(start),
        end: _round2(end),
        target: _round2(target),
      );
    }).toList();

    String sig(({double dur, int segs}) x) => '${x.segs}:${x.dur.round()}';
    final adSigs = picked.map((p) => sig(infos[p.idx])).toSet();
    bool isAdShape(({double dur, int segs}) x) =>
        x.segs >= 1 && x.segs <= 30 && x.dur >= 5 && x.dur <= 90;

    final edgeRanges = <AdRange>[];
    final adIdxAll = Set<int>.from(adIndices);

    if (chunks.length >= 2 && adSigs.isNotEmpty) {
      if (isAdShape(infos[0]) &&
          adSigs.contains(sig(infos[0])) &&
          infos[1].dur >= (infos[0].dur * 3 > 180 ? infos[0].dur * 3 : 180)) {
        edgeRanges.add(AdRange(
          start: 0,
          end: _round2(infos[0].dur),
          target: _round2(infos[0].dur + 0.4),
        ));
        adIdxAll.add(0);
      }
      final lastIdx = chunks.length - 1;
      if (isAdShape(infos[lastIdx]) &&
          adSigs.contains(sig(infos[lastIdx])) &&
          infos[lastIdx - 1].dur >=
              (infos[lastIdx].dur * 3 > 180
                  ? infos[lastIdx].dur * 3
                  : 180)) {
        final start = chunkPtsStarts[lastIdx];
        edgeRanges.add(AdRange(
          start: _round2(start),
          end: _round2(start + infos[lastIdx].dur),
          target: _round2(start + infos[lastIdx].dur + 0.4),
          isTail: true,
        ));
        adIdxAll.add(lastIdx);
      }
    }

    final allRanges = [...ranges, ...edgeRanges]
      ..sort((a, b) => a.start.compareTo(b.start));

    return AdAnalysisResult(
      ranges: allRanges,
      chunks: chunkListOf(adIdxAll),
      edgeAds: edgeRanges.length,
      totalChunks: chunks.length,
      duration: totalDur.roundToDouble(),
      mainDuration: dramaAcc.roundToDouble(),
    );
  }

  static String absolutizePlaylist(String text, String baseUrl) {
    final base = Uri.tryParse(baseUrl);
    String toAbs(String u) {
      if (u.isEmpty) return u;
      if (RegExp(r'^(https?:)?//', caseSensitive: false).hasMatch(u) ||
          RegExp(r'^data:', caseSensitive: false).hasMatch(u)) {
        return u;
      }
      if (base == null) return u;
      try {
        return base.resolve(u).toString();
      } catch (_) {
        return u;
      }
    }

    return text.split(RegExp(r'\r?\n')).map((line) {
      final s = line.trim();
      if (s.isEmpty) return '';
      if (s.startsWith('#')) {
        return line.replaceAllMapped(
          RegExp(r'URI="([^"]*)"'),
          (m) => 'URI="${toAbs(m.group(1) ?? '')}"',
        );
      }
      return toAbs(s);
    }).join('\n');
  }

  static ({String text, List<AdCutRange> cuts, double removed, int kept})
      buildCutPlaylist(String text, AdAnalysisResult analysis) {
    final lines = text.split(RegExp(r'\r?\n'));
    final blocks = <({int a, int b})>[];
    var startLine = 0;
    for (var i = 0; i < lines.length; i++) {
      if (RegExp(r'^#EXT-X-DISCONTINUITY\b', caseSensitive: false)
          .hasMatch(lines[i].trim())) {
        blocks.add((a: startLine, b: i));
        startLine = i + 1;
      }
    }
    blocks.add((a: startLine, b: lines.length));

    bool safeToCut(AdChunkInfo? c) =>
        c != null && c.ad && c.d >= 5 && c.d <= 120 && c.n <= 40;

    final hadEndList = lines.any(
      (l) => RegExp(r'^#EXT-X-ENDLIST', caseSensitive: false)
          .hasMatch(l.trim()),
    );

    final out = <String>[];
    final cuts = <AdCutRange>[];
    var acc = 0.0;
    var removed = 0.0;
    var kept = 0;

    for (var idx = 0; idx < blocks.length; idx++) {
      final blk = blocks[idx];
      var dur = 0.0;
      for (var i = blk.a; i < blk.b; i++) {
        final s = lines[i].trim();
        if (s.startsWith('#EXTINF')) {
          final colon = s.indexOf(':');
          if (colon >= 0) {
            final rest = s.substring(colon + 1);
            final comma = rest.indexOf(',');
            final numStr = comma >= 0 ? rest.substring(0, comma) : rest;
            dur += double.tryParse(numStr.trim()) ?? 0.0;
          }
        }
      }
      final start = acc;
      acc += dur;

      final chunk = idx < analysis.chunks.length ? analysis.chunks[idx] : null;
      if (safeToCut(chunk)) {
        cuts.add(AdCutRange(_round2(start), _round2(acc)));
        removed += dur;
        if (idx == 0) {
          for (var i = blk.a; i < blk.b; i++) {
            if (lines[i].trim().startsWith('#EXTINF')) break;
            out.add(lines[i]);
          }
        }
        continue;
      }

      if (kept > 0) out.add('#EXT-X-DISCONTINUITY');
      for (var i = blk.a; i < blk.b; i++) {
        if (!RegExp(r'^#EXT-X-ENDLIST', caseSensitive: false)
            .hasMatch(lines[i].trim())) {
          out.add(lines[i]);
        }
      }
      kept++;
    }

    if (hadEndList) out.add('#EXT-X-ENDLIST');

    return (
      text: '${out.join('\n')}\n',
      cuts: cuts,
      removed: _round2(removed),
      kept: kept,
    );
  }

  static String proxyUris(
    String text,
    Map<String, String> headers,
    int port,
  ) {
    final hParam = headers.isNotEmpty
        ? '&h=${Uri.encodeQueryComponent(jsonEncode(headers))}'
        : '';
    String enc(String u) =>
        'http://127.0.0.1:$port/api/seg?u=${Uri.encodeQueryComponent(u)}$hParam';

    return text.split(RegExp(r'\r?\n')).map((line) {
      final s = line.trim();
      if (s.isEmpty) return line;
      if (s.startsWith('#')) {
        return line.replaceAllMapped(
          RegExp(r'URI="([^"]+)"'),
          (m) => 'URI="${enc(m.group(1) ?? '')}"',
        );
      }
      return RegExp(r'^https?://', caseSensitive: false).hasMatch(s)
          ? enc(s)
          : line;
    }).join('\n');
  }
}
