import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/error/error.dart'
    hide
        // ignore: undefined_hidden_name, necessary to support lower analyzer version
        LintCode;
import 'package:analyzer/error/listener.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_dart.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:riverpod_analyzer_utils/riverpod_analyzer_utils.dart';

import '../imports.dart';
import '../object_utils.dart';
import '../riverpod_custom_lint.dart';

const _debugLoggingEnabled = bool.fromEnvironment(
  'RIVERPOD_LINT_DEBUG',
  defaultValue: false,
);

void _logLint(String message) {
  if (!_debugLoggingEnabled) return;
  // ignore: avoid_print
  print('[riverpod_lint][provider_dependencies] $message');
}

const _fixDependenciesPriority = 100;

class _LocatedProvider {
  _LocatedProvider(this.provider, this.node);

  final ProviderDeclarationElement provider;
  final AstNode node;
}

class _MyDiagnostic implements DiagnosticMessage {
  _MyDiagnostic({
    required this.message,
    required this.filePath,
    required this.length,
    required this.offset,
  });

  @override
  String? get url => null;

  final String message;

  @override
  final String filePath;

  @override
  final int length;

  @override
  final int offset;

  @override
  String messageText({required bool includeUrl}) => message;
}

class _FindNestedDependency extends RecursiveRiverpodAstVisitor {
  _FindNestedDependency(
    this.accumulatedDependencyList, {
    required this.onProvider,
    this.visitStates = false,
  });

  final AccumulatedDependencyList accumulatedDependencyList;
  final bool visitStates;
  final void Function(
    _LocatedProvider provider,
    AccumulatedDependencyList list, {
    required bool checkOverrides,
  })
  onProvider;

  _FindNestedDependency copyWith({
    AccumulatedDependencyList? accumulatedDependencyList,
    bool? visitStates,
    void Function(AccumulatedDependencyList child)? parentAddChild,
  }) {
    return _FindNestedDependency(
      accumulatedDependencyList ?? this.accumulatedDependencyList,
      onProvider: onProvider,
      visitStates: visitStates ?? this.visitStates,
    );
  }

  @override
  void visitComment(Comment node) {
    // Identifiers in comments shouldn't count.
  }

  @override
  void visitWidgetDeclaration(WidgetDeclaration node) {
    super.visitWidgetDeclaration(node);

    if (node is! StatefulWidgetDeclaration) return;

    final stateAst = node.findStateAst();

    // If targeting a StatefulWidget, we also need to check the state class.
    if (stateAst != null) {
      stateAst.node.accept(copyWith(visitStates: true));
    }
  }

  @override
  void visitStateDeclaration(StateDeclaration node) {
    if (!visitStates) return;

    super.visitStateDeclaration(node);
  }

  @override
  void visitProviderOverrideExpression(ProviderOverrideExpression node) {
    // Disable the lint for overrides. But only if the override isn't
    // `overrides: [provider]`.
    if (node.node.safeCast<Expression>()?.providerListenable != null) {
      super.visitProviderOverrideExpression(node);
      return;
    }
  }

  @override
  void visitProviderIdentifier(ProviderIdentifier node) {
    super.visitProviderIdentifier(node);

    onProvider(
      _LocatedProvider(node.providerElement, node.node),
      accumulatedDependencyList,
      checkOverrides: false,
    );
  }

  @override
  void visitAccumulatedDependencyList(AccumulatedDependencyList node) {
    node.node.visitChildren(copyWith(accumulatedDependencyList: node));
  }

  @override
  void visitIdentifierDependencies(IdentifierDependencies node) {
    super.visitIdentifierDependencies(node);

    if (_isSelfReference(node.dependencies)) return;

    if (node.dependencies.dependencies case final deps?) {
      for (final dep in deps) {
        onProvider(
          _LocatedProvider(dep, node.node),
          accumulatedDependencyList,
          checkOverrides: false,
        );
      }
    }
  }

  /// If an object references itself, so we don't count those dependencies
  /// as "used".
  bool _isSelfReference(DependenciesAnnotationElement node) {
    return node == accumulatedDependencyList.dependencies?.element;
  }

