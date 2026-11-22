import 'package:flutter_test/flutter_test.dart';
import 'package:personal_sender/core/transfer/file_names.dart';

void main() {
  group('safeFileName', () {
    test('strips traversal and separators', () {
      expect(safeFileName(r'..\..\evil.exe'), 'evil.exe');
      expect(safeFileName('/etc/passwd'), 'passwd');
      expect(safeFileName('a/../b.txt'), 'b.txt');
      expect(safeFileName('..'), 'file');
    });

    test('reserved Windows names', () {
      expect(safeFileName('CON.txt'), '_CON.txt');
      expect(safeFileName('nul'), '_nul');
      expect(safeFileName('com1.tar.gz'), '_com1.tar.gz');
      expect(safeFileName('console.txt'), 'console.txt');
    });

    test('empty and junk names', () {
      expect(safeFileName(''), 'file');
      expect(safeFileName('   '), 'file');
      expect(safeFileName('...'), 'file');
      expect(safeFileName('a<b>:c?.txt'), 'a_b__c_.txt');
      expect(safeFileName('name. '), 'name');
    });

    test('trims length but keeps extension', () {
      final n = safeFileName('${'a' * 500}.jpg');
      expect(n.length, 200);
      expect(n.endsWith('.jpg'), isTrue);
    });

    test('normal names are untouched', () {
      expect(safeFileName('photo (1).jpg'), 'photo (1).jpg');
    });
  });

  group('uniqueName', () {
    test('free name is returned as is', () {
      expect(uniqueName('photo.jpg', (_) => false), 'photo.jpg');
    });

    test('duplicates get (1), (2) before the extension', () {
      final taken = {'photo.jpg', 'photo (1).jpg'};
      expect(uniqueName('photo.jpg', taken.contains), 'photo (2).jpg');
    });

    test('no extension and dotfiles', () {
      expect(uniqueName('notes', {'notes'}.contains), 'notes (1)');
      expect(uniqueName('.env', {'.env'}.contains), '.env (1)');
    });
  });
}
