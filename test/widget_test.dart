import 'package:flutter_test/flutter_test.dart';

import 'package:mario/ui/colors.dart';

void main() {
  test('Mario primary is the spec yellow', () {
    // Updated in 56083a8, which changed the brand yellow from 0xFFFFDE7A to
    // this without updating the assertion — the test has been red ever since.
    expect(MarioColors.primary.toARGB32(), 0xFFF2C94C);
  });
}
