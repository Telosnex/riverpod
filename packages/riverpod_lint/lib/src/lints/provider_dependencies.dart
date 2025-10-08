import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/error/error.dart'
    hide
        // ignore: undefined_hidden_name, necessary to support lower analyzer version
        LintCode;
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/source/source.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_dart.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_analyzer_utils/riverpod_analyzer_utils.dart';

import '../imports.dart';
import '../object_utils.dart';
import '../riverpod_custom_lint.dart';

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

class _AnalysisResult {
  _AnalysisResult({
    required this.data,
    required this.message,
    required this.contextMessages,
  });

  final _Data data;
  final String message;
  final List<DiagnosticMessage> contextMessages;
}

extension on AccumulatedDependencyList {
  AstNode get target =>
      riverpod?.annotation.dependencyList?.node ??
      riverpod?.annotation.node ??
      dependencies?.dependencies.node ??
      node;
}

bool _shouldSkipList(AccumulatedDependencyList list) {
  if (list.overrides != null) return true;

  // If the State has an associated widget, we don't visit it.
  // The widget will already visit the state.
  if (list.node.safeCast<ClassDeclaration>()?.state?.findWidgetAst() != null) {
    return true;
  }

  return false;
}

_AnalysisResult? _analyzeDependencies(AccumulatedDependencyList list) {
  final usedDependencies = <_LocatedProvider>[];

  final visitor = _FindNestedDependency(
    list,
    onProvider: (locatedProvider, list, {required checkOverrides}) {
      final provider = locatedProvider.provider;
      if (provider is! GeneratorProviderDeclarationElement) return;
      if (!provider.isScoped) return;

      // Check if the provider is overridden. If it is, the provider doesn't
      // count towards the unused/missing dependencies
      if (checkOverrides && list.isSafelyAccessibleAfterOverrides(provider)) {
        return;
      }

      usedDependencies.add(locatedProvider);
    },
  );

  list.node.accept(visitor);

  var unusedDependencies = list.allDependencies
      ?.where(
        (dependency) =>
            !usedDependencies.any((e) => e.provider == dependency.provider),
      )
      .toList();
  final missingDependencies = usedDependencies
      .where(
        (dependency) =>
            list.allDependencies?.every(
              (e) => e.provider != dependency.provider,
            ) ??
            true,
      )
      .toSet();

  unusedDependencies ??= const [];
  if (unusedDependencies.isEmpty && missingDependencies.isEmpty) {
    return null;
  }

  final message = StringBuffer();
  if (unusedDependencies.isNotEmpty) {
    message.write('Unused dependencies: ');
    message.writeAll(unusedDependencies.map((e) => e.provider.name), ', ');
  }
  if (missingDependencies.isNotEmpty) {
    if (unusedDependencies.isNotEmpty) {
      message.write(' | ');
    }
    message.write('Missing dependencies: ');
    message.writeAll(missingDependencies.map((e) => e.provider.name), ', ');
  }

  final unit = list.node.thisOrAncestorOfType<CompilationUnit>();
  final Source? source = unit?.declaredFragment?.source;

  final contextMessages = <DiagnosticMessage>[
    for (final dependency in missingDependencies)
      if (source != null)
        _MyDiagnostic(
          message: dependency.provider.name,
          filePath: source.fullName,
          offset: dependency.node.offset,
          length: dependency.node.length,
        ),
  ];

  return _AnalysisResult(
    data: _Data(usedDependencies: usedDependencies, list: list),
    message: message.toString(),
    contextMessages: contextMessages,
  );
}

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
      if (_shouldSkipList(list)) return;
      if (list.riverpod == null) return;

      final analysis = _analyzeDependencies(list);
      if (analysis == null) return;

      reporter.atNode(
        list.target,
        _code,
        arguments: [analysis.message],
        contextMessages: analysis.contextMessages,
        data: analysis.data,
      );
    });
  }

  @override
  List<DartFix> getFixes() => [_ProviderDependenciesFix()];
}

class ScopedConsumerDependencies extends RiverpodLintRule {
  ScopedConsumerDependencies({
    required List<Glob> include,
    required List<Glob> exclude,
  }) : _include = List.unmodifiable(include),
       _exclude = List.unmodifiable(exclude),
       super(code: _code);

  static const _code = LintCode(
    name: 'scoped_consumer_dependencies',
    problemMessage: '{0}',
    errorSeverity: ErrorSeverity.INFO,
  );

  final List<Glob> _include;
  final List<Glob> _exclude;

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    final fileUri = resolver.source.uri;
    if (!_shouldLintFile(fileUri)) return;

    riverpodRegistry(context).addAccumulatedDependencyList((list) {
      if (_shouldSkipList(list)) return;
      if (list.riverpod != null) return;

      final analysis = _analyzeDependencies(list);
      if (analysis == null) return;

      reporter.atNode(
        list.target,
        _code,
        arguments: [analysis.message],
        contextMessages: analysis.contextMessages,
        data: analysis.data,
      );
    });
  }

  bool _shouldLintFile(Uri uri) {
    final candidates = _pathCandidatesForUri(uri);
    if (candidates.isEmpty) return false;

    if (_include.isNotEmpty) {
      final matchesInclude = candidates.any(
        (path) => _include.any((glob) => glob.matches(path)),
      );
      if (!matchesInclude) return false;
    }

    final matchesExclude = candidates.any(
      (path) => _exclude.any((glob) => glob.matches(path)),
    );
    return !matchesExclude;
  }

  @override
  List<DartFix> getFixes() => [_ProviderDependenciesFix()];
}

List<String> _pathCandidatesForUri(Uri uri) {
  String? resolved;
  try {
    resolved = uri.toFilePath();
  } catch (_) {
    resolved = uri.path;
  }

  if (resolved.isEmpty) return const [];

  final normalized = _normalizePath(resolved);
  final segments = normalized.split('/');

  final candidates = <String>{normalized};

  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    if (segment == 'lib' ||
        segment == 'test' ||
        segment == 'example' ||
        segment == 'bin' ||
        segment == 'tool') {
      candidates.add(segments.sublist(i).join('/'));
    }
  }

  return candidates.toList();
}

String _normalizePath(String path) {
  final normalized = path.replaceAll('\\', '/');
  return p.posix.normalize(normalized);
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

    final scopedDependencies = data.usedDependencies
        .map((e) => e.provider)
        .toSet();
    final newDependencies = scopedDependencies.isEmpty
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
