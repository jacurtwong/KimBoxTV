import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'paths.dart';

class JvmException implements Exception {
  final String message;
  final String? stage;
  final int? status;

  JvmException(this.message, {this.stage, this.status});

  @override
  String toString() => message;
}

class JvmStatusSnapshot {
  final bool installed;
  final bool enabled;
  final bool running;
  final int port;
  final String java;
  final int coldStartMs;
  final int uptimeMs;
  final String lastError;
  final int spiderSites;
  final int preloadTotal;
  final int preloadDone;
  final int preloadOk;
  final int preloadFailed;
  final bool preloadRunning;

  const JvmStatusSnapshot({
    required this.installed,
    required this.enabled,
    required this.running,
    required this.port,
    required this.java,
    required this.coldStartMs,
    required this.uptimeMs,
    required this.lastError,
    this.spiderSites = 0,
    this.preloadTotal = 0,
    this.preloadDone = 0,
    this.preloadOk = 0,
    this.preloadFailed = 0,
    this.preloadRunning = false,
  });
}

class JvmBridge {
  JvmBridge._();

  static const int _minJava = 21;
  static const Duration _idleStop = Duration(minutes: 10);
  static const Duration _readyTimeout = Duration(seconds: 30);
  static const int _maxRestarts = 3;
  static const Duration _restartWindow = Duration(minutes: 5);
  static const _processJobChannel = MethodChannel('kimbox/process_job');

  static Process? _proc;
  static int _port = 0;
  static Future<int>? _starting;
  static bool _stopping = false;
  static String _java = '';
  static DateTime? _startedAt;
  static int _coldStartMs = 0;
  static String _lastError = '';
  static final List<DateTime> _restarts = [];
  static Timer? _idleTimer;
  static Timer? _readyTimer;
  static Timer? _crashRestartTimer;
  static bool _enabled = true;

  static final Dio _dio = Dio(
    BaseOptions(validateStatus: (_) => true),
  );

