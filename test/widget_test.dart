import 'package:flutter_test/flutter_test.dart';

import 'package:mario/ui/colors.dart';

void main() {
  test('Mario primary is the spec yellow', () {
    expect(MarioColors.primary.toARGB32(), 0xFFFFDE7A);
  });
}