  @override
  void visitNamedTypeDependencies(NamedTypeDependencies node) {
    super.visitNamedTypeDependencies(node);

    if (_isSelfReference(node.dependencies)) return;

    final type = node.node.type;
    if (type == null) return;
    late final isWidget = widgetType.isAssignableFromType(type);

    if (node.dependencies.dependencies case final deps?) {
      for (final dep in deps) {
        onProvider(
          _LocatedProvider(dep, node.node),
          accumulatedDependencyList,
          // We check overrides only for Widget instances, as we can't guarantee
          // that non-widget instances use a "ref" that's a child of the overrides.
          checkOverrides: isWidget,
        );
      }
    }
  }
}

class _Data {
  _Data({required this.list, required this.usedDependencies});

  final AccumulatedDependencyList list;
  final List<_LocatedProvider> usedDependencies;
}

extension on AccumulatedDependencyList {
  AstNode get target =>
      riverpod?.annotation.dependencyList?.node ??
      riverpod?.annotation.node ??
      dependencies?.dependencies.node ??
      node;
}

const _maxDependencyCycleDepth = 64;

String _formatDependencyCycle(List<GeneratorProviderDeclarationElement> path) {
  if (path.isEmpty) return '';

  final buffer = StringBuffer();
  for (var i = 0; i < path.length; i++) {
    if (i > 0) buffer.write(' → ');
    buffer.write(path[i].name);
  }
  return buffer.toString();
}

AstNode? _dependencyNodeFor(
  AccumulatedDependencyList list,
  GeneratorProviderDeclarationElement provider,
) {
  final dependencies = list.allDependencies;
  if (dependencies == null) return null;

  for (final dependency in dependencies) {
    if (_sameProvider(dependency.provider, provider)) {
      return dependency.node;
    }
  }

  return null;
}

bool _sameProvider(
  ProviderDeclarationElement? a,
  ProviderDeclarationElement? b,
) {
  if (a == null || b == null) return false;
  return identical(a.element, b.element);
}

List<GeneratorProviderDeclarationElement>? _findDependencyCyclePath(
  GeneratorProviderDeclarationElement root,
) {
  final rootKey = _providerKey(root);
  if (rootKey == null) return null;

  final stack = <Object?>{rootKey};
  final path = <GeneratorProviderDeclarationElement>[root];

  return _findDependencyCyclePathRecursive(
    current: root,
    target: root,
    path: path,
    stack: stack,
    depth: 0,
  );
}

List<GeneratorProviderDeclarationElement>? _findDependencyCyclePathRecursive({
  required GeneratorProviderDeclarationElement current,
  required GeneratorProviderDeclarationElement target,
  required List<GeneratorProviderDeclarationElement> path,
  required Set<Object?> stack,
  required int depth,
}) {
  if (depth >= _maxDependencyCycleDepth) {
    _logLint(
      '    Max depth reached while searching cycle from ${target.name}. '
      'Current path: ${_formatDependencyCycle(path)}',
    );
    return null;
  }

  _logLint(
    '    Visiting ${current.name} (depth=$depth, path='
    '${_formatDependencyCycle(path)})',
  );

  final dependencies = current.annotation.dependencies;
  if (dependencies == null) return null;

  for (final dependency in dependencies) {
    final key = _providerKey(dependency);
    if (key == null) continue;

    if (_sameProvider(dependency, target)) {
      _logLint(
        '    Cycle completed: ${_formatDependencyCycle([...path, dependency])}',
      );
      return [...path, dependency];
    }

    if (stack.contains(key)) {
      _logLint('    Skipping ${dependency.name} (already on stack)');
      continue;
    }

    stack.add(key);
    path.add(dependency);

    final cycle = _findDependencyCyclePathRecursive(
      current: dependency,
      target: target,
      path: path,
      stack: stack,
      depth: depth + 1,
    );

    if (cycle != null) {
      _logLint(
        '    Returning cycle from ${dependency.name}: '
        '${_formatDependencyCycle(cycle)}',
      );
      return cycle;
    }

    path.removeLast();
    stack.remove(key);
    _logLint('    Backtracking from ${dependency.name}');
  }

  return null;
}

