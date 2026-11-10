import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:jmap_dart_client/jmap/core/id.dart';
import 'package:rule_filter/rule_filter/rule_condition.dart';
import 'package:rule_filter/rule_filter/rule_condition_group.dart';
import 'package:rule_filter/rule_filter/rule_id.dart';
import 'package:rule_filter/rule_filter/tmail_rule.dart';
import 'package:rule_filter/sieve/sieve_account_capability.dart';

/// Name of the Sieve script owned by the webmail. Any other script is never
/// read as rules nor changed.
const String managedSieveScriptName = 'twake-mail-rules';

/// Prefix of the comment line that carries the visual rules as JSON. The rest
/// of the script is generated from it, so the pair is the source of truth.
const String managedSieveMetadataPrefix = '# twake-mail-rules: ';

const String unicodeCaseMapComparator = 'i;unicode-casemap';
const String asciiCaseMapComparator = 'i;ascii-casemap';

/// Mailbox used when a rule points to a mailbox id that no longer exists.
/// `fileinto :mailboxid` falls back to this name, so mail is never lost.
const String fallbackMailboxName = 'INBOX';

/// Sieve extensions an action needs. The editor uses this to disable options
/// the server does not support instead of dropping them silently.
enum SieveRuleFeature {
  moveToMailbox({'fileinto', 'mailboxid'}),
  setFlags({'imap4flags'}),
  discard({});

  final Set<String> extensions;

  const SieveRuleFeature(this.extensions);

  bool isSupportedBy(SieveAccountCapability capability) =>
      extensions.every(capability.supportsExtension);
}

class SieveRulesDocument with EquatableMixin {
  static const int currentVersion = 1;

  final String comparator;
  final List<TMailRule> rules;

  const SieveRulesDocument({required this.comparator, required this.rules});

  @override
  List<Object?> get props => [comparator, rules];
}

enum ManagedScriptIntegrity {
  /// Script content equals what the webmail generates from its metadata.
  intact,

  /// Metadata missing, unreadable or the code was changed by another client.
  modifiedExternally,
}

class ParsedManagedScript with EquatableMixin {
  final ManagedScriptIntegrity integrity;
  final SieveRulesDocument? document;

  const ParsedManagedScript(this.integrity, this.document);

  bool get isIntact => integrity == ManagedScriptIntegrity.intact;

  @override
  List<Object?> get props => [integrity, document];
}

class SieveRuleNotRepresentableException implements Exception {
  final String ruleName;
  final String reason;

  const SieveRuleNotRepresentableException(this.ruleName, this.reason);

  @override
  String toString() =>
      'SieveRuleNotRepresentableException(rule: $ruleName, reason: $reason)';
}

class SieveExtensionNotSupportedException implements Exception {
  final Set<String> missingExtensions;

  const SieveExtensionNotSupportedException(this.missingExtensions);

  @override
  String toString() =>
      'SieveExtensionNotSupportedException(missing: $missingExtensions)';
}

/// Converts the visual rules into a Sieve script and back.
///
/// The conversion back never interprets Sieve code: it reads the JSON stored
/// in the metadata comment and accepts it only when regenerating the script
/// from it yields exactly the stored content. Anything else is reported as
/// [ManagedScriptIntegrity.modifiedExternally] and kept untouched.
class SieveRulesCodec {
  const SieveRulesCodec();

  /// Picks the comparator once, when the script is first written. It is
  /// stored in the metadata, so regenerating the script stays deterministic.
  String chooseComparator(SieveAccountCapability capability) {
    final implementation = capability.implementation?.toLowerCase() ?? '';
    final supportsUnicode =
        capability.supportsExtension('comparator-$unicodeCaseMapComparator') ||
            // Stalwart compiles `i;unicode-casemap` without announcing it in
            // `sieveExtensions` (checked against v0.16).
            implementation.startsWith('stalwart');
    return supportsUnicode ? unicodeCaseMapComparator : asciiCaseMapComparator;
  }

