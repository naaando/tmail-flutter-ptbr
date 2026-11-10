import 'package:equatable/equatable.dart';
import 'package:rule_filter/sieve/sieve_rules_codec.dart';

/// Why the Sieve rules cannot be changed from the webmail.
enum EmailRulesReadOnlyReason {
  /// The managed script was edited by another client (ManageSieve, admin UI).
  modifiedExternally,

  /// A script with the managed name exists but was not created by the webmail.
  nameConflict,
}

/// State of the server-side rules, reported only by the Sieve backend. The
/// Linagora backend has no equivalent and reports `null`.
class EmailRulesStatus with EquatableMixin {
  /// The managed script exists on the server.
  final bool hasManagedScript;

  /// The managed script is the active script, so the rules run on delivery.
  final bool isActive;

  /// Name of another active script that prevents activation (Sieve allows a
  /// single active script per account).
  final String? blockingScriptName;

  /// The blocking script is the one Stalwart creates for the automatic
  /// reply (`VacationResponse`).
  final bool blockedByVacation;

  final EmailRulesReadOnlyReason? readOnlyReason;

  /// Editor features unavailable because the server lacks the extension.
  final Set<SieveRuleFeature> unsupportedFeatures;

  /// The editor may offer the "stop processing further rules" option.
  final bool supportsStopProcessing;

  const EmailRulesStatus({
    required this.hasManagedScript,
    required this.isActive,
    this.blockingScriptName,
    this.blockedByVacation = false,
    this.readOnlyReason,
    this.unsupportedFeatures = const {},
    this.supportsStopProcessing = true,
  });

  bool get isReadOnly => readOnlyReason != null;

  bool get isBlocked => blockingScriptName != null;

  /// Saved rules that do not run and nothing prevents activating them.
  bool get canActivate =>
      hasManagedScript && !isActive && !isBlocked && !isReadOnly;

  @override
  List<Object?> get props => [
        hasManagedScript,
        isActive,
        blockingScriptName,
        blockedByVacation,
        readOnlyReason,
        unsupportedFeatures,
        supportsStopProcessing,
      ];
}
