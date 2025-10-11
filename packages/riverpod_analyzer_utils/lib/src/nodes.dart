// ignore: unnecessary_library_name, used by the generator
library nodes;

import 'dart:async';
import 'dart:convert';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/syntactic_entity.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_provider.dart';
import 'package:analyzer_buffer/analyzer_buffer.dart';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:custom_lint_core/custom_lint_core.dart';
import 'package:meta/meta.dart';

import '../riverpod_analyzer_utils.dart';
import 'analyzer_utils.dart';
import 'argument_list_utils.dart';
import 'object_extensions.dart';
import 'riverpod_types.dart';

part 'nodes/widgets/state.dart';
part 'nodes/widgets/stateful_widget.dart';
part 'nodes/widgets/stateless_widget.dart';
part 'nodes/widgets/widget.dart';

part 'nodes/dependencies.dart';
part 'nodes/generated_providers/function.dart';
part 'nodes/manual_providers/provider.dart';
part 'nodes/generated_providers/notifier.dart';
part 'nodes/generated_providers/providers.dart';
part 'nodes/generated_providers/identifiers.dart';

part 'nodes/provider_for.dart';
part 'nodes/provider_or_family.dart';
part 'nodes/annotation.dart';
part 'nodes/provider_listenable.dart';
part 'nodes/ref_invocation.dart';
part 'nodes/widget_ref_invocation.dart';

part 'nodes/scopes/overrides.dart';
part 'nodes/scopes/provider_container.dart';
part 'nodes/scopes/provider_scope.dart';

part 'nodes.g.dart';

const _ast = Object();

extension RawTypeX on DartType {
  /// Returns whether this type is a `Raw` typedef from `package:riverpod_annotation`.
  bool get isRaw {
    final alias = this.alias;
    if (alias == null) return false;
    return alias.element2.name3 == 'Raw' &&
        isFromRiverpodAnnotation.isExactly(alias.element2);
  }
}

class _Cache<CachedT> {
  final _entries = <Object, _CacheEntry<CachedT>>{};

  CachedT call(
    Object key,
    CachedT Function() create, {
    CachedT Function()? onCycle,
  }) {
    final existing = _entries[key];
    if (existing != null) {
      if (!existing.isComputing) {
        return existing.value as CachedT;
      }

      if (onCycle != null) {
        final result = onCycle();
        existing.value = result;
        existing.isComputing = false;
        return result;
      }

      throw _CacheCircularDependencyError(key);
    }

    final entry = _CacheEntry<CachedT>(isComputing: true);
    _entries[key] = entry;
    var entryRemovedDuringCompute = false;
    late final CachedT result;
    try {
      final created = create();
      entry
        ..value = created
        ..isComputing = false;
      result = created;
    } finally {
      final current = _entries[key];
      if (current == null) {
        entryRemovedDuringCompute = true;
      } else if (current.isComputing) {
        _entries.remove(key);
      }
    }

    if (entryRemovedDuringCompute) {
      throw StateError('Cache entry was removed while computing "$key".');
    }

    return result;
  }
}

final class _CacheEntry<CachedT> {
  _CacheEntry({required this.isComputing, this.value});

  CachedT? value;
  bool isComputing;
}

final class _CacheCircularDependencyError extends Error {
  _CacheCircularDependencyError(this.key);

  final Object key;

  @override
  String toString() =>
      '_CacheCircularDependencyError: Circular dependency detected while computing "$key".';
}

Object _annotationCacheKey(ElementAnnotation annotation) => annotation;

Object _providerCacheKey(Element2 element) => element;
