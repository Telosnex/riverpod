// Snippets are test code shown outside test/ on the docs site, so the
// test-only APIs they use (e.g. ProviderContainer.test) are expected here.
// ignore_for_file: unused_local_variable, invalid_use_of_visible_for_testing_member

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Some description', (tester) async {
    /* SNIPPET START */
    final container = tester.container();
    /* SNIPPET END */
  });
}
