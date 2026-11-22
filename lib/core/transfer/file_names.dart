/// Filename cleanup for incoming files. Pure Dart.
library;

const _reserved = {
  'CON',
  'PRN',
  'AUX',
  'NUL',
  'COM1',
  'COM2',
  'COM3',
  'COM4',
  'COM5',
  'COM6',
  'COM7',
  'COM8',
  'COM9',
  'LPT1',
  'LPT2',
  'LPT3',
  'LPT4',
  'LPT5',
  'LPT6',
  'LPT7',
  'LPT8',
  'LPT9',
};

const _maxLength = 200;

/// Returns a name that is safe to create inside the receive folder:
/// no path parts, no `..`, no control or Windows-illegal characters, no
/// reserved device names, no trailing dots/spaces, and at most 200 chars.
String safeFileName(String input, {String fallback = 'file'}) {
  // Keep only the last path segment, whatever the separator.
  var name = input.split(RegExp(r'[\\/]')).last;
  if (RegExp(r'^[. ]*$').hasMatch(name)) return fallback;
  name = name.replaceAll(RegExp(r'[\x00-\x1f<>:"|?*]'), '_');
  name = name.replaceAll('..', '_');
  name = name.replaceAll(RegExp(r'[. ]+$'), '').replaceAll(RegExp(r'^\s+'), '');
  if (name.isEmpty || name == '.') return fallback;

  final dot = name.indexOf('.');
  final stem = dot < 0 ? name : name.substring(0, dot);
  if (_reserved.contains(stem.toUpperCase())) name = '_$name';

  if (name.length > _maxLength) {
    final ext = _extension(name);
    final keep = _maxLength - ext.length;
    name = keep > 0
        ? name.substring(0, keep) + ext
        : name.substring(0, _maxLength);
  }
  return name;
}

String _extension(String name) {
  final i = name.lastIndexOf('.');
  if (i <= 0 || name.length - i > 20) return '';
  return name.substring(i);
}

/// Returns [name] if [exists] says it is free, otherwise `stem (1).ext`,
/// `stem (2).ext`, … before the extension.
String uniqueName(String name, bool Function(String candidate) exists) {
  if (!exists(name)) return name;
  final ext = _extension(name);
  final stem = name.substring(0, name.length - ext.length);
  for (var n = 1; ; n++) {
    final candidate = '$stem ($n)$ext';
    if (!exists(candidate)) return candidate;
  }
}
