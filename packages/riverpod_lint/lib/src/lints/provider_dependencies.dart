import 'package:analyzer/error/error.dart'
    hide
        // ignore: undefined_hidden_name, necessary to support lower analyzer version
        LintCode;
import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:riverpod_analyzer_utils/riverpod_analyzer_utils.dart';

import 'dependencies_base.dart';

class ProviderDependencies extends DependenciesLintBase {
  const ProviderDependencies()
      : super(
          code: const LintCode(
            name: 'provider_dependencies',
            problemMessage: '{0}',
            errorSeverity: ErrorSeverity.WARNING,
          ),
        );

  @override
  bool shouldLint(AccumulatedDependencyList list) => list.riverpod != null;
}
