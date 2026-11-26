import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import '../models.dart';
import '../paths.dart';

class TvboxDb {
  TvboxDb._();

  static Database? _db;
  static const int autoKeep = 5;

  static Database get db {
    if (_db == null) {
      open();
    }
    return _db!;
  }

  static void open([String? customDbPath]) {
    if (_db != null) return;
    final path = customDbPath ?? AppPaths.dbPath;
    Directory(p.dirname(path)).createSync(recursive: true);
    final d = sqlite3.open(path);
    d.execute('''
      PRAGMA journal_mode = WAL;

      CREATE TABLE IF NOT EXISTS config (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        url          TEXT NOT NULL UNIQUE,
        name         TEXT NOT NULL DEFAULT '',
        created_at   INTEGER NOT NULL,
        last_used_at INTEGER NOT NULL DEFAULT 0,
        default_site TEXT NOT NULL DEFAULT ''
      );

      CREATE TABLE IF NOT EXISTS history (
        site_key   TEXT NOT NULL,
        vod_id     TEXT NOT NULL,
        vod_name   TEXT,
        vod_pic    TEXT,
        source     TEXT,
        ep_name    TEXT,
        ep_index   INTEGER NOT NULL DEFAULT 0,
        ep_url     TEXT,
        position   REAL NOT NULL DEFAULT 0,
        duration   REAL NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (site_key, vod_id)
      );

      CREATE TABLE IF NOT EXISTS show_mark (
        show_key   TEXT PRIMARY KEY,
        show_name  TEXT,
        intro      REAL NOT NULL DEFAULT 0,
        outro      REAL NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS favorite (
        site_key   TEXT NOT NULL,
        vod_id     TEXT NOT NULL,
        vod_name   TEXT,
        vod_pic    TEXT,
        remarks    TEXT,
        created_at INTEGER NOT NULL,
        PRIMARY KEY (site_key, vod_id)
      );

      CREATE INDEX IF NOT EXISTS idx_history_time ON history(updated_at DESC);
      CREATE INDEX IF NOT EXISTS idx_favorite_time ON favorite(created_at DESC);
    ''');
    _migrate(d);
    try {
      d.execute('DROP TABLE IF EXISTS episode_history');
    } catch (_) {}
    _db = d;
  }

  static void _migrate(Database d) {
    try {
      final cols = d
          .select('PRAGMA table_info(config)')
          .map((r) => r['name'].toString())
          .toList();
      if (!cols.contains('default_site')) {
        d.execute(
            "ALTER TABLE config ADD COLUMN default_site TEXT NOT NULL DEFAULT ''");
      }
    } catch (_) {}
  }

