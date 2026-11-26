import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'paths.dart';

class BossKeyService {
  BossKeyService._();

  static const _channel = MethodChannel('kimbox/boss_key');
  static const _fullscreenChannel = MethodChannel('kimbox/window_fullscreen');

  static String currentShortcut = 'Alt+Q';
  static bool enabled = true;
  static bool isHidden = false;
  static bool _wasFullscreenBeforeHide = false;

  static Future<void> Function()? onPauseForBossKey;
  static Future<void> Function()? onWakeFromBossKey;

  static void initHandler() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onBossKeyPressed') {
        await toggle();
      }
    });
  }

  static Future<void> loadAndRegister() async {
    try {
      final f = File(AppPaths.bossKeyFile);
      if (f.existsSync()) {
        final obj = jsonDecode(f.readAsStringSync());
        if (obj is Map) {
          final sc = (obj['shortcut'] ?? '').toString().trim();
          if (sc.isNotEmpty) currentShortcut = sc;
          enabled = obj['enabled'] != false;
        }
      }
    } catch (_) {}

    if (enabled) {
      await register(currentShortcut);
    }
  }

  static void _saveConfig() {
    try {
      File(AppPaths.bossKeyFile).parent.createSync(recursive: true);
      File(AppPaths.bossKeyFile).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'shortcut': currentShortcut,
          'enabled': enabled,
        }),
      );
    } catch (_) {}
  }

  static ({int modifiers, int vkCode})? parseAccelerator(String acc) {
    final parts = acc
        .split('+')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;

    var modifiers = 0;
    for (var i = 0; i < parts.length - 1; i++) {
      final p = parts[i].toLowerCase();
      if (p == 'alt') {
        modifiers |= 0x0001; // MOD_ALT
      } else if (p == 'ctrl' || p == 'control' || p == 'commandorcontrol') {
        modifiers |= 0x0002; // MOD_CONTROL
      } else if (p == 'shift') {
        modifiers |= 0x0004; // MOD_SHIFT
      } else if (p == 'meta' || p == 'win') {
        modifiers |= 0x0008; // MOD_WIN
      }
    }

    final main = parts.last.toUpperCase();
    int? vk;
    if (main.length == 1) {
      final c = main.codeUnitAt(0);
      if ((c >= 0x41 && c <= 0x5A) || (c >= 0x30 && c <= 0x39)) {
        vk = c;
      }
    } else if (RegExp(r'^F([1-9]|1[0-2])$').hasMatch(main)) {
      final n = int.parse(main.substring(1));
      vk = 0x70 + (n - 1); // VK_F1..VK_F12
    } else if (main == 'SPACE') {
      vk = 0x20;
    } else if (main == 'ESC' || main == 'ESCAPE') {
      vk = 0x1B;
    }
    if (vk == null) return null;
    return (modifiers: modifiers, vkCode: vk);
  }

  static Future<bool> register(String accelerator) async {
    final parsed = parseAccelerator(accelerator);
    if (parsed == null) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('register', {
            'modifiers': parsed.modifiers,
            'vkCode': parsed.vkCode,
          }) ??
          false;
      if (ok) currentShortcut = accelerator;
      return ok;
    } catch (_) {
      return false;
    }
  }

  static Future<({bool ok, String? error, String shortcut})> setBossKey(
      String accelerator) async {
    final parsed = parseAccelerator(accelerator);
    if (parsed == null) {
      return (
        ok: false,
        error: '快捷键格式不支持或无效: $accelerator',
        shortcut: currentShortcut,
      );
    }
    final old = currentShortcut;
    try {
      final ok = await _channel.invokeMethod<bool>('register', {
            'modifiers': parsed.modifiers,
            'vkCode': parsed.vkCode,
          }) ??
          false;
      if (ok) {
        currentShortcut = accelerator;
        enabled = true;
        _saveConfig();
        return (ok: true, error: null, shortcut: currentShortcut);
      } else {
        await register(old);
        return (
          ok: false,
          error: '快捷键 "$accelerator" 注册失败（已被系统或其他软件占用），请更换',
          shortcut: old,
        );
      }
    } catch (e) {
      return (
        ok: false,
        error: '快捷键注册失败: $e',
        shortcut: old,
      );
    }
  }

  static Future<void> setEnabledTemporary(bool value) async {
    enabled = value;
    if (enabled) {
      await register(currentShortcut);
    } else {
      try {
        await _channel.invokeMethod('unregister');
      } catch (_) {}
    }
  }

  static Future<void> toggle() async {
    final visible = await windowManager.isVisible();
    final minimized = await windowManager.isMinimized();
    if (visible && !minimized && !isHidden) {
      if (onPauseForBossKey != null) {
        await onPauseForBossKey!();
      }
      _wasFullscreenBeforeHide =
          await _fullscreenChannel.invokeMethod<bool>('isFullScreen') ?? false;
      isHidden = true;
      await windowManager.hide();
    } else {
      isHidden = false;
      if (minimized) await windowManager.restore();
      await windowManager.setAlwaysOnTop(true);
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setAlwaysOnTop(false);
      if (_wasFullscreenBeforeHide) {
        await _fullscreenChannel.invokeMethod('setFullScreen', {'isFullScreen': true});
      }
      if (onWakeFromBossKey != null) {
        await onWakeFromBossKey!();
      }
    }
  }
}

class WindowStateService {
  WindowStateService._();

  static const double defaultWidth = 1460;
  static const double defaultHeight = 920;
  static const double minWidth = 1024;
  static const double minHeight = 640;

  static Timer? _saveTimer;

  static ({
    double width,
    double height,
    double? x,
    double? y,
    bool maximized,
  }) load() {
    try {
      final f = File(AppPaths.windowStateFile);
      if (f.existsSync()) {
        final s = jsonDecode(f.readAsStringSync());
        if (s is Map) {
          final w = (s['width'] as num?)?.toDouble();
          final h = (s['height'] as num?)?.toDouble();
          if (w != null && h != null && w >= minWidth && h >= minHeight) {
            return (
              width: w.roundToDouble(),
              height: h.roundToDouble(),
              x: (s['x'] as num?)?.toDouble(),
              y: (s['y'] as num?)?.toDouble(),
              maximized: s['maximized'] == true,
            );
          }
        }
      }
    } catch (_) {}
    return (
      width: defaultWidth,
      height: defaultHeight,
      x: null,
      y: null,
      maximized: false,
    );
  }

  static void scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), saveNow);
  }

  static Future<void> saveNow() async {
    try {
      final bounds = await windowManager.getBounds();
      final max = await windowManager.isMaximized();
      final data = {
        'x': bounds.left.round(),
        'y': bounds.top.round(),
        'width': bounds.width.round(),
        'height': bounds.height.round(),
        'maximized': max,
      };
      File(AppPaths.windowStateFile).parent.createSync(recursive: true);
      File(AppPaths.windowStateFile).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(data),
      );
    } catch (_) {}
  }
}
