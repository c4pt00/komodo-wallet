import 'package:rational/rational.dart';
import 'package:test/test.dart';
import 'package:web_dex/views/dex/dex_helpers.dart';

void testCompareToCex() {
  test('compare different prices', () {
    expect(compareToCex(1, 2, Rational.one), 100);
  });
}
