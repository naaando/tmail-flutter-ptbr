import 'package:jmap_dart_client/jmap/account_id.dart';
import 'package:jmap_dart_client/jmap/core/session/session.dart';
import 'package:rule_filter/rule_filter/capability_rule_filter.dart';
import 'package:rule_filter/sieve/capability_sieve.dart';
import 'package:tmail_ui_user/main/error/capability_validator.dart';

/// Server API behind the "Email rules" settings.
enum EmailRulesBackend {
  /// Linagora `Filter/get` and `Filter/set` (Twake Mail / TMail server).
  linagora,

  /// JMAP for Sieve (RFC 9661) with JMAP Blob (RFC 9404), e.g. Stalwart.
  sieve,

  none;

  /// The Linagora API keeps priority so servers that announce both behave
  /// exactly as before.
  static EmailRulesBackend resolve(Session? session, AccountId? accountId) {
    if (session == null || accountId == null) return EmailRulesBackend.none;
    if (capabilityRuleFilter.isSupported(session, accountId)) {
      return EmailRulesBackend.linagora;
    }
    if ([capabilitySieve, capabilityBlob].isSupported(session, accountId)) {
      return EmailRulesBackend.sieve;
    }
    return EmailRulesBackend.none;
  }

  bool get isSupported => this != EmailRulesBackend.none;

  bool get isSieve => this == EmailRulesBackend.sieve;
}
