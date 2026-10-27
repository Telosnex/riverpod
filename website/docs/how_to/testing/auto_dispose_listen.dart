// Snippets are test code shown outside test/ on the docs site, so the
// test-only APIs they use (e.g. ProviderContainer.test) are expected here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

final provider = Provider((_) => 'Hello world');

void main() {
  test('Some description', () {
    final container = ProviderContainer.test();
    /* SNIPPET START */
    final subscription = container.listen<String>(provider, (_, _) {});

    expect(
      // {@template read}
      // Equivalent to `container.read(provider)`
      // But the provider will not be disposed unless "subscription" is disposed.
      // {@endtemplate}
      subscription.read(),
      'Some value',
    );
    /* SNIPPET END */
  });
}
