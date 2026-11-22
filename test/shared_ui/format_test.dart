import 'package:flutter_test/flutter_test.dart';
import 'package:personal_sender/shared_ui/format.dart';

void main() {
  test('formatBytes uses decimal units with one decimal place', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(999), '999 B');
    expect(formatBytes(1000), '1.0 KB');
    expect(formatBytes(18400), '18.4 KB');
    expect(formatBytes(12400000), '12.4 MB');
    expect(formatBytes(1500000000), '1.5 GB');
    expect(formatBytes(2500000000000), '2.5 TB');
  });
}