Object? _providerKey(ProviderDeclarationElement provider) => provider.element;

class ProviderDependencies extends RiverpodLintRule {
  const ProviderDependencies() : super(code: _code);

  static const _code = LintCode(
    name: 'provider_dependencies',
    problemMessage: '{0}',
    errorSeverity: ErrorSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    riverpodRegistry(context).addAccumulatedDependencyList((list) {
      // Ignore ProviderScopes. We only check annotations
      if (list.overrides != null) return;

      // If the State has an associated widget, we don't visit it.
      // The widget will already visit the state.
      if (list.node.safeCast<ClassDeclaration>()?.state?.findWidgetAst() !=
          null) {
        return;
      }

      final usedDependencies = <_LocatedProvider>[];

      final visitor = _FindNestedDependency(
        list,
        onProvider: (locatedProvider, list, {required checkOverrides}) {
          final provider = locatedProvider.provider;
          // if (!provider.isScoped) return;

          if (provider is GeneratorProviderDeclarationElement) {
            // Check if the provider is overridden. If it is, the provider doesn't
            // count towards the unused/missing dependencies
            if (checkOverrides &&
                list.isSafelyAccessibleAfterOverrides(provider)) {
              return;
            }

            usedDependencies.add(locatedProvider);
            return;
          }

          // Non-generator providers (e.g. manually declared providers) do not
          // participate in override checks. We still record them so that
          // @Dependencies on arbitrary nodes can be validated.
          usedDependencies.add(locatedProvider);
        },
      );

      list.node.accept(visitor);

      final providerElement = list.riverpod?.providerElement;
      final providerName =
          providerElement?.name ??
          list.riverpod?.annotation.element.name ??
          list.riverpod?.annotation.node.name?.toSource() ??
          list.node.toSource().split(RegExp('[({]')).first.trim();
      final locationUnit = list.node.thisOrAncestorOfType<CompilationUnit>();
      final locationSource = locationUnit?.declaredFragment?.source;
      final location =
          locationSource == null
              ? '<unknown location>'
              : '${locationSource.fullName}:${list.node.offset}';
      _logLint('Analyzing "$providerName" at $location');

      final providerElementDisplay =
          providerElement?.element?.displayName ??
          providerElement?.name ??
          '<none>';
      _logLint(
        '  Provider element: $providerElementDisplay '
        '(${providerElement?.runtimeType ?? 'null'})',
      );

      if (providerElement == null) {
        _logLint(
          '  No provider element associated with "$providerName". '
          'Node type: ${list.node.runtimeType}',
        );
      }

      final manualDependencies = list.dependencies?.dependencies?.values
          ?.map((e) => e.provider.name)
          .toList(growable: false);
      if (manualDependencies != null && manualDependencies.isNotEmpty) {
        _logLint('  Manual @Dependencies: ${manualDependencies.join(', ')}');
      }

      final declaredDependencyNames =
          providerElement != null
              ? (list.allDependencies
                      ?.map((e) => e.provider.name)
                      .toList(growable: false) ??
                  const <String>[])
              : (manualDependencies ?? const <String>[]);

      if (declaredDependencyNames.isEmpty) {
        _logLint('  Declared dependencies: <none>');
      } else {
        _logLint(
          '  Declared dependencies: ${declaredDependencyNames.join(', ')}',
        );
      }

      final usedDependencyNames =
          usedDependencies.map((e) => e.provider.name).toSet();
      if (usedDependencyNames.isEmpty) {
        _logLint('  Used dependencies: <none>');
      } else {
        _logLint(
          '  Used dependencies: '
          '${usedDependencyNames.join(', ')}',
        );
      }

      final declaredDependencySet = declaredDependencyNames.toSet();
      final missingDependencies = [
        for (final dependency in usedDependencies)
          if (!declaredDependencySet.contains(dependency.provider.name))
            dependency,
      ];
      final unusedDependencyNames = [
        for (final name in declaredDependencyNames)
          if (!usedDependencyNames.contains(name)) name,
      ];

      final cyclePath =
          providerElement == null
              ? null
              : _findDependencyCyclePath(providerElement);

      if (unusedDependencyNames.isEmpty && missingDependencies.isEmpty) {
        _logLint('  No unused or missing dependencies identified.');
      } else {
        if (unusedDependencyNames.isNotEmpty) {
          _logLint(
            '  Unused dependencies: '
            '${unusedDependencyNames.join(', ')}',
          );
        }
        if (missingDependencies.isNotEmpty) {
          _logLint(
            '  Missing dependencies: '
            '${missingDependencies.map((e) => e.provider.name).join(', ')}',
          );
        }
      }

      if (cyclePath != null) {
        _logLint(
          '  Circular dependency detected: '
          '${_formatDependencyCycle(cyclePath)}',
        );
      }

      if (unusedDependencyNames.isEmpty &&
          missingDependencies.isEmpty &&
          cyclePath == null) {
        _logLint('  No diagnostics emitted for "$providerName".');
        return;
      }

      final messageParts = <String>[];
      if (unusedDependencyNames.isNotEmpty) {
        messageParts.add(
          'Unused dependencies: '
          '${unusedDependencyNames.join(', ')}',
        );
      }
      if (missingDependencies.isNotEmpty) {
        messageParts.add(
          'Missing dependencies: '
          '${missingDependencies.map((e) => e.provider.name).join(', ')}',
        );
      }

      final cycleDescription =
          cyclePath == null ? null : _formatDependencyCycle(cyclePath);

      if (cycleDescription != null) {
        messageParts.add(
          cycleDescription.isEmpty
              ? 'Circular dependency detected'
              : 'Circular dependency: $cycleDescription',
        );
      }

      final message = messageParts.join(' | ');
      _logLint('  Emitting diagnostic: $message');

      late final unit =
          locationUnit ?? list.node.thisOrAncestorOfType<CompilationUnit>();
      late final source = unit?.declaredFragment?.source;

      final contextDiagnostics = <DiagnosticMessage>[
        for (final dependency in missingDependencies)
          if (source != null)
            _MyDiagnostic(
              message: dependency.provider.name,
              filePath: source.fullName,
              offset: dependency.node.offset,
              length: dependency.node.length,
            ),
      ];

      if (cyclePath != null && source != null) {
        final firstStep = cyclePath.length > 1 ? cyclePath[1] : null;
        final cycleNode =
            firstStep == null ? null : _dependencyNodeFor(list, firstStep);

        if (cycleNode != null) {
          contextDiagnostics.add(
            _MyDiagnostic(
              message:
                  cycleDescription == null || cycleDescription.isEmpty
                      ? 'Part of circular dependency'
                      : 'Part of circular dependency: $cycleDescription',
              filePath: source.fullName,
              offset: cycleNode.offset,
              length: cycleNode.length,
            ),
          );
        }

        if (firstStep != null && _sameProvider(providerElement, firstStep)) {
          for (final usage in usedDependencies) {
            if (_sameProvider(usage.provider, firstStep)) {
              contextDiagnostics.add(
                _MyDiagnostic(
                  message: 'Provider references itself here (part of cycle).',
                  filePath: source.fullName,
                  offset: usage.node.offset,
                  length: usage.node.length,
                ),
              );
            }
          }
        }
      }

      reporter.atNode(
        list.target,
        _code,
        arguments: [message],
        contextMessages: contextDiagnostics,
        data: _Data(usedDependencies: usedDependencies, list: list),
      );
    });
  }

