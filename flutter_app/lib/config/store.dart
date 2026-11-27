/// Data-path resolution, atomic persistence and load/save entry points.
///
/// Ported from the C++ reference: `AI_USAGE_DATA_DIR` override first, then a
/// writable `data/` directory next to the executable (portable), then the
/// per-user directory. Writes rotate the previous file to `.bak` through a
/// `.tmp` temporary file and recover from `.bak` when the primary file is
/// unreadable.
library;

import 'dart:io';

import '../domain/model.dart';
import '../domain/validate.dart';
import 'settings.dart';
import 'settings_json.dart';
import 'validation.dart';

/// Per-user data root: `%LOCALAPPDATA%\AIUsageMonitor` on Windows,
/// `$XDG_DATA_HOME/ai-usage-monitor` or `$HOME/.local/share/ai-usage-monitor`
/// on Linux.
String userDataRoot() {
  if (Platform.isWindows) {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.isNotEmpty) {
      return '$localAppData\\AIUsageMonitor';
    }
  } else {
    final xdg = Platform.environment['XDG_DATA_HOME'];
    if (xdg != null && xdg.isNotEmpty) return '$xdg/ai-usage-monitor';
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) return '$home/.local/share/ai-usage-monitor';
  }
  final temp = Directory.systemTemp.path;
  final separator = Platform.isWindows ? '\\' : '/';
  return '$temp${separator}ai-usage-monitor';
}

String? _dataDirectoryOverride() {
  final value = Platform.environment['AI_USAGE_DATA_DIR'];
  if (value == null || value.isEmpty) return null;
  return value;
}

bool _isWritableDirectory(String path) {
  try {
    final directory = Directory(path);
    if (!directory.existsSync()) return false;
    final probe = File('$path${Platform.pathSeparator}.write-test');
    probe.writeAsStringSync('ok', flush: true);
    probe.deleteSync();
    return true;
  } catch (_) {
    return false;
  }
}

/// Resolves the data paths with the reference's precedence.
DataPaths resolveDataPaths(String executablePath, {String? Function()? perUserRoot}) {
  final separator = Platform.pathSeparator;
  final overrideRoot = _dataDirectoryOverride();
  if (overrideRoot != null) {
    Directory(overrideRoot).createSync(recursive: true);
    return DataPaths(
      root: overrideRoot,
      settings: '$overrideRoot${separator}settings.json',
      cache: '$overrideRoot${separator}cache.json',
      portable: false,
    );
  }

  final executableDirectory = File(executablePath).parent.path;
  final root = '$executableDirectory${separator}data';
  var portable = true;
  try {
    Directory(root).createSync(recursive: true);
    portable = _isWritableDirectory(root);
  } catch (_) {
    portable = false;
  }
  var resolvedRoot = root;
  if (!portable) {
    final locations = perUserRoot ?? userDataRoot;
    resolvedRoot = locations() ?? userDataRoot();
    Directory(resolvedRoot).createSync(recursive: true);
  }
  return DataPaths(
    root: resolvedRoot,
    settings: '$resolvedRoot${separator}settings.json',
    cache: '$resolvedRoot${separator}cache.json',
    portable: portable,
  );
}

/// Writes [content] to [path] atomically: temporary file first, then rotate
/// the previous file to `.bak`, then rename.
void atomicWrite(String path, String content) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  final temporary = '$path.tmp';
  final backup = '$path.bak';
  final temporaryFile = File(temporary);
  temporaryFile.writeAsStringSync(content, flush: true);
  final backupFile = File(backup);
  if (backupFile.existsSync()) {
    try {
      backupFile.deleteSync();
    } on FileSystemException catch (error) {
      temporaryFile.deleteSync();
      throw FileSystemException('cannot rotate backup file', backup, error.osError);
    }
  }
  if (file.existsSync()) {
    try {
      file.renameSync(backup);
    } on FileSystemException catch (error) {
      temporaryFile.deleteSync();
      throw FileSystemException('cannot rotate current file', path, error.osError);
    }
  }
  try {
    temporaryFile.renameSync(path);
  } on FileSystemException catch (error) {
    final restored = File(backup);
    if (restored.existsSync()) {
      try {
        restored.renameSync(path);
      } catch (_) {}
    }
    throw FileSystemException('cannot replace file atomically', path, error.osError);
  }
}

dynamic _readJson(String path) {
  try {
    return decodeJson(File(path).readAsStringSync());
  } on FileSystemException {
    throw FileSystemException('cannot open $path', path);
  }
}

/// Loads settings from [paths], recovering the `.bak` copy when the primary
/// file is unreadable and reporting recovery.
LoadSettingsResult loadSettings(DataPaths paths) {
  final settingsFile = File(paths.settings);
  if (!settingsFile.existsSync()) {
    return LoadSettingsResult(settings: Settings());
  }
  try {
    final settings = settingsFromJson(_readJson(paths.settings), validate: _validated);
    return LoadSettingsResult(settings: settings);
  } catch (currentError) {
    final backup = File('${paths.settings}.bak');
    if (!backup.existsSync()) rethrow;
    final settings = settingsFromJson(_readJson(backup.path), validate: _validated);
    return LoadSettingsResult(
      settings: settings,
      recoveredBackup: true,
      warning: 'Recovered settings backup after: $currentError',
    );
  }
}

Settings _validated(Settings settings) {
  final error = validateSettings(settings);
  if (error != null) throw FormatException(error);
  return settings;
}

/// Validates and writes settings atomically.
void saveSettings(DataPaths paths, Settings settings) {
  final error = validateSettings(settings);
  if (error != null) throw FormatException(error);
  atomicWrite(paths.settings, encodeSettings(settings));
}

/// Loads cached snapshots, falling back to `.bak` and starting empty rather
/// than failing to launch.
List<ProviderSnapshot> loadCache(DataPaths paths) {
  final cacheFile = File(paths.cache);
  if (!cacheFile.existsSync()) return [];
  try {
    return cacheFromJson(_readJson(paths.cache));
  } catch (_) {
    final backup = File('${paths.cache}.bak');
    if (!backup.existsSync()) return [];
    try {
      return cacheFromJson(_readJson(backup.path));
    } catch (_) {
      return [];
    }
  }
}

/// Saves snapshots to cache.json, filtering out invalid or metric-less
/// snapshots exactly like the reference.
void saveCache(DataPaths paths, List<ProviderSnapshot> snapshots) {
  final valid = [
    for (final snapshot in snapshots)
      if (validateSnapshot(snapshot).valid) snapshot,
  ];
  atomicWrite(paths.cache, encodeCache(valid));
}