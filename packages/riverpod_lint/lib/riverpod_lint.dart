import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:glob/glob.dart';

import 'src/assists/consumers/convert_to_stateful_base_widget.dart';
import 'src/assists/consumers/convert_to_stateless_base_widget.dart';
import 'src/assists/consumers/convert_to_widget_utils.dart';
import 'src/assists/providers/class_based_to_functional_provider.dart';
import 'src/assists/providers/functional_to_class_based_provider.dart';
import 'src/assists/wrap/wrap_with_consumer.dart';
import 'src/assists/wrap/wrap_with_provider_scope.dart';
import 'src/lints/async_value_nullable_pattern.dart';
import 'src/lints/avoid_build_context_in_providers.dart';
import 'src/lints/avoid_public_notifier_properties.dart';
import 'src/lints/avoid_ref_inside_state_dispose.dart';
import 'src/lints/functional_ref.dart';
import 'src/lints/missing_provider_scope.dart';
import 'src/lints/notifier_build.dart';
import 'src/lints/notifier_extends.dart';
import 'src/lints/only_use_keep_alive_inside_keep_alive.dart';
import 'src/lints/protected_notifier_properties.dart';
import 'src/lints/provider_dependencies.dart';
import 'src/lints/provider_parameters.dart';
import 'src/lints/riverpod_syntax_error.dart';
import 'src/lints/scoped_providers_should_specify_dependencies.dart';
import 'src/lints/unsupported_provider_value.dart';
import 'src/riverpod_custom_lint.dart';

PluginBase createPlugin() => _RiverpodPlugin();

class _RiverpodPlugin extends PluginBase {
  @override
  List<RiverpodLintRule> getLintRules(CustomLintConfigs configs) {
    final pluginOptions = _readPluginOptions(configs);
    final consumerConfig = _parseScopedConsumerConfig(
      pluginOptions['scoped_consumer_dependencies'],
    );

    return [
      const AsyncValueNullablePattern(),
      const AvoidBuildContextInProviders(),
      const OnlyUseKeepAliveInsideKeepAlive(),
      const AvoidPublicNotifierProperties(),
      const AvoidRefInsideStateDispose(),
      const FunctionalRef(),
      const MissingProviderScope(),
      const NotifierBuild(),
      const NotifierExtends(),
      const ProtectedNotifierProperties(),
      const ProviderDependencies(),
      if (consumerConfig.enabled)
        ScopedConsumerDependencies(
          include: consumerConfig.includes,
          exclude: consumerConfig.excludes,
        ),
      const ProviderParameters(),
      const RiverpodSyntaxError(),
      const ScopedProvidersShouldSpecifyDependencies(),
      const UnsupportedProviderValue(),
    ];
  }

  @override
  List<Assist> getAssists() => [
    WrapWithConsumer(),
    WrapWithProviderScope(),
    ...StatelessBaseWidgetType.values.map(
      (targetWidget) =>
          ConvertToStatelessBaseWidget(targetWidget: targetWidget),
    ),
    ...StatefulBaseWidgetType.values.map(
      (targetWidget) => ConvertToStatefulBaseWidget(targetWidget: targetWidget),
    ),
    FunctionalToClassBasedProvider(),
    ClassBasedToFunctionalProvider(),
  ];
}

class _ScopedConsumerConfig {
  const _ScopedConsumerConfig({
    required this.enabled,
    required this.includes,
    required this.excludes,
  });

  final bool enabled;
  final List<Glob> includes;
  final List<Glob> excludes;

  static const disabled = _ScopedConsumerConfig(
    enabled: false,
    includes: <Glob>[],
    excludes: <Glob>[],
  );
}

Map<String, Object?> _readPluginOptions(CustomLintConfigs configs) {
  final dynamic dynamicConfigs = configs;

  try {
    // ignore: avoid_dynamic_calls
    final forPlugin = dynamicConfigs.forPlugin;
    if (forPlugin is Function) {
      final result = forPlugin('riverpod_lint');
      if (result is Map<String, Object?>) {
        return result;
      }
    }
  } catch (_) {
    // Fall back to other discovery mechanisms.
  }

  try {
    // ignore: avoid_dynamic_calls
    final pluginConfigs = dynamicConfigs.pluginConfigs;
    if (pluginConfigs is Map) {
      final options = pluginConfigs['riverpod_lint'];
      if (options is Map<String, Object?>) {
        return options;
      }
    }
  } catch (_) {
    // No configuration available.
  }

  return const {};
}

_ScopedConsumerConfig _parseScopedConsumerConfig(Object? raw) {
  if (raw == null) {
    return _ScopedConsumerConfig.disabled;
  }

  if (raw is bool) {
    if (!raw) return _ScopedConsumerConfig.disabled;
    return const _ScopedConsumerConfig(
      enabled: true,
      includes: <Glob>[],
      excludes: <Glob>[],
    );
  }

  if (raw is Map) {
    final enabled = raw['enabled'] == true;
    if (!enabled) return _ScopedConsumerConfig.disabled;

    final includes = _parseGlobList(raw['include']);
    final excludes = _parseGlobList(raw['exclude']);

    return _ScopedConsumerConfig(
      enabled: true,
      includes: List.unmodifiable(includes),
      excludes: List.unmodifiable(excludes),
    );
  }

  return _ScopedConsumerConfig.disabled;
}

List<Glob> _parseGlobList(Object? raw) {
  if (raw == null) return const <Glob>[];

  if (raw is String) {
    final glob = _tryCreateGlob(raw);
    return glob == null ? const <Glob>[] : <Glob>[glob];
  }

  if (raw is Iterable) {
    final globs = <Glob>[];
    for (final entry in raw) {
      if (entry is! String) continue;
      final glob = _tryCreateGlob(entry);
      if (glob != null) globs.add(glob);
    }
    return globs;
  }

  return const <Glob>[];
}

Glob? _tryCreateGlob(String pattern) {
  try {
    return Glob(pattern);
  } catch (_) {
    return null;
  }
}
