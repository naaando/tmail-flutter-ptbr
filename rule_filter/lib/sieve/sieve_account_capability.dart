import 'package:equatable/equatable.dart';
import 'package:jmap_dart_client/jmap/account_id.dart';
import 'package:jmap_dart_client/jmap/core/capability/default_capability.dart';
import 'package:jmap_dart_client/jmap/core/session/session.dart';
import 'package:rule_filter/sieve/capability_sieve.dart';

/// Account capability announced under `urn:ietf:params:jmap:sieve`
/// (RFC 9661, section 2).
class SieveAccountCapability with EquatableMixin {
  final int? maxSizeScriptName;
  final int? maxSizeScript;
  final int? maxNumberScripts;
  final Set<String> sieveExtensions;
  final String? implementation;

  const SieveAccountCapability({
    this.maxSizeScriptName,
    this.maxSizeScript,
    this.maxNumberScripts,
    this.sieveExtensions = const {},
    this.implementation,
  });

  factory SieveAccountCapability.fromJson(Map<String, dynamic> json) {
    int? asInt(Object? value) => value is num ? value.toInt() : null;
    final extensions = json['sieveExtensions'];
    return SieveAccountCapability(
      maxSizeScriptName: asInt(json['maxSizeScriptName']),
      maxSizeScript: asInt(json['maxSizeScript']),
      maxNumberScripts: asInt(json['maxNumberScripts']),
      sieveExtensions: extensions is List
          ? extensions.whereType<String>().map((e) => e.toLowerCase()).toSet()
          : const {},
      implementation: json['implementation'] as String?,
    );
  }

  /// Reads the account capability from the session, or `null` when the
  /// account does not announce JMAP for Sieve.
  static SieveAccountCapability? fromSession(
    Session session,
    AccountId accountId,
  ) {
    final capability =
        session.accounts[accountId]?.accountCapabilities[capabilitySieve];
    if (capability == null) return null;
    final accountJson = capability is DefaultCapability
        ? capability.properties ?? const <String, dynamic>{}
        : const <String, dynamic>{};
    // RFC 9661 puts `implementation` in the session-level capability, which
    // is where Stalwart announces it; the account capability has the rest.
    final sessionCapability = session.capabilities[capabilitySieve];
    final sessionJson = sessionCapability is DefaultCapability
        ? sessionCapability.properties ?? const <String, dynamic>{}
        : const <String, dynamic>{};
    return SieveAccountCapability.fromJson({
      if (sessionJson['implementation'] != null)
        'implementation': sessionJson['implementation'],
      ...accountJson,
    });
  }

  bool supportsExtension(String extension) =>
      sieveExtensions.contains(extension.toLowerCase());

  @override
  List<Object?> get props => [
        maxSizeScriptName,
        maxSizeScript,
        maxNumberScripts,
        sieveExtensions,
        implementation,
      ];
}