  static void log(String line) {
    try {
      final f = File(AppPaths.jvmLogFile);
      f.parent.createSync(recursive: true);
      if (f.existsSync() && f.lengthSync() > 2 * 1024 * 1024) {
        final rot = File('${AppPaths.jvmLogFile}.1');
        if (rot.existsSync()) rot.deleteSync();
        f.renameSync(rot.path);
      }
      f.writeAsStringSync(
        '[${DateTime.now().toIso8601String()}] $line\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }

  static bool installed() {
    final dir = AppPaths.jvmDir;
    if (dir == null) return false;
    return File(p.join(dir, 'companion-service.jar')).existsSync() &&
        File(p.join(dir, 'bcprov-jdk18on-1.78.1.jar')).existsSync();
  }

  static String resolveJava() {
    if (_java.isNotEmpty && File(_java).existsSync()) return _java;
    for (final c in AppPaths.jreCandidates()) {
      if (!File(c).existsSync()) continue;
      if (_javaMajor(c) >= _minJava) {
        _java = c;
        return c;
      }
    }
    final exe = Platform.isWindows ? 'java.exe' : 'java';
    if (_javaMajor(exe) >= _minJava) {
      _java = exe;
      return exe;
    }
    return '';
  }

  static int _javaMajor(String exe) {
    try {
      final r = Process.runSync(exe, ['-version'], runInShell: false);
      final text = '${r.stderr}\n${r.stdout}';
      final m = RegExp(r'version\s+"(\d+)(?:\.(\d+))?').firstMatch(text);
      if (m == null) return 0;
      final first = int.tryParse(m.group(1) ?? '0') ?? 0;
      return first == 1 ? (int.tryParse(m.group(2) ?? '0') ?? 0) : first;
    } catch (_) {
      return 0;
    }
  }

  static void _touchIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleStop, () {
      if (_proc == null) return;
      log('[idle] 空闲超时，停止 JVM 服务');
      stop();
    });
  }

  static Future<int> ensureStarted() async {
    if (_port > 0 && _proc != null) {
      _touchIdle();
      return _port;
    }
    if (_starting != null) return _starting!;
    if (!_enabled) throw JvmException('JVM 站源已关闭');
    if (!installed()) {
      throw JvmException('JVM 运行时缺失（需将 jvm/ 与 runtime/jre/ 放到程序目录）');
    }
    final java = resolveJava();
    if (java.isEmpty) throw JvmException('未找到 Java 21+ 运行时');

    final jvmDir = AppPaths.jvmDir!;
    final jar = p.join(jvmDir, 'companion-service.jar');
    Directory(AppPaths.jvmHomeDir).createSync(recursive: true);

    final completer = Completer<int>();
    _starting = completer.future;

    final t0 = DateTime.now();
    final args = [
      '-Duser.home=${AppPaths.jvmHomeDir}',
      '-Dfile.encoding=UTF-8',
      '-noverify',
      '-jar',
      jar,
      '--port=0',
      '--stdin-watch=on',
      '--parent-pid=$pid',
    ];

    try {
      final proc = await Process.start(
        java,
        args,
        workingDirectory: jvmDir,
        runInShell: false,
      );
      _proc = proc;
      try {
        await _processJobChannel.invokeMethod('adopt', proc.pid);
      } catch (_) {}

      var outBuf = '';
      var done = false;
      _readyTimer?.cancel();
      final timer = Timer(_readyTimeout, () {
        if (done) return;
        done = true;
        _lastError = '服务启动超时';
        try {
          proc.kill();
        } catch (_) {}
        _starting = null;
        if (!completer.isCompleted) {
          completer.completeError(JvmException(_lastError));
        }
      });
      _readyTimer = timer;

      proc.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((s) {
        if (s.trim().isNotEmpty) log('[java] ${s.trim()}');
        if (!done) {
          outBuf += s;
          final m = RegExp(r'\[COMPANION_READY\] PORT=(\d+)').firstMatch(outBuf);
          if (m != null) {
            done = true;
            timer.cancel();
            outBuf = '';
            _port = int.parse(m.group(1)!);
            _startedAt = DateTime.now();
            _coldStartMs = DateTime.now().difference(t0).inMilliseconds;
            _lastError = '';
            _starting = null;
            _touchIdle();
            log('[ready] port=$_port coldStart=${_coldStartMs}ms');
            if (!completer.isCompleted) completer.complete(_port);
          } else if (outBuf.length > 64 * 1024) {
            outBuf = outBuf.substring(outBuf.length - 4096);
          }
        }
      }, onError: (_) {});

      proc.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((s) {
        if (s.trim().isNotEmpty) log('[java:err] ${s.trim()}');
      }, onError: (_) {});

      proc.exitCode.then((code) {
        final isCurrent = (_proc == proc);
        final wasRunning = isCurrent && _port > 0;
        if (isCurrent) {
          _proc = null;
          _port = 0;
        }
        if (!done) {
          done = true;
          timer.cancel();
          _starting = null;
          _lastError = _stopping ? '服务已停止' : '服务启动失败（code=$code）';
          if (isCurrent) _stopping = false;
          if (!completer.isCompleted) {
            completer.completeError(JvmException(_lastError));
          }
          return;
        }
        if (wasRunning && !_stopping) {
          log('[crash] JVM 退出 code=$code');
          _lastError = 'JVM 异常退出（code=$code）';
          final now = DateTime.now();
          _restarts.removeWhere((t) => now.difference(t) >= _restartWindow);
          if (_restarts.length < _maxRestarts) {
            _restarts.add(now);
            _crashRestartTimer?.cancel();
            _crashRestartTimer =
                Timer(Duration(milliseconds: 1500 * _restarts.length), () {
              if (_enabled && _proc == null && !_stopping) {
                ensureStarted().catchError((_) => 0);
              }
            });
          } else {
            _lastError = 'JVM 反复崩溃，已停止自动重启';
          }
        }
        if (isCurrent) _stopping = false;
      });
    } catch (e) {
      _lastError = e.toString();
      _starting = null;
      if (!completer.isCompleted) {
        completer.completeError(JvmException(_lastError));
      }
    }

    return completer.future;
  }

  static void stop() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _readyTimer?.cancel();
    _readyTimer = null;
    _crashRestartTimer?.cancel();
    _crashRestartTimer = null;
    _starting = null;
    final p0 = _proc;
    if (p0 == null) {
      _port = 0;
      _stopping = false;
      return;
    }
    _stopping = true;
    try {
      p0.stdin.close();
    } catch (_) {}
    try {
      p0.kill();
    } catch (_) {}
    _proc = null;
    _port = 0;
  }

