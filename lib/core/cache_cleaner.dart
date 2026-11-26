import 'dart:io';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'paths.dart';

class CacheCleaner {
  CacheCleaner._();

  static const List<String> _legacySubfolders = [
    'Cache',
    'Code Cache',
    'GPUCache',
    'DawnGraphiteCache',
    'DawnWebGPUCache',
    'ShaderCache',
    'GrShaderCache',
  ];

  static String? _tryCacheDir() {
    try {
      return AppPaths.cacheDir;
    } catch (_) {
      return null;
    }
  }

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
            final len = entity.lengthSync();
            entity.deleteSync();
            freed += len;
          }
        } catch (_) {}
      }
    } catch (_) {}
    return freed;
  }

  static List<Directory> _targetDirs({
    String? customCacheDir,
    String? customAppData,
  }) {
    final dirs = <Directory>[];
    final appCache = customCacheDir ?? _tryCacheDir();
    if (appCache != null && appCache.isNotEmpty) {
      dirs.add(Directory(appCache));
    }
    final appData = customAppData ?? Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      for (final folderName in const ['kimboxtv', 'kimboxpc']) {
        final base = p.join(appData, folderName);
        for (final sub in _legacySubfolders) {
          dirs.add(Directory(p.join(base, sub)));
        }
      }
    }
    return dirs;
  }

  static ({int sizeBytes, double sizeMB, String path}) getCacheInfo({
    String? customCacheDir,
    String? customAppData,
  }) {
    final appCache = customCacheDir ?? _tryCacheDir() ?? '';
    var totalBytes = 0;
    for (final dir in _targetDirs(
      customCacheDir: customCacheDir,
      customAppData: customAppData,
    )) {
      totalBytes += _getDirSize(dir);
    }
    final mb = (totalBytes / 1024 / 1024 * 100).round() / 100;
    return (sizeBytes: totalBytes, sizeMB: mb, path: appCache);
  }

  static ({double freedMB, double currentMB}) cleanCache({
    String? customCacheDir,
    String? customAppData,
  }) {
    final before = getCacheInfo(
      customCacheDir: customCacheDir,
      customAppData: customAppData,
    );
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}

    var freedBytes = 0;
    for (final dir in _targetDirs(
      customCacheDir: customCacheDir,
      customAppData: customAppData,
    )) {
      freedBytes += _cleanFolderContents(dir);
    }
    final after = getCacheInfo(
      customCacheDir: customCacheDir,
      customAppData: customAppData,
    );
    final diff = before.sizeBytes - after.sizeBytes;
    final effective = freedBytes > diff ? freedBytes : diff;
    final freedMB =
        effective > 0 ? (effective / 1024 / 1024 * 100).round() / 100 : 0.0;
    return (
      freedMB: freedMB,
      currentMB: after.sizeMB,
    );
  }
}