  @override
  List<DartFix> getFixes() => [_ProviderDependenciesFix()];
}

class _ProviderDependenciesFix extends RiverpodFix {
  @override
  void run(
    CustomLintResolver resolver,
    ChangeReporter reporter,
    CustomLintContext context,
    AnalysisError analysisError,
    List<AnalysisError> others,
  ) {
    final data = analysisError.data;
    if (data is! _Data) return;

    final scopedDependencies =
        data.usedDependencies.map((e) => e.provider).toSet();
    final newDependencies =
        scopedDependencies.isEmpty
            ? null
            : '[${scopedDependencies.map((e) => e.name).join(', ')}]';

    final riverpodAnnotation = data.list.riverpod?.annotation;
    final dependencies = data.list.dependencies;

    if (newDependencies == null) {
      if (riverpodAnnotation == null && dependencies == null) {
        // No annotation found, so we can't fix anything.
        // This shouldn't happen but prevents errors in case of bad states.
        return;
      }

      final changeBuilder = reporter.createChangeBuilder(
        message: 'Remove "dependencies"',
        priority: _fixDependenciesPriority,
      );
      changeBuilder.addDartFileEdit((builder) {
        if (riverpodAnnotation case final riverpod?) {
          _riverpodRemoveDependencies(builder, riverpod);
        } else if (dependencies != null) {
          builder.addDeletion(data.list.dependencies!.node.sourceRange);
        }
      });

      return;
    }

    final dependencyList =
        data.list.riverpod?.annotation.dependencyList ??
        data.list.dependencies?.dependencies;

    if (dependencyList == null) {
      final changeBuilder = reporter.createChangeBuilder(
        message: 'Specify "dependencies"',
        priority: _fixDependenciesPriority,
      );
      changeBuilder.addDartFileEdit((builder) {
        if (riverpodAnnotation case final riverpod?) {
          _riverpodSpecifyDependencies(builder, riverpod, newDependencies);
        } else {
          final dep = builder.importDependenciesClass();
          builder.addSimpleInsertion(
            data.list.node.offset,
            '@$dep($newDependencies)\n',
          );
        }
      });

      return;
    }

    if (riverpodAnnotation == null && dependencies == null) {
      // No annotation found, so we can't fix anything.
      // This shouldn't happen but prevents errors in case of bad states.
      return;
    }
    final changeBuilder = reporter.createChangeBuilder(
      message: 'Update "dependencies"',
      priority: _fixDependenciesPriority,
    );
    changeBuilder.addDartFileEdit((builder) {
      if (riverpodAnnotation != null) {
        final dependencies = scopedDependencies.map((e) => e.name).join(', ');
        builder.addSimpleReplacement(
          dependencyList.node!.sourceRange,
          '[$dependencies]',
        );
      } else {
        final dep = builder.importDependenciesClass();
        builder.addSimpleReplacement(
          data.list.dependencies!.node.sourceRange,
          '@$dep($newDependencies)',
        );
      }
    });
  }

