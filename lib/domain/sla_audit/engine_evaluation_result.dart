import 'contractual_execution_state.dart';
import 'evaluation_trace.dart';

/// The deterministic output triplet structurally guaranteed by the Evaluation Engine.
class EngineEvaluationResult {
  /// The operational truth result (Execution State).
  final ContractualExecutionState executionState;

  /// The financial consequence, if generated during this evaluation step.
  final Object?
  financialSnapshot; // Utilizing Object? as a placeholder, requires actual ContractualFinancialSnapshot class

  /// The forensic investigative artifact explaining exactly why the engine reached these conclusions.
  final EvaluationTrace trace;

  const EngineEvaluationResult({
    required this.executionState,
    this.financialSnapshot,
    required this.trace,
  });
}
