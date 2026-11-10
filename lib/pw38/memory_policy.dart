import 'execution_identity_scope.dart';

/// Production observes memory without the experimental 2 GB rejection. The
/// observer ABI requires a positive signed-64-bit cap; zero is not an off switch.
const productionObservationCapBytes = 0x7fffffffffffffff;
const benchMemoryCapBytes = 2000000000;
const productionMemoryPolicy = 'production_observe_only_v1';
const benchMemoryPolicy = 'bench_2gb_enforced_v1';

int wholeMemoryCapBytes(Pw38ExecutionIdentityScope scope) =>
    scope.isIndependentTest
    ? benchMemoryCapBytes
    : productionObservationCapBytes;

String wholeMemoryPolicy(Pw38ExecutionIdentityScope scope) =>
    scope.isIndependentTest ? benchMemoryPolicy : productionMemoryPolicy;

void requireWholeMemoryPolicy(
  Map<String, dynamic> profile,
  Pw38ExecutionIdentityScope scope,
) {
  final policy = profile['memory_policy'];
  if (profile['physical_limit_bytes'] != wholeMemoryCapBytes(scope) ||
      (policy != wholeMemoryPolicy(scope) &&
          !(scope.isIndependentTest && policy == null))) {
    throw StateError(
      'Whole runtime memory policy differs from execution scope',
    );
  }
}