  void _riverpodRemoveDependencies(
    DartFileEditBuilder builder,
    RiverpodAnnotation riverpod,
  ) {
    if (riverpod.keepAliveNode == null) {
      final _riverpod = builder.importRiverpod();
      // Only "dependencies" is specified in the annotation.
      // So instead of @Riverpod(dependencies: []) -> @Riverpod(),
      // we can do @Riverpod(dependencies: []) -> @riverpod
      builder.addSimpleReplacement(riverpod.node.sourceRange, '@$_riverpod');
      return;
    }

    // Some parameters are specified in the annotation, so we remove
    // only the "dependencies" parameter.
    final dependenciesNode = riverpod.dependenciesNode!;
    final argumentList = riverpod.node.arguments!;

    builder.addDeletion(
      range.nodeInList(argumentList.arguments, dependenciesNode),
    );
  }

  void _riverpodSpecifyDependencies(
    DartFileEditBuilder builder,
    RiverpodAnnotation riverpod,
    String newDependencies,
  ) {
    final annotationArguments = riverpod.node.arguments;
    if (annotationArguments == null) {
      final _riverpod = builder.importRiverpodClass();
      // No argument list found. We are using the @riverpod annotation.
      builder.addSimpleReplacement(
        riverpod.node.sourceRange,
        '@$_riverpod(dependencies: $newDependencies)',
      );
    } else {
      // Argument list found, we are using the @Riverpod() annotation

      // We want to insert the "dependencies" parameter after the last
      final insertOffset =
          annotationArguments.arguments.lastOrNull?.end ??
          annotationArguments.leftParenthesis.end;

      builder.addSimpleInsertion(
        insertOffset,
        ', dependencies: $newDependencies',
      );
    }
  }
}
