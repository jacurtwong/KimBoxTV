import 'dart:io';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;

class CacheCleaner {
  CacheCleaner._();

  static const List<String> _cacheSubfolders = [
    'Cache',
    'Code Cache',
    'GPUCache',
    'DawnGraphiteCache',
    'DawnWebGPUCache',
    'ShaderCache',
    'GrShaderCache',
  ];

  static int _getDirSize(Directory dir) {
    var size = 0;
    try {
      if (!dir.existsSync()) return 0;
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            size += entity.lengthSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return size;
  }

  static int _cleanFolderContents(Directory dir) {
    var freed = 0;
    try {
      if (!dir.existsSync()) return 0;
      for (final entity in dir.listSync(followLinks: false)) {
        try {
          if (entity is Directory) {
            freed += _cleanFolderContents(entity);
            entity.deleteSync();
          } else if (entity is File) {
            freed += entity.lengthSync();
            entity.deleteSync();
          }
        } catch (_) {}
      }
    } catch (_) {}
    return freed;
  }

  static ({int sizeBytes, double sizeMB, String path}) getCacheInfo() {
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) {
      return (sizeBytes: 0, sizeMB: 0, path: '');
    }
    final targetDir = p.join(appData, 'kimboxtv');
    var totalBytes = 0;
    for (final folderName in const ['kimboxtv', 'kimboxpc']) {
      final base = p.join(appData, folderName);
      for (final sub in _cacheSubfolders) {
        totalBytes += _getDirSize(Directory(p.join(base, sub)));
      }
    }
    final mb = (totalBytes / 1024 / 1024 * 100).round() / 100;
    return (sizeBytes: totalBytes, sizeMB: mb, path: targetDir);
  }

  static ({double freedMB, double currentMB}) cleanCache() {
    final before = getCacheInfo();
    // Clear Flutter's in-memory image cache as well
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}

    var freedBytes = 0;
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      for (final folderName in const ['kimboxtv', 'kimboxpc']) {
        final base = p.join(appData, folderName);
        for (final sub in _cacheSubfolders) {
          freedBytes += _cleanFolderContents(Directory(p.join(base, sub)));
        }
      }
    }
    final after = getCacheInfo();
    final diff = before.sizeBytes - after.sizeBytes;
    final effective = freedBytes > diff ? freedBytes : diff;
    final freedMB = (effective / 1024 / 1024 * 100).round() / 100;
    return (
      freedMB: freedMB > 0 ? freedMB : before.sizeMB,
      currentMB: after.sizeMB,
    );
  }
}