  static Future<Map<String, dynamic>> post(
    String pathname,
    Map<String, dynamic> body, {
    int timeoutMs = 75000,
  }) async {
    final port = await ensureStarted();
    _touchIdle();
    final resp = await _dio.post<dynamic>(
      'http://127.0.0.1:$port$pathname',
      data: body,
      options: Options(
        receiveTimeout: Duration(milliseconds: timeoutMs),
        sendTimeout: Duration(milliseconds: timeoutMs),
      ),
    );
    final status = resp.statusCode ?? 500;
    final data = resp.data is Map
        ? Map<String, dynamic>.from(resp.data as Map)
        : <String, dynamic>{};
    if (status != 200) {
      final msg =
          (data['error'] ?? data['detail'] ?? 'HTTP $status').toString();
      throw JvmException(
        msg,
        stage: data['stage']?.toString(),
        status: status,
      );
    }
    return data;
  }

  static Future<bool> loadSite({
    required String siteKey,
    required String api,
    String ext = '',
    String jar = '',
    int timeoutMs = 180000,
  }) async {
    final data = await post(
      '/spider/load',
      {
        'key': siteKey,
        'api': api,
        'ext': ext,
        'jar': jar,
        'rpcId': 'load@$siteKey#${DateTime.now().millisecondsSinceEpoch}',
      },
      timeoutMs: timeoutMs,
    );
    return data['code'] == 0;
  }

  static Future<dynamic> callSpider({
    required String siteKey,
    required String api,
    String ext = '',
    String jar = '',
    required String method,
    Map<String, dynamic>? params,
    int timeoutMs = 75000,
  }) async {
    final body = <String, dynamic>{
      'siteKey': siteKey,
      'api': api,
      'ext': ext,
      'jar': jar,
      'method': method,
      'rpcId': '$method@$siteKey#${DateTime.now().millisecondsSinceEpoch}',
      'timeoutMs': '${(timeoutMs - 5000).clamp(5000, 600000)}',
      ...?params,
    };
    final data = await post('/spider/call', body, timeoutMs: timeoutMs);
    if (data['code'] != 0) {
      throw JvmException(
        (data['detail'] ?? data['error'] ?? '站源调用失败').toString(),
        stage: data['stage']?.toString(),
      );
    }
    return data['data'];
  }

  static Future<bool> resetAll() async {
    if (_port == 0) return false;
    try {
      final r = await post('/spider/reset', const {}, timeoutMs: 15000);
      return r['code'] == 0;
    } catch (_) {
      return false;
    }
  }

  static JvmStatusSnapshot status({
    int spiderSites = 0,
    int preloadTotal = 0,
    int preloadDone = 0,
    int preloadOk = 0,
    int preloadFailed = 0,
    bool preloadRunning = false,
  }) {
    return JvmStatusSnapshot(
      installed: installed(),
      enabled: _enabled,
      running: _port > 0 && _proc != null,
      port: _port,
      java: _java,
      coldStartMs: _coldStartMs,
      uptimeMs: _startedAt != null
          ? DateTime.now().difference(_startedAt!).inMilliseconds
          : 0,
      lastError: _lastError,
      spiderSites: spiderSites,
      preloadTotal: preloadTotal,
      preloadDone: preloadDone,
      preloadOk: preloadOk,
      preloadFailed: preloadFailed,
      preloadRunning: preloadRunning,
    );
  }

  static void setEnabled(bool v) {
    _enabled = v;
    if (!_enabled) stop();
  }
}
