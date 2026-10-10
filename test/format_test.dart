import 'package:flutter_test/flutter_test.dart';
import 'package:mssh/util/format.dart';

void main() {
  group('joinPath', () {
    test('joins under root', () => expect(joinPath('/', 'etc'), '/etc'));
    test('joins nested',
        () => expect(joinPath('/home/k', 'a.txt'), '/home/k/a.txt'));
    test('handles trailing slash',
        () => expect(joinPath('/home/k/', 'a'), '/home/k/a'));
  });

  group('parentPath', () {
    test('root stays root', () => expect(parentPath('/'), '/'));
    test('file parent', () => expect(parentPath('/home/k/a.txt'), '/home/k'));
    test('top level dir', () => expect(parentPath('/etc'), '/'));
    test('trailing slash', () => expect(parentPath('/home/k/'), '/home'));
  });

  group('humanSize', () {
    test('bytes', () => expect(humanSize(512), '512 B'));
    test('kilobytes', () => expect(humanSize(2048), '2.0 KB'));
    test('megabytes', () => expect(humanSize(5 * 1024 * 1024), '5.0 MB'));
  });

  group('looksBinary', () {
    test('plain text is not binary',
        () => expect(looksBinary('hello\nworld'.codeUnits), isFalse));
    test('a NUL byte means binary', () => expect(looksBinary([1, 2, 0, 3]), isTrue));
  });
}
