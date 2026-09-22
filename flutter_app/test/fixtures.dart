import 'dart:io';

/// Read-only access to the reference application's shared test fixtures.
///
/// The fixtures live in the C++ test tree (`../tests/fixtures/` relative to
/// `flutter_app/`) and are never modified by this package. The harness copies
/// nothing and only reads bytes, mirroring the reference's fixture use.
class Fixtures {
  Fixtures._();

  /// Resolves the fixture directory from the current package location.
  static Directory? locate() {
    var dir = Directory.current;
    for (var i = 0; i < 6; i++) {
      final candidate = Directory('${dir.path}${Platform.pathSeparator}tests${Platform.pathSeparator}fixtures');
      if (candidate.existsSync()) return candidate;
      final parent = dir.parent;
      if (parent.path == dir.path) return null;
      dir = parent;
    }
    return null;
  }

  /// Reads a fixture as UTF-8 text. Throws when the fixture tree is absent.
  static String read(String name) {
    final root = locate();
    if (root == null) {
      throw StateError('tests/fixtures directory not found from ${Directory.current.path}');
    }
    return File('${root.path}${Platform.pathSeparator}$name').readAsStringSync();
  }

  /// Reads a fixture as raw bytes.
  static List<int> readBytes(String name) {
    final root = locate();
    if (root == null) {
      throw StateError('tests/fixtures directory not found from ${Directory.current.path}');
    }
    return File('${root.path}${Platform.pathSeparator}$name').readAsBytesSync();
  }
}