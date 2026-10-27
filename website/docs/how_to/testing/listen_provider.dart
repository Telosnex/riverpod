// Snippets are test code shown outside test/ on the docs site, so the
// test-only APIs they use (e.g. ProviderContainer.test) are expected here.
// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

final provider = Provider((_) => 'Hello world');

void main() {
  test('Some description', () {
    final container = ProviderContainer.test();
    /* SNIPPET START */
    container.listen<String>(
      provider,
      (previous, next) {
        print('The provider changed from $previous to $next');
      },
    );
    /* SNIPPET END */
  });
}
