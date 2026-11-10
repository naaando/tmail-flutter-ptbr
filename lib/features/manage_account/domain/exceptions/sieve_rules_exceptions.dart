import 'package:tmail_ui_user/features/manage_account/domain/model/email_rules_status.dart';

/// Base class so the presentation layer can map every Sieve failure to a
/// specific message instead of a generic error.
sealed class SieveRulesException implements Exception {
  const SieveRulesException();
}

/// `ifInState` did not match: rules or vacation changed in another session.
class SieveRulesConflictException extends SieveRulesException {
  const SieveRulesConflictException();
}

class SieveRulesReadOnlyException extends SieveRulesException {
  final EmailRulesReadOnlyReason reason;

  const SieveRulesReadOnlyException(this.reason);
}

/// The server refused the script (`invalidScript`, `invalidSieve`, quota...).
class SieveScriptRejectedException extends SieveRulesException {
  final String type;
  final String? description;

  const SieveScriptRejectedException(this.type, {this.description});

  @override
  String toString() => 'SieveScriptRejectedException($type, $description)';
}

class SieveScriptTooLargeException extends SieveRulesException {
  final int size;
  final int maxSize;

  const SieveScriptTooLargeException(this.size, this.maxSize);
}

/// The server answered without error but the stored rules differ from the
/// ones sent. A 200 response alone is not taken as success.
class SieveRulesVerificationException extends SieveRulesException {
  const SieveRulesVerificationException();
}