  static void close() {
    try {
      _db?.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    try {
      _db?.dispose();
    } catch (_) {}
    _db = null;
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  /* ---------- 配置源 ---------- */
  static List<ConfigRecord> listConfigs() {
    final rows =
        db.select('SELECT * FROM config ORDER BY last_used_at DESC, id ASC');
    return rows.map(ConfigRecord.fromMap).toList();
  }

  static ConfigRecord? getConfig(int id) {
    final rows = db.select('SELECT * FROM config WHERE id = ?', [id]);
    return rows.isEmpty ? null : ConfigRecord.fromMap(rows.first);
  }

  static ConfigRecord? getConfigByUrl(String url) {
    final rows = db.select('SELECT * FROM config WHERE url = ?', [url]);
    return rows.isEmpty ? null : ConfigRecord.fromMap(rows.first);
  }

  static ConfigRecord addConfig(String url, String name) {
    final exist = getConfigByUrl(url);
    if (exist != null) return exist;
    db.execute(
      'INSERT INTO config (url, name, created_at, last_used_at) VALUES (?, ?, ?, ?)',
      [url, name, _now(), 0],
    );
    return getConfig(db.lastInsertRowId)!;
  }

  static void touchConfig(int id) {
    db.execute(
        'UPDATE config SET last_used_at = ? WHERE id = ?', [_now(), id]);
  }

  static ConfigRecord? renameConfig(int id, String name) {
    db.execute('UPDATE config SET name = ? WHERE id = ?', [name, id]);
    return getConfig(id);
  }

  static void removeConfig(int id) {
    db.execute('DELETE FROM config WHERE id = ?', [id]);
  }

  static ConfigRecord? setDefaultSite(int id, String siteKey) {
    db.execute(
        'UPDATE config SET default_site = ? WHERE id = ?', [siteKey, id]);
    return getConfig(id);
  }

  static void clearConfigs() {
    db.execute('DELETE FROM config');
  }

  /* ---------- 播放历史 ---------- */
  static List<HistoryItem> listHistory({int limit = 100}) {
    final rows = db.select(
        'SELECT * FROM history ORDER BY updated_at DESC LIMIT ?', [limit]);
    return rows.map(HistoryItem.fromMap).toList();
  }

  static HistoryItem? getHistory(String siteKey, String vodId) {
    final rows = db.select(
      'SELECT * FROM history WHERE site_key = ? AND vod_id = ?',
      [siteKey, vodId],
    );
    return rows.isEmpty ? null : HistoryItem.fromMap(rows.first);
  }

  static void saveHistory({
    required String siteKey,
    required String vodId,
    String vodName = '',
    String vodPic = '',
    String source = '',
    String epName = '',
    int epIndex = 0,
    String epUrl = '',
    double position = 0,
    double duration = 0,
  }) {
    db.execute('''
      INSERT INTO history (site_key, vod_id, vod_name, vod_pic, source, ep_name, ep_index, ep_url, position, duration, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(site_key, vod_id) DO UPDATE SET
        vod_name = excluded.vod_name,
        vod_pic  = excluded.vod_pic,
        source   = excluded.source,
        ep_name  = excluded.ep_name,
        ep_index = excluded.ep_index,
        ep_url   = excluded.ep_url,
        position = excluded.position,
        duration = excluded.duration,
        updated_at = excluded.updated_at
    ''', [
      siteKey,
      vodId,
      vodName,
      vodPic,
      source,
      epName,
      epIndex,
      epUrl,
      position,
      duration,
      _now(),
    ]);
  }

  static void removeHistory(String siteKey, String vodId) {
    db.execute(
      'DELETE FROM history WHERE site_key = ? AND vod_id = ?',
      [siteKey, vodId],
    );
  }

  static void clearHistory() {
    db.execute('DELETE FROM history');
  }

  /* ---------- 片头 / 片尾标记（按片名） ---------- */
  static String showMarkKey(String name) {
    return name
        .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F-\u009F]'), '')
        .replaceAll(
            RegExp(r'''[\s·・,，.。:：!！?？'"“”()（）\[\]【】\-—_]'''), '')
        .toLowerCase();
  }

  static ShowMark? getShowMark(String name) {
    final k = showMarkKey(name);
    if (k.isEmpty) return null;
    final rows =
        db.select('SELECT * FROM show_mark WHERE show_key = ?', [k]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return ShowMark(
      intro: (r['intro'] as num?)?.toDouble() ?? 0,
      outro: (r['outro'] as num?)?.toDouble() ?? 0,
      name: (r['show_name'] ?? '').toString(),
    );
  }

  static ShowMark? saveShowMark(String name, double intro, double outro) {
    final k = showMarkKey(name);
    if (k.isEmpty) return null;
    final now = _now();
    final exist =
        db.select('SELECT 1 FROM show_mark WHERE show_key = ?', [k]);
    if (exist.isNotEmpty) {
      db.execute(
        'UPDATE show_mark SET intro = ?, outro = ?, show_name = ?, updated_at = ? WHERE show_key = ?',
        [intro, outro, name, now, k],
      );
    } else {
      db.execute(
        'INSERT INTO show_mark (show_key, show_name, intro, outro, updated_at) VALUES (?, ?, ?, ?, ?)',
        [k, name, intro, outro, now],
      );
    }
    return getShowMark(name);
  }

  static bool removeShowMark(String name) {
    final k = showMarkKey(name);
    if (k.isEmpty) return false;
    db.execute('DELETE FROM show_mark WHERE show_key = ?', [k]);
    return true;
  }

  /* ---------- 收藏 ---------- */
  static List<FavoriteItem> listFavorites() {
    final rows =
        db.select('SELECT * FROM favorite ORDER BY created_at DESC');
    return rows.map(FavoriteItem.fromMap).toList();
  }

  static bool hasFavorite(String siteKey, String vodId) {
    final rows = db.select(
      'SELECT 1 FROM favorite WHERE site_key = ? AND vod_id = ?',
      [siteKey, vodId],
    );
    return rows.isNotEmpty;
  }

  static void addFavorite({
    required String siteKey,
    required String vodId,
    String vodName = '',
    String vodPic = '',
    String remarks = '',
  }) {
    db.execute(
      'INSERT OR REPLACE INTO favorite (site_key, vod_id, vod_name, vod_pic, remarks, created_at) VALUES (?, ?, ?, ?, ?, ?)',
      [siteKey, vodId, vodName, vodPic, remarks, _now()],
    );
  }

  static void removeFavorite(String siteKey, String vodId) {
    db.execute(
      'DELETE FROM favorite WHERE site_key = ? AND vod_id = ?',
      [siteKey, vodId],
    );
  }

  static bool toggleFavorite({
    required String siteKey,
    required String vodId,
    String vodName = '',
    String vodPic = '',
    String remarks = '',
  }) {
    if (hasFavorite(siteKey, vodId)) {
      removeFavorite(siteKey, vodId);
      return false;
    }
    addFavorite(
      siteKey: siteKey,
      vodId: vodId,
      vodName: vodName,
      vodPic: vodPic,
      remarks: remarks,
    );
    return true;
  }

  static void clearFavorites() {
    db.execute('DELETE FROM favorite');
  }

  /* ---------- 备份与还原 ---------- */
  static Map<String, int> countAll() {
    final c = (db.select('SELECT COUNT(*) c FROM config').first['c'] as num)
        .toInt();
    final f = (db.select('SELECT COUNT(*) c FROM favorite').first['c'] as num)
        .toInt();
    final h = (db.select('SELECT COUNT(*) c FROM history').first['c'] as num)
        .toInt();
    return {'config': c, 'favorite': f, 'history': h};
  }

  static String _stamp() {
    final d = DateTime.now();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${pad(d.month)}${pad(d.day)}-${pad(d.hour)}${pad(d.minute)}${pad(d.second)}';
  }

  static void _pruneAuto([String? backupsDir]) {
    try {
      final dir = Directory(backupsDir ?? AppPaths.backupsDir);
      if (!dir.existsSync()) return;
      final autos = dir
          .listSync()
          .whereType<File>()
          .where((f) {
            final name = p.basename(f.path);
            return name.endsWith('.db') && !name.startsWith('tvbox-manual-');
          })
          .map((f) => (file: f, mtime: f.statSync().modified))
          .toList()
        ..sort((a, b) => a.mtime.compareTo(b.mtime));
      while (autos.length > autoKeep) {
        final victim = autos.removeAt(0);
        try {
          victim.file.deleteSync();
        } catch (_) {}
      }
    } catch (_) {}
  }

  static ({String? file, bool skipped, String? error, Map<String, int>? stats})
      backup([String label = 'auto', String? backupsDir]) {
    try {
      final stats = countAll();
      if ((stats['config'] ?? 0) +
              (stats['favorite'] ?? 0) +
              (stats['history'] ?? 0) ==
          0) {
        return (file: null, skipped: true, error: null, stats: stats);
      }
      final dir = backupsDir ?? AppPaths.backupsDir;
      Directory(dir).createSync(recursive: true);
      final isManual = label == 'manual';
      final name =
          'tvbox-${isManual ? 'manual' : 'auto-$label'}-${_stamp()}.db';
      final file = p.join(dir, name);
      db.execute("VACUUM INTO '${file.replaceAll("'", "''")}'");
      if (!isManual) _pruneAuto(dir);
      return (file: name, skipped: false, error: null, stats: stats);
    } catch (e) {
      return (file: null, skipped: false, error: e.toString(), stats: null);
    }
  }

  static List<BackupInfo> listBackups([String? backupsDir]) {
    final dir = Directory(backupsDir ?? AppPaths.backupsDir);
    if (!dir.existsSync()) return [];
    final items = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.db'))
        .map((f) {
      final st = f.statSync();
      final name = p.basename(f.path);
      return BackupInfo(
        name: name,
        size: st.size,
        time: st.modified,
        manual: name.startsWith('tvbox-manual-'),
      );
    }).toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    return items;
  }

  static String _safeBackupPath(String name, [String? backupsDir]) {
    if (!RegExp(r'^tvbox-[A-Za-z0-9._-]+\.db$').hasMatch(name)) {
      throw Exception('非法的备份文件名');
    }
    final dir = p.normalize(backupsDir ?? AppPaths.backupsDir);
    final full = p.normalize(p.join(dir, name));
    if (p.dirname(full) != dir) {
      throw Exception('非法的备份路径');
    }
    if (!File(full).existsSync()) {
      throw Exception('备份文件不存在: $name');
    }
    return full;
  }

  static void deleteBackup(String name, [String? backupsDir]) {
    final full = _safeBackupPath(name, backupsDir);
    File(full).deleteSync();
  }

  static Map<String, int> restoreBackup(String name,
      {String? backupsDir, String? customDbPath}) {
    final full = _safeBackupPath(name, backupsDir);
    try {
      backup('before-restore', backupsDir);
    } catch (_) {}

    final targetDb = customDbPath ?? AppPaths.dbPath;
    close();

    for (final suffix in ['-wal', '-shm']) {
      final f = File('$targetDb$suffix');
      try {
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    File(full).copySync(targetDb);
    open(targetDb);
    return countAll();
  }
}