  /// Extensions the generated script declares in `require`, in a stable
  /// order. `mailbox` is added when announced because Stalwart rejects
  /// `:mailboxid` without it.
  Set<String> requiredExtensions(
    SieveRulesDocument document, {
    SieveAccountCapability? capability,
  }) {
    final required = <String>{};
    for (final rule in document.rules.where((rule) => rule.isEnabled)) {
      final action = rule.action;
      if (action.reject == true) continue;
      if (action.appendIn.mailboxIds.isNotEmpty) {
        required.addAll(SieveRuleFeature.moveToMailbox.extensions);
        if (capability == null || capability.supportsExtension('mailbox')) {
          required.add('mailbox');
        }
      }
      if (_flagsOf(rule).isNotEmpty) {
        required.addAll(SieveRuleFeature.setFlags.extensions);
      }
    }
    if (document.comparator != asciiCaseMapComparator &&
        document.comparator != 'i;octet' &&
        capability != null &&
        capability.supportsExtension('comparator-${document.comparator}')) {
      required.add('comparator-${document.comparator}');
    }
    final ordered = required.toList()..sort();
    return ordered.toSet();
  }

  /// Throws [SieveExtensionNotSupportedException] when the script would need
  /// an extension the account does not announce.
  void ensureSupported(
    SieveRulesDocument document,
    SieveAccountCapability capability,
  ) {
    final missing = requiredExtensions(document, capability: capability)
        .where((extension) => !capability.supportsExtension(extension))
        .toSet();
    if (missing.isNotEmpty) {
      throw SieveExtensionNotSupportedException(missing);
    }
  }

  String generate(
    SieveRulesDocument document, {
    SieveAccountCapability? capability,
  }) {
    final lines = <String>[
      '# Twake Mail: regras de e-mail gerenciadas pelo webmail.',
      '# Altere pelo webmail. Edições manuais deixam as regras somente leitura.',
      '$managedSieveMetadataPrefix${jsonEncode(_metadataOf(document))}',
    ];

    final required = requiredExtensions(document, capability: capability);
    if (required.isNotEmpty) {
      lines.add('require [${required.map(_quote).join(', ')}];');
    }

    for (var index = 0; index < document.rules.length; index++) {
      final rule = document.rules[index];
      lines.add('');
      if (!rule.isEnabled) {
        lines.add('# Regra ${index + 1}: desativada');
        continue;
      }
      lines.add('# Regra ${index + 1}');
      lines.add('if ${_testOf(rule, document.comparator)} {');
      for (final command in _commandsOf(rule)) {
        lines.add('    $command');
      }
      lines.add('}');
    }

    return '${lines.join('\r\n')}\r\n';
  }

  ParsedManagedScript parse(String content) {
    final metadataLine = _normalize(content)
        .split('\n')
        .where((line) => line.startsWith(managedSieveMetadataPrefix))
        .firstOrNull;
    if (metadataLine == null) {
      return const ParsedManagedScript(
        ManagedScriptIntegrity.modifiedExternally,
        null,
      );
    }

    final SieveRulesDocument document;
    try {
      document = _documentOf(
        jsonDecode(metadataLine.substring(managedSieveMetadataPrefix.length))
            as Map<String, dynamic>,
      );
    } catch (_) {
      return const ParsedManagedScript(
        ManagedScriptIntegrity.modifiedExternally,
        null,
      );
    }

    // Without the account capability the `require` line may differ only by
    // optional entries, so compare against both variants.
    final candidates = {
      _normalize(generate(document)),
      _normalize(generate(
        document,
        capability: _capabilityAnnouncing(content),
      )),
    };
    final integrity = candidates.contains(_normalize(content))
        ? ManagedScriptIntegrity.intact
        : ManagedScriptIntegrity.modifiedExternally;
    return ParsedManagedScript(integrity, document);
  }

  /// Rebuilds a capability containing exactly the extensions the script
  /// requires, so optional `require` entries do not break the comparison.
  SieveAccountCapability _capabilityAnnouncing(String content) {
    final requireLine = _normalize(content)
        .split('\n')
        .where((line) => line.startsWith('require ['))
        .firstOrNull;
    final extensions = RegExp(r'"([^"\\]*)"')
        .allMatches(requireLine ?? '')
        .map((match) => match.group(1)!)
        .toSet();
    return SieveAccountCapability(sieveExtensions: extensions);
  }

  Map<String, dynamic> _metadataOf(SieveRulesDocument document) {
    return {
      'v': SieveRulesDocument.currentVersion,
      'cmp': document.comparator,
      'rules': document.rules.map((rule) {
        final json = rule.withoutLegacyCondition().toJson()..remove('id');
        return {
          ...json,
          'enabled': rule.isEnabled,
          'stop': rule.stopProcessing,
        };
      }).toList(),
    };
  }

