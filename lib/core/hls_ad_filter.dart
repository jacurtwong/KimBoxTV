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

  static String _dirOf(String uri) {
    final s = uri.trim();
    if (!s.contains('/')) return '';
    final parsed = Uri.tryParse(s);
    final path = (parsed != null && parsed.path.isNotEmpty) ? parsed.path : s;
    final slash = path.lastIndexOf('/');
    if (slash <= 0) return '';
    return path.substring(0, slash);
  }

  static ({double dur, int segs, String dirSig, String uriKey}) _chunkMeta(
    List<String> lines,
  ) {
    var dur = 0.0;
    var segs = 0;
    final dirs = <String>{};
    final uris = <String>[];
    for (final ln in lines) {
      final s = ln.trim();
      if (s.isEmpty) continue;
      if (s.startsWith('#EXTINF')) {
        final colon = s.indexOf(':');
        if (colon >= 0) {
          final rest = s.substring(colon + 1);
          final comma = rest.indexOf(',');
          final numStr = comma >= 0 ? rest.substring(0, comma) : rest;
          dur += double.tryParse(numStr.trim()) ?? 0.0;
        }
        segs++;
      } else if (!s.startsWith('#')) {
        uris.add(s);
        final d = _dirOf(s);
        if (d.isNotEmpty) dirs.add(d);
      }
    }
    final dirSig = dirs.length == 1 ? dirs.first : '';
    final uriKey =
        (uris.isNotEmpty && uris.length <= 30) ? uris.join('|') : '';
    return (dur: dur, segs: segs, dirSig: dirSig, uriKey: uriKey);
  }

  static AdAnalysisResult analyzeAdRanges(String text) {
    final chunks = splitByDiscontinuity(text);
    final metas = chunks.map(_chunkMeta).toList();
    final totalDur = metas.fold<double>(0.0, (a, b) => a + b.dur);

    List<AdChunkInfo> chunkListOf(Set<int>? adSet) {
      return List.generate(
        metas.length,
        (i) => AdChunkInfo(
          d: _round2(metas[i].dur),
          n: metas[i].segs,
          ad: adSet != null && adSet.contains(i),
        ),
      );
    }

    final nonEmpty = <int>[
      for (var i = 0; i < metas.length; i++)
        if (metas[i].segs > 0) i,
    ];

    if (nonEmpty.length < 2) {
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

    bool isAdShape(({double dur, int segs, String dirSig, String uriKey}) x) =>
        x.segs >= 1 && x.segs <= 30 && x.dur >= 5 && x.dur <= 90;
    String sig(({double dur, int segs, String dirSig, String uriKey}) x) =>
        '${x.segs}:${x.dur.round()}';

    final picked = <int>[];
    final compactStream = nonEmpty.length <= 30;

    // Pass 1: sandwiched mid-roll ads among non-empty chunks
    for (var k = 1; k < nonEmpty.length - 1; k++) {
      final idx = nonEmpty[k];
      final prevIdx = nonEmpty[k - 1];
      final nextIdx = nonEmpty[k + 1];
      final cur = metas[idx];
      if (!isAdShape(cur)) continue;
      if (picked.isNotEmpty && picked.last == prevIdx) continue;

      final prev = metas[prevIdx];
      final next = metas[nextIdx];
      final need = cur.dur * 3 > 180 ? cur.dur * 3 : 180.0;
      final maxNeighbor = prev.dur > next.dur ? prev.dur : next.dur;
      final minNeighbor = prev.dur < next.dur ? prev.dur : next.dur;
      final minEdgeDur = cur.dur * 2 > 45 ? cur.dur * 2 : 45.0;

      final bothLong = prev.dur >= need && next.dur >= need;
      final oneLongShortEdge =
          compactStream && maxNeighbor >= need && minNeighbor >= minEdgeDur;
      final sameNeighborDir = maxNeighbor >= need &&
          prev.dirSig.isNotEmpty &&
          prev.dirSig == next.dirSig &&
          cur.dirSig != prev.dirSig;

      if (bothLong || oneLongShortEdge || sameNeighborDir) {
        picked.add(idx);
      }
    }

    // Pass 1B: exact repeated ad-creative URI sequences (catches multi-discontinuity anime/sports)
    final uriCounts = <String, int>{};
    for (final idx in nonEmpty) {
      final m = metas[idx];
      if (isAdShape(m) && m.uriKey.isNotEmpty) {
        uriCounts[m.uriKey] = (uriCounts[m.uriKey] ?? 0) + 1;
      }
    }
    final repeatedUriKeys = {
      for (final e in uriCounts.entries)
        if (e.value >= 2) e.key,
    };
    var hasRepeatedAds = false;
    if (repeatedUriKeys.isNotEmpty) {
      final repIndices = [
        for (final idx in nonEmpty)
          if (repeatedUriKeys.contains(metas[idx].uriKey)) idx,
      ];
      final repDur = repIndices.fold<double>(0.0, (a, i) => a + metas[i].dur);
      if (totalDur > 0 && repDur <= totalDur * 0.25) {
        hasRepeatedAds = true;
        for (final idx in repIndices) {
          if (!picked.contains(idx)) picked.add(idx);
        }
        picked.sort();
      }
    }

    if (picked.isEmpty) {
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

    final adDur = picked.fold<double>(0.0, (a, i) => a + metas[i].dur);
    final maxPicked =
        totalDur > 0 ? ((totalDur / 300).ceil().clamp(6, 30)) : 6;
    final maxRatio = totalDur < 600 ? 0.15 : 0.06;
    if (!hasRepeatedAds &&
        (picked.length > maxPicked || adDur > totalDur * maxRatio)) {
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

    final adIdxAll = Set<int>.from(picked);
    final adSigs = {for (final i in picked) sig(metas[i])};
    final adDirs = {
      for (final i in picked)
        if (metas[i].dirSig.isNotEmpty) metas[i].dirSig,
    };
    final adUriKeys = {
      for (final i in picked)
        if (metas[i].uriKey.isNotEmpty) metas[i].uriKey,
    };
    final pickedDurs = [for (final i in picked) metas[i].dur];
    final minPickedDur = pickedDurs.reduce((a, b) => a < b ? a : b);
    final maxPickedDur = pickedDurs.reduce((a, b) => a > b ? a : b);

    bool matchesPickedDur(double d) =>
        pickedDurs.any((pd) => (pd - d).abs() <= 0.15);

    // Pass 2: expand to edges and remaining matching chunks
    var edgeAds = 0;
    for (var k = 0; k < nonEmpty.length; k++) {
      final idx = nonEmpty[k];
      if (adIdxAll.contains(idx)) continue;
      final cur = metas[idx];
      if (!isAdShape(cur)) continue;

      final prevIdx = k > 0 ? nonEmpty[k - 1] : -1;
      final nextIdx = k + 1 < nonEmpty.length ? nonEmpty[k + 1] : -1;
      if ((prevIdx >= 0 && adIdxAll.contains(prevIdx)) ||
          (nextIdx >= 0 && adIdxAll.contains(nextIdx))) {
        continue;
      }

      final isHead = k == 0;
      final isTail = k == nonEmpty.length - 1;
      final isEdge = isHead || isTail;
      final need = cur.dur * 3 > 180 ? cur.dur * 3 : 180.0;

      final uriHit = cur.uriKey.isNotEmpty && adUriKeys.contains(cur.uriKey);
      final dirHit = cur.dirSig.isNotEmpty && adDirs.contains(cur.dirSig);
      final sigHit = adSigs.contains(sig(cur));

      var matched = false;
      if (uriHit || dirHit || sigHit) {
        if (isEdge) {
          final adj = metas[isHead ? nextIdx : prevIdx];
          final minAdjDur = cur.dur * 2 > 45 ? cur.dur * 2 : 45.0;
          if (adj.dur >= minAdjDur ||
              uriHit ||
              dirHit ||
              (compactStream && matchesPickedDur(cur.dur))) {
            matched = true;
          }
        } else {
          final maxAdj = metas[prevIdx].dur > metas[nextIdx].dur
              ? metas[prevIdx].dur
              : metas[nextIdx].dur;
          if (maxAdj >= need || uriHit || dirHit) {
            matched = true;
          }
        }
      } else if (isTail && nonEmpty.length <= 24) {
        // Alternating tail ad creative (e.g. 16.5s mid-roll + 17.7s tail)
        final prev = metas[prevIdx];
        if (prev.dur >= 300 &&
            cur.dur >= 10 &&
            cur.dur <= 35 &&
            cur.segs <= 12 &&
            cur.dur >= minPickedDur - 5 &&
            cur.dur <= maxPickedDur + 5) {
          matched = true;
        }
      }

      if (matched) {
        adIdxAll.add(idx);
        if (isEdge) edgeAds++;
      }
    }

    var dramaAcc = 0.0;
    var allAdDur = 0.0;
    final firstNonEmptyIdx = nonEmpty.first;
    final lastNonEmptyIdx = nonEmpty.last;
    final chunkPtsStarts = List<double>.filled(chunks.length, 0.0);
    for (var i = 0; i < chunks.length; i++) {
      chunkPtsStarts[i] = dramaAcc;
      final isMidAd = adIdxAll.contains(i) &&
          i != firstNonEmptyIdx &&
          i != lastNonEmptyIdx;
      if (adIdxAll.contains(i)) {
        allAdDur += metas[i].dur;
      }
      if (!isMidAd) {
        dramaAcc += metas[i].dur;
      }
    }

    final sortedAds = adIdxAll.toList()..sort();
    final allRanges = sortedAds.map((idx) {
      final start = idx == firstNonEmptyIdx ? 0.0 : chunkPtsStarts[idx];
      final dur = metas[idx].dur;
      final end = start + dur;
      return AdRange(
        start: _round2(start),
        end: _round2(end),
        target: _round2(end + 0.4),
        isTail: idx == lastNonEmptyIdx,
      );
    }).toList();

    return AdAnalysisResult(
      ranges: allRanges,
      chunks: chunkListOf(adIdxAll),
      edgeAds: edgeAds,
      totalChunks: chunks.length,
      duration: totalDur.roundToDouble(),
      mainDuration: (totalDur - allAdDur).roundToDouble(),
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

  static final RegExp _playlistHeaderTagRe = RegExp(
    r'^#(?:EXTM3U|EXT-X-VERSION|EXT-X-TARGETDURATION|EXT-X-PLAYLIST-TYPE|EXT-X-MEDIA-SEQUENCE|EXT-X-DISCONTINUITY-SEQUENCE|EXT-X-INDEPENDENT-SEGMENTS|EXT-X-ALLOW-CACHE)\b',
    caseSensitive: false,
  );

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
      var segs = 0;
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
          segs++;
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
            final t = lines[i].trim();
            if (t.startsWith('#EXTINF')) break;
            if (_playlistHeaderTagRe.hasMatch(t)) {
              out.add(lines[i]);
            }
          }
        }
        continue;
      }

      if (segs == 0) {
        if (idx == 0) {
          for (var i = blk.a; i < blk.b; i++) {
            final t = lines[i].trim();
            if (t.isNotEmpty &&
                !RegExp(r'^#EXT-X-ENDLIST', caseSensitive: false).hasMatch(t)) {
              out.add(lines[i]);
            }
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
          (m) {
            final uriVal = m.group(1) ?? '';
            if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(uriVal)) {
              return m.group(0)!;
            }
            return 'URI="${enc(uriVal)}"';
          },
        );
      }
      return RegExp(r'^https?://', caseSensitive: false).hasMatch(s)
          ? enc(s)
          : line;
    }).join('\n');
  }
}
