import 'package:core/presentation/state/failure.dart';
import 'package:core/presentation/state/success.dart';

/// The vacation reply was turned on and paused the email rules (Stalwart runs
/// a single Sieve script per account).
class EmailRulesPausedByVacation extends UIState {}

/// The vacation reply was turned off and the email rules were activated again.
class EmailRulesResumedAfterVacation extends UIState {}

class SyncEmailRulesWithVacationFailure extends FeatureFailure {
  SyncEmailRulesWithVacationFailure(dynamic exception) : super(exception: exception);
}
