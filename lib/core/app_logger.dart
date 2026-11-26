import 'dart:io';
import 'paths.dart';

class AppLogger {
  AppLogger._();

  static void log(String src, String msg) {
    try {
      final f = File(AppPaths.logFile);
      f.parent.createSync(recursive: true);
      if (f.existsSync() && f.lengthSync() > 512 * 1024) {
        final rotated = File('${AppPaths.logFile}.1');
        if (rotated.existsSync()) rotated.deleteSync();
        f.renameSync(rotated.path);
      }
      final line = '[${DateTime.now().toIso8601String()}] [$src] $msg\n';
      f.writeAsStringSync(line, mode: FileMode.append, flush: false);
    } catch (_) {}
  }

  static String tail({int maxLines = 200}) {
    try {
      final f = File(AppPaths.logFile);
      if (!f.existsSync()) return '(还没有日志)';
      final lines = f.readAsLinesSync();
      if (lines.length <= maxLines) return lines.join('\n');
      return lines.sublist(lines.length - maxLines).join('\n');
    } catch (_) {
      return '(读取日志失败)';
    }
  }
}
