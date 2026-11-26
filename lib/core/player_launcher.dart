import 'dart:io';
import 'package:path/path.dart' as p;
import 'models.dart';

class _PlayerCandidate {
  final String id;
  final String name;
  final String friendly;
  final bool hasUi;
  final String exeName;
  final List<String> paths;
  final List<String> Function(String url, String title, double startAt) buildArgs;

  const _PlayerCandidate({
    required this.id,
    required this.name,
    required this.friendly,
    required this.hasUi,
    required this.exeName,
    required this.paths,
    required this.buildArgs,
  });
}

class PlayerLauncher {
  PlayerLauncher._();

  static final String _local = Platform.environment['LOCALAPPDATA'] ?? '';
  static final String _pf =
      Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
  static final String _pf86 =
      Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';

  static final List<_PlayerCandidate> _candidates = [
    _PlayerCandidate(
      id: 'potplayer',
      name: 'PotPlayer',
      friendly: 'PotPlayer（完整界面）',
      hasUi: true,
      exeName: 'PotPlayerMini64',
      paths: [
        '$_pf\\DAUM\\PotPlayer\\PotPlayerMini64.exe',
        '$_pf86\\DAUM\\PotPlayer\\PotPlayerMini.exe',
        '$_pf\\DAUM\\PotPlayer\\PotPlayerMini.exe',
      ],
      buildArgs: (url, title, startAt) => [
        url,
        if (startAt > 0) '/seek=${startAt.floor()}',
      ],
    ),
    _PlayerCandidate(
      id: 'vlc',
      name: 'VLC',
      friendly: 'VLC（完整界面）',
      hasUi: true,
      exeName: 'vlc',
      paths: [
        '$_pf\\VideoLAN\\VLC\\vlc.exe',
        '$_pf86\\VideoLAN\\VLC\\vlc.exe',
      ],
      buildArgs: (url, title, startAt) => [
        '--started-from-file',
        url,
        if (startAt > 0) '--start-time=${startAt.floor()}',
      ],
    ),
    _PlayerCandidate(
      id: 'mpv',
      name: 'mpv',
      friendly: 'mpv（鼠标移动显示控制条）',
      hasUi: true,
      exeName: 'mpv',
      paths: [
        '$_local\\Microsoft\\WinGet\\Links\\mpv.exe',
        '$_pf\\mpv\\mpv.exe',
        '$_pf86\\mpv\\mpv.exe',
      ],
      buildArgs: (url, title, startAt) => [
        '--force-window=yes',
        '--osc=yes',
        '--title=$title',
        if (startAt > 0) '--start=${startAt.floor()}',
        url,
      ],
    ),
    _PlayerCandidate(
      id: 'mpc-hc',
      name: 'MPC-HC',
      friendly: 'MPC-HC（完整界面）',
      hasUi: true,
      exeName: 'mpc-hc64',
      paths: [
        '$_pf\\MPC-HC\\mpc-hc64.exe',
        '$_pf86\\MPC-HC\\mpc-hc.exe',
      ],
      buildArgs: (url, title, startAt) => [
        url,
        if (startAt > 0) ...['/start', '${(startAt * 1000).floor()}'],
      ],
    ),
    _PlayerCandidate(
      id: 'ffplay',
      name: 'ffplay',
      friendly: 'ffplay（无界面，键盘控制）',
      hasUi: false,
      exeName: 'ffplay',
      paths: [
        '$_local\\Microsoft\\WinGet\\Links\\ffplay.exe',
      ],
      buildArgs: (url, title, startAt) => [
        '-window_title',
        'KimBoxTV - $title',
        '-autoexit',
        if (startAt > 0) ...['-ss', '${startAt.floor()}'],
        url,
      ],
    ),
  ];

  static String? _findInPath(String exeName) {
    final dirs = (Platform.environment['PATH'] ?? '').split(';');
    for (final dir in dirs) {
      if (dir.isEmpty) continue;
      for (final ext in const ['.exe', '.bat', '.cmd', '']) {
        final full = p.join(dir, '$exeName$ext');
        try {
          if (FileSystemEntity.isFileSync(full)) return full;
        } catch (_) {}
      }
    }
    return null;
  }

  static String? _resolveExe(_PlayerCandidate c) {
    for (final path in c.paths) {
      try {
        if (path.isNotEmpty && File(path).existsSync()) return path;
      } catch (_) {}
    }
    return _findInPath(c.exeName);
  }

  static List<ExternalPlayerInfo> listAvailable() {
    final out = <ExternalPlayerInfo>[];
    for (final c in _candidates) {
      final exe = _resolveExe(c);
      if (exe != null) {
        out.add(ExternalPlayerInfo(
          id: c.id,
          name: c.name,
          friendly: c.friendly,
          hasUi: c.hasUi,
          exe: exe,
        ));
      }
    }
    return out;
  }

  static Future<({String player, bool hasUi})> play(
    String mediaUrl, {
    String title = 'TVBox 视频',
    String playerId = '',
    double startAt = 0,
  }) async {
    final available = listAvailable();
    if (available.isEmpty) {
      throw Exception('没有找到可用的外部播放器（可以装 PotPlayer / VLC / mpv）');
    }

    List<ExternalPlayerInfo> queue;
    if (playerId.isNotEmpty) {
      final idx = available.indexWhere((p) => p.id == playerId);
      if (idx == -1) throw Exception('未安装播放器: $playerId');
      queue = [
        available[idx],
        ...available.sublist(0, idx),
        ...available.sublist(idx + 1),
      ];
    } else {
      queue = available;
    }

    final errors = <String>[];
    for (final pInfo in queue) {
      final cand = _candidates.firstWhere((c) => c.id == pInfo.id);
      try {
        final args = cand.buildArgs(mediaUrl, title, startAt);
        await Process.start(
          pInfo.exe,
          args,
          mode: ProcessStartMode.detached,
          runInShell: false,
        );
        return (player: pInfo.name, hasUi: pInfo.hasUi);
      } catch (e) {
        errors.add('${pInfo.name}: $e');
      }
    }
    throw Exception('启动播放器失败 -> ${errors.join(' | ')}');
  }
}
