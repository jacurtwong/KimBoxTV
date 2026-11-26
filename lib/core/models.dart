import 'dart:convert';

class ConfigRecord {
  final int id;
  final String url;
  final String name;
  final int createdAt;
  final int lastUsedAt;
  final String defaultSite;

  const ConfigRecord({
    required this.id,
    required this.url,
    required this.name,
    required this.createdAt,
    required this.lastUsedAt,
    required this.defaultSite,
  });

  String get displayName {
    final cleaned = name.replaceAll(RegExp(r'\s*·\s*\d+\s*站\s*$'), '').trim();
    if (cleaned.isNotEmpty) return cleaned;
    try {
      final u = Uri.parse(url);
      if (u.host.isNotEmpty) return u.host;
    } catch (_) {}
    return url.length > 40 ? url.substring(0, 40) : url;
  }

  factory ConfigRecord.fromMap(Map<String, dynamic> m) {
    return ConfigRecord(
      id: (m['id'] as num).toInt(),
      url: (m['url'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      createdAt: (m['created_at'] as num?)?.toInt() ?? 0,
      lastUsedAt: (m['last_used_at'] as num?)?.toInt() ?? 0,
      defaultSite: (m['default_site'] ?? '').toString(),
    );
  }
}

class SiteInfo {
  final String key;
  final String name;
  final int type;
  final String api;
  final dynamic ext;
  final bool isDexSpider;
  final int searchable;
  final int changeable;
  final List<String> categories;

  const SiteInfo({
    required this.key,
    required this.name,
    required this.type,
    required this.api,
    this.ext = '',
    this.isDexSpider = false,
    this.searchable = 1,
    this.changeable = 1,
    this.categories = const [],
  });

  String get extString {
    if (ext == null) return '';
    if (ext is String) return ext as String;
    if (ext is Map || ext is List) return jsonEncode(ext);
    return ext.toString();
  }

  String get fingerprint => '$key:$api:$name';

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'type': type,
        'api': api,
        'ext': ext,
        'isDexSpider': isDexSpider,
        'searchable': searchable,
        'changeable': changeable,
        'categories': categories,
      };

  factory SiteInfo.fromJson(Map<String, dynamic> m) {
    return SiteInfo(
      key: (m['key'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      type: (m['type'] as num?)?.toInt() ?? 0,
      api: (m['api'] ?? '').toString(),
      ext: m['ext'] ?? '',
      isDexSpider: m['isDexSpider'] == true,
      searchable: (m['searchable'] as num?)?.toInt() ?? 1,
      changeable: (m['changeable'] as num?)?.toInt() ?? 1,
      categories: (m['categories'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }
}

class ParsedConfig {
  final String spider;
  final String wallpaper;
  final String logo;
  final List<SiteInfo> sites;
  final List<dynamic> parses;
  final List<dynamic> rules;

  const ParsedConfig({
    this.spider = '',
    this.wallpaper = '',
    this.logo = '',
    required this.sites,
    this.parses = const [],
    this.rules = const [],
  });

  Map<String, dynamic> toJson() => {
        'spider': spider,
        'wallpaper': wallpaper,
        'logo': logo,
        'sites': sites.map((s) => s.toJson()).toList(),
        'parses': parses,
        'rules': rules,
      };

  factory ParsedConfig.fromJson(Map<String, dynamic> m) {
    return ParsedConfig(
      spider: (m['spider'] ?? '').toString(),
      wallpaper: (m['wallpaper'] ?? '').toString(),
      logo: (m['logo'] ?? '').toString(),
      sites: (m['sites'] as List?)
              ?.whereType<Map>()
              .map((e) => SiteInfo.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      parses: (m['parses'] as List?) ?? const [],
      rules: (m['rules'] as List?) ?? const [],
    );
  }
}

class CategoryItem {
  final String typeId;
  final String typeName;

  const CategoryItem({required this.typeId, required this.typeName});
}

class SpiderFilterValue {
  final String n;
  final String v;

  const SpiderFilterValue({required this.n, required this.v});
}

class SpiderFilterGroup {
  final String key;
  final String name;
  final List<SpiderFilterValue> values;

  const SpiderFilterGroup({
    required this.key,
    required this.name,
    required this.values,
  });
}

class VideoItem {
  final String vodId;
  final String vodName;
  final String vodPic;
  final String vodRemarks;
  final String typeName;
  final String? siteKey;
  final String? siteName;
  final int sources;
  final double position;
  final double duration;
  bool faved;

  VideoItem({
    required this.vodId,
    required this.vodName,
    this.vodPic = '',
    this.vodRemarks = '',
    this.typeName = '',
    this.siteKey,
    this.siteName,
    this.sources = 1,
    this.position = 0,
    this.duration = 0,
    this.faved = false,
  });

  VideoItem copyWith({
    String? vodId,
    String? vodName,
    String? vodPic,
    String? vodRemarks,
    String? typeName,
    String? siteKey,
    String? siteName,
    int? sources,
    double? position,
    double? duration,
    bool? faved,
  }) {
    return VideoItem(
      vodId: vodId ?? this.vodId,
      vodName: vodName ?? this.vodName,
      vodPic: vodPic ?? this.vodPic,
      vodRemarks: vodRemarks ?? this.vodRemarks,
      typeName: typeName ?? this.typeName,
      siteKey: siteKey ?? this.siteKey,
      siteName: siteName ?? this.siteName,
      sources: sources ?? this.sources,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      faved: faved ?? this.faved,
    );
  }
}

class HomeResult {
  final List<CategoryItem> classes;
  final List<VideoItem> list;
  final Map<String, List<SpiderFilterGroup>> filters;
  final int page;
  final int pagecount;
  final int total;

  const HomeResult({
    required this.classes,
    required this.list,
    this.filters = const {},
    this.page = 1,
    this.pagecount = 1,
    this.total = 0,
  });
}

class CategoryResult {
  final int page;
  final int pagecount;
  final int total;
  final List<VideoItem> list;

  const CategoryResult({
    required this.page,
    required this.pagecount,
    required this.total,
    required this.list,
  });
}

class Episode {
  final String title;
  final String url;

  const Episode({required this.title, required this.url});
}

class PlaySource {
  final String sourceName;
  final String flag;
  final List<Episode> episodes;

  const PlaySource({
    required this.sourceName,
    this.flag = '',
    required this.episodes,
  });
}

class HistoryItem {
  final String siteKey;
  final String vodId;
  final String vodName;
  final String vodPic;
  final String source;
  final String epName;
  final int epIndex;
  final String epUrl;
  final double position;
  final double duration;
  final int updatedAt;

  const HistoryItem({
    required this.siteKey,
    required this.vodId,
    required this.vodName,
    required this.vodPic,
    required this.source,
    required this.epName,
    required this.epIndex,
    required this.epUrl,
    required this.position,
    required this.duration,
    required this.updatedAt,
  });

  factory HistoryItem.fromMap(Map<String, dynamic> m) {
    return HistoryItem(
      siteKey: (m['site_key'] ?? '').toString(),
      vodId: (m['vod_id'] ?? '').toString(),
      vodName: (m['vod_name'] ?? '').toString(),
      vodPic: (m['vod_pic'] ?? '').toString(),
      source: (m['source'] ?? '').toString(),
      epName: (m['ep_name'] ?? '').toString(),
      epIndex: (m['ep_index'] as num?)?.toInt() ?? 0,
      epUrl: (m['ep_url'] ?? '').toString(),
      position: (m['position'] as num?)?.toDouble() ?? 0,
      duration: (m['duration'] as num?)?.toDouble() ?? 0,
      updatedAt: (m['updated_at'] as num?)?.toInt() ?? 0,
    );
  }
}

class FavoriteItem {
  final String siteKey;
  final String vodId;
  final String vodName;
  final String vodPic;
  final String remarks;
  final int createdAt;

  const FavoriteItem({
    required this.siteKey,
    required this.vodId,
    required this.vodName,
    required this.vodPic,
    required this.remarks,
    required this.createdAt,
  });

  factory FavoriteItem.fromMap(Map<String, dynamic> m) {
    return FavoriteItem(
      siteKey: (m['site_key'] ?? '').toString(),
      vodId: (m['vod_id'] ?? '').toString(),
      vodName: (m['vod_name'] ?? '').toString(),
      vodPic: (m['vod_pic'] ?? '').toString(),
      remarks: (m['remarks'] ?? '').toString(),
      createdAt: (m['created_at'] as num?)?.toInt() ?? 0,
    );
  }
}

class ShowMark {
  final double intro;
  final double outro;
  final String name;

  const ShowMark({this.intro = 0, this.outro = 0, this.name = ''});
}

class VideoDetail {
  final String vodId;
  final String vodName;
  final String vodPic;
  final String vodRemarks;
  final String typeName;
  final String content;
  final String director;
  final String actor;
  final String year;
  final String area;
  final List<PlaySource> playSources;
  final bool spider;
  final String siteKey;
  final HistoryItem? history;
  bool favorited;

  VideoDetail({
    required this.vodId,
    required this.vodName,
    this.vodPic = '',
    this.vodRemarks = '',
    this.typeName = '',
    this.content = '',
    this.director = '',
    this.actor = '',
    this.year = '',
    this.area = '',
    required this.playSources,
    this.spider = false,
    this.siteKey = '',
    this.history,
    this.favorited = false,
  });
}

class SitePing {
  final int ms;
  final bool ok;
  final bool dex;
  final bool unsupported;

  const SitePing({
    required this.ms,
    required this.ok,
    this.dex = false,
    this.unsupported = false,
  });
}

class SameSourceResult {
  final String siteKey;
  final String siteName;
  final String vodId;
  final String vodName;
  final String pic;
  final List<String> lines;
  final int episodes;
  final int? disc;
  final int ms;

  const SameSourceResult({
    required this.siteKey,
    required this.siteName,
    required this.vodId,
    required this.vodName,
    required this.pic,
    required this.lines,
    required this.episodes,
    this.disc,
    required this.ms,
  });
}

class BackupInfo {
  final String name;
  final int size;
  final DateTime time;
  final bool manual;

  const BackupInfo({
    required this.name,
    required this.size,
    required this.time,
    required this.manual,
  });
}

class ExternalPlayerInfo {
  final String id;
  final String name;
  final String friendly;
  final bool hasUi;
  final String exe;

  const ExternalPlayerInfo({
    required this.id,
    required this.name,
    required this.friendly,
    required this.hasUi,
    required this.exe,
  });
}

class AdChunkInfo {
  final double d;
  final int n;
  final bool ad;

  const AdChunkInfo({required this.d, required this.n, required this.ad});
}

class AdRange {
  final double start;
  final double end;
  final double target;
  final bool isTail;

  const AdRange({
    required this.start,
    required this.end,
    required this.target,
    this.isTail = false,
  });
}

class AdAnalysisResult {
  final List<AdRange> ranges;
  final List<AdChunkInfo> chunks;
  final int edgeAds;
  final int totalChunks;
  final double duration;
  final double mainDuration;
  final bool rejected;

  const AdAnalysisResult({
    required this.ranges,
    required this.chunks,
    required this.edgeAds,
    required this.totalChunks,
    required this.duration,
    required this.mainDuration,
    this.rejected = false,
  });
}

class AdCutRange {
  final double start;
  final double end;

  const AdCutRange(this.start, this.end);
}

class HlsProxyResult {
  final String token;
  final String path;
  final String absoluteUrl;
  final String mode;
  final bool cut;
  final List<AdCutRange> cuts;
  final double removedSeconds;
  final List<AdRange> ranges;
  final List<AdChunkInfo> chunks;
  final int edgeAds;
  final double duration;
  final double sourceDuration;
  final int totalChunks;
  final String source;

  const HlsProxyResult({
    required this.token,
    required this.path,
    required this.absoluteUrl,
    required this.mode,
    required this.cut,
    required this.cuts,
    required this.removedSeconds,
    required this.ranges,
    required this.chunks,
    required this.edgeAds,
    required this.duration,
    required this.sourceDuration,
    required this.totalChunks,
    required this.source,
  });
}

class ProbeResult {
  final int disc;
  final int segments;
  final int duration;
  final int multiAudio;
  final bool master;
  final String? error;

  const ProbeResult({
    this.disc = 0,
    this.segments = 0,
    this.duration = 0,
    this.multiAudio = 0,
    this.master = false,
    this.error,
  });
}

class AdDebugSnapshot {
  final String title;
  final String url;
  final bool proxy;
  final double duration;
  final List<AdRange> ranges;
  final List<AdChunkInfo> chunks;
  final String mode;
  final bool wantCut;
  final bool cut;
  final List<AdCutRange> cuts;
  final double removed;

  const AdDebugSnapshot({
    required this.title,
    required this.url,
    required this.proxy,
    required this.duration,
    required this.ranges,
    required this.chunks,
    required this.mode,
    required this.wantCut,
    required this.cut,
    required this.cuts,
    required this.removed,
  });
}