  SieveRulesDocument _documentOf(Map<String, dynamic> json) {
    if (json['v'] != SieveRulesDocument.currentVersion) {
      throw FormatException('Unsupported metadata version: ${json['v']}');
    }
    final rules = (json['rules'] as List<dynamic>).asMap().entries.map((entry) {
      final ruleJson = Map<String, dynamic>.from(entry.value as Map)
        ..['id'] = entry.key.toString();
      return TMailRule.fromJson(ruleJson).copyWith(
        id: RuleId(id: Id(entry.key.toString())),
        isEnabled: ruleJson['enabled'] != false,
        stopProcessing: ruleJson['stop'] == true,
      );
    }).toList();
    return SieveRulesDocument(
      comparator: json['cmp'] as String,
      rules: rules,
    );
  }

  String _testOf(TMailRule rule, String comparator) {
    final group = rule.conditionGroup;
    final conditions = group?.conditions ??
        [if (rule.condition != null) rule.condition!];
    if (conditions.isEmpty) {
      throw SieveRuleNotRepresentableException(rule.name, 'no condition');
    }
    final tests =
        conditions.map((condition) => _conditionTest(condition, comparator));
    final combiner = group?.conditionCombiner == ConditionCombiner.OR
        ? 'anyof'
        : 'allof';
    return '$combiner(${tests.join(', ')})';
  }

  String _conditionTest(RuleCondition condition, String comparator) {
    final headers = switch (condition.field) {
      Field.from => ['from'],
      Field.to => ['to'],
      Field.cc => ['cc'],
      Field.recipient => ['to', 'cc'],
      Field.subject => ['subject'],
    };
    final isAddressField = condition.field != Field.subject;
    final headerList = _stringList(headers);
    final value = _quote(condition.value);
    final cmp = ':comparator ${_quote(comparator)}';

    String contains() => 'header $cmp :contains $headerList $value';
    String equals() => isAddressField
        // Matches either one of the addresses or the whole header value.
        ? 'anyof(address :all $cmp :is $headerList $value, '
            'header $cmp :is $headerList $value)'
        : 'header $cmp :is $headerList $value';

    return switch (condition.comparator) {
      Comparator.contains => contains(),
      Comparator.notContains => 'not ${contains()}',
      Comparator.exactlyEquals => equals(),
      Comparator.notExactlyEquals => 'not ${equals()}',
    };
  }

  List<String> _flagsOf(TMailRule rule) {
    final action = rule.action;
    if (action.reject == true) return const [];
    return [
      if (action.markAsSeen == true) r'\Seen',
      if (action.markAsImportant == true) r'\Flagged',
      ...?action.withKeywords,
    ];
  }

  List<String> _commandsOf(TMailRule rule) {
    final action = rule.action;
    if (action.reject == true) {
      // `discard` drops the message silently, like the Linagora backend.
      // Sending a bounce (`reject`) would generate backscatter.
      return ['discard;', 'stop;'];
    }

    final flags = _flagsOf(rule);
    for (final keyword in action.withKeywords ?? const <String>[]) {
      if (!RegExp(r'^\$?[A-Za-z0-9_.\-]+$').hasMatch(keyword)) {
        throw SieveRuleNotRepresentableException(
          rule.name,
          'invalid keyword "$keyword"',
        );
      }
    }

    final mailboxIds = action.appendIn.mailboxIds;
    if (flags.isEmpty && mailboxIds.isEmpty && !rule.stopProcessing) {
      throw SieveRuleNotRepresentableException(rule.name, 'no action');
    }

    return [
      // Flags accumulate for the rest of the script, so they also reach the
      // default delivery (implicit keep) and the mailboxes below.
      if (flags.isNotEmpty) 'addflag ${_stringList(flags)};',
      for (final mailboxId in mailboxIds)
        'fileinto :mailboxid ${_quote(mailboxId.id.value)} '
            '${_quote(fallbackMailboxName)};',
      if (rule.stopProcessing) 'stop;',
    ];
  }

  String _stringList(List<String> values) =>
      '[${values.map(_quote).join(', ')}]';

  /// RFC 5228, section 2.4.2: inside a quoted string only `"` and `\` need
  /// escaping. CR and LF are removed because header values never contain
  /// them and they would change the meaning of the comparison.
  String _quote(String value) {
    final escaped = value
        .replaceAll('\r', '')
        .replaceAll('\n', '')
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"');
    return '"$escaped"';
  }

  String _normalize(String content) =>
      content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trimRight();
}
