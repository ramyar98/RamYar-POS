import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ramyar_pos/core/language.dart';
import 'package:ramyar_pos/services/app_localizations.dart' show allTranslations;

final File _report = File('build/translation_gaps.txt');

/// Guards the promise that every string in the app speaks all six languages:
///
///  1. Every key in the translation table must carry the five non-Kurdish
///     languages (badini, arabic, persian, english, turkish) - Kurdish is the
///     key itself, by design (`tr` returns the key verbatim in Kurdish).
///  2. Every `tr('…')` / `trp('…')` literal actually used in `lib` must exist
///     in the table; a lookup that falls through to the key shows raw Kurdish
///     on an English/Turkish/… device, which is precisely what must never
///     happen.
///
/// Runs against the real `allTranslations` map so a missing translation fails
/// the suite instead of silently shipping.
const Set<AppLanguage> _targets = {
  AppLanguage.badini,
  AppLanguage.arabic,
  AppLanguage.persian,
  AppLanguage.english,
  AppLanguage.turkish,
};

Iterable<File> _dartFiles(String dir) sync* {
  final entries = Directory(dir).listSync(followLinks: false);
  for (final e in entries) {
    if (e is Directory && !e.path.contains('gen')) {
      yield* _dartFiles(e.path);
    } else if (e is File && e.path.endsWith('.dart')) {
      yield e;
    }
  }
}

List<String> _trLiterals(String root) {
  final found = <String>[];
  // Catches `context.tr('…')`, `context.trp('…')`, but also the bare aliases
  // `final tr = context.tr;` / `final trp = context.trp;` used in a few widgets,
  // and keys that the formatter wrapped onto the line *after* the call. The
  // previous line-by-line, dot-only matcher missed both of those, so an
  // untranslated string could slip through the gate.
  final re = RegExp(
    r'''(?:\.|(?<![\w.]))(?:trp?)\(\s*(?:"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)')''',
    dotAll: true,
  );
  for (final file in _dartFiles(root)) {
    final text = file.readAsStringSync();
    for (final m in re.allMatches(text)) {
      final raw = m.group(1) ?? m.group(2);
      if (raw == null) continue;
      final key = raw
          .replaceAll(r"\'", "'")
          .replaceAll(r'\"', '"')
          .replaceAll(r'\$', r'$');
      final line = '\n'.allMatches(text.substring(0, m.start)).length + 1;
      found.add('${file.path}:$line  «$key»');
    }
  }
  return found;
}

void main() {
  group('translation table completeness', () {
    test('every key carries all five non-Kurdish languages', () {
      final map = allTranslations;
      final missing = <String, List<AppLanguage>>{};
      for (final entry in map.entries) {
        final absent = _targets
            .where((l) {
              final v = entry.value[l];
              return v == null || v.trim().isEmpty;
            })
            .toList();
        if (absent.isNotEmpty) missing[entry.key] = absent;
      }
      if (missing.isNotEmpty) {
        final lines = missing.entries
            .map((e) => '«${e.key}» -> missing ${e.value.map((l) => l.name).join(', ')}')
            .toList()
          ..sort();
        fail(
          '${lines.length} key(s) lack one or more translations:\n'
          '${lines.join('\n')}',
        );
      }
    });

    test('every tr()/trp() literal used in lib exists in the table', () {
      final map = allTranslations;
      final calls = _trLiterals('lib');
      final byKey = <String, List<String>>{};
      for (final call in calls) {
        final key = call.substring(
          call.lastIndexOf('«') + 1,
          call.lastIndexOf('»'),
        );
        byKey.putIfAbsent(key, () => []).add(call);
      }
      final unknown = byKey.keys.where((k) => !map.containsKey(k)).toList()
        ..sort();
      _report.parent.createSync(recursive: true);
      final buffer = StringBuffer()
        ..writeln('UNIQUE MISSING KEYS: ${unknown.length}')
        ..writeln();
      for (final key in unknown) {
        buffer.writeln('KEY: $key');
        for (final site in byKey[key]!) {
          buffer.writeln('   $site');
        }
        buffer.writeln();
      }
      _report.writeAsStringSync(buffer.toString());
      if (unknown.isNotEmpty) {
        fail(
          '${unknown.length} tr()/trp() key(s) have NO translation entry '
          '(details in build/translation_gaps.txt).',
        );
      }
    });
  });
}