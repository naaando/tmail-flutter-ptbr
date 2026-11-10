import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jmap_dart_client/jmap/core/id.dart';
import 'package:jmap_dart_client/jmap/mail/mailbox/mailbox.dart';
import 'package:rule_filter/rule_filter/rule_action.dart';
import 'package:rule_filter/rule_filter/rule_append_in.dart';
import 'package:rule_filter/rule_filter/rule_condition.dart';
import 'package:rule_filter/rule_filter/rule_condition_group.dart';
import 'package:rule_filter/rule_filter/tmail_rule.dart';
import 'package:rule_filter/sieve/sieve_account_capability.dart';
import 'package:rule_filter/sieve/sieve_rules_codec.dart';

const _stalwart = SieveAccountCapability(
  maxSizeScript: 102400,
  sieveExtensions: {
    'fileinto',
    'mailbox',
    'mailboxid',
    'imap4flags',
    'comparator-i;ascii-casemap',
  },
  implementation: 'Stalwart v1.0.0',
);

TMailRule _rule(
  String name, {
  List<RuleCondition>? conditions,
  ConditionCombiner combiner = ConditionCombiner.AND,
  List<String> mailboxIds = const [],
  bool seen = false,
  bool important = false,
  bool reject = false,
  List<String>? keywords,
  bool enabled = true,
  bool stop = false,
}) {
  return TMailRule(
    name: name,
    conditionGroup: RuleConditionGroup(
      conditionCombiner: combiner,
      conditions: conditions ??
          [
            RuleCondition(
              field: Field.subject,
              comparator: Comparator.contains,
              value: 'relatório',
            ),
          ],
    ),
    action: RuleAction(
      appendIn: RuleAppendIn(
        mailboxIds: mailboxIds.map((id) => MailboxId(Id(id))).toList(),
      ),
      markAsSeen: seen,
      markAsImportant: important,
      reject: reject,
      withKeywords: keywords,
    ),
    isEnabled: enabled,
    stopProcessing: stop,
  );
}

void main() {
  const codec = SieveRulesCodec();

  SieveRulesDocument document(List<TMailRule> rules) => SieveRulesDocument(
        comparator: codec.chooseComparator(_stalwart),
        rules: rules,
      );

  group('SieveRulesCodec.generate', () {
    test('generates ordered rules with every supported action', () {
      final script = codec.generate(
        document([
          _rule(
            'Relatórios',
            mailboxIds: ['m1'],
            seen: true,
            stop: true,
          ),
          _rule(
            'Chefe ou cliente',
            combiner: ConditionCombiner.OR,
            conditions: [
              RuleCondition(
                field: Field.from,
                comparator: Comparator.exactlyEquals,
                value: 'chefe@ext.test',
              ),
              RuleCondition(
                field: Field.recipient,
                comparator: Comparator.notContains,
                value: 'lista@',
              ),
            ],
            important: true,
            keywords: [r'$label1'],
          ),
          _rule('Pausada', mailboxIds: ['m2'], enabled: false),
          _rule('Lixo', reject: true, seen: true),
        ]),
        capability: _stalwart,
      );

      expect(
        script.split('\r\n').skip(3).join('\n'),
        '''
require ["fileinto", "imap4flags", "mailbox", "mailboxid"];

# Regra 1
if allof(header :comparator "i;unicode-casemap" :contains ["subject"] "relatório") {
    addflag ["\\\\Seen"];
    fileinto :mailboxid "m1" "INBOX";
    stop;
}

# Regra 2
if anyof(anyof(address :all :comparator "i;unicode-casemap" :is ["from"] "chefe@ext.test", header :comparator "i;unicode-casemap" :is ["from"] "chefe@ext.test"), not header :comparator "i;unicode-casemap" :contains ["to", "cc"] "lista@") {
    addflag ["\\\\Flagged", "\$label1"];
}

# Regra 3: desativada

# Regra 4
if allof(header :comparator "i;unicode-casemap" :contains ["subject"] "relatório") {
    discard;
    stop;
}
''',
      );
      expect(script, startsWith('# Twake Mail:'));
      expect(script, contains('\r\n'));
    });

    test('escapes quotes and backslashes and drops line breaks', () {
      final script = codec.generate(document([
        _rule(
          'Escape',
          conditions: [
            RuleCondition(
              field: Field.subject,
              comparator: Comparator.contains,
              value: 'a"b\\c\r\nd',
            ),
          ],
          important: true,
        ),
      ]));

      expect(script, contains(r':contains ["subject"] "a\"b\\cd"'));
    });

    test('keeps Unicode values verbatim', () {
      final script = codec.generate(document([
        _rule(
          'Unicode',
          conditions: [
            RuleCondition(
              field: Field.subject,
              comparator: Comparator.exactlyEquals,
              value: 'Ação 日本 🚀',
            ),
          ],
          seen: true,
        ),
      ]));

      expect(script, contains(':is ["subject"] "Ação 日本 🚀"'));
    });

    test('uses the ascii comparator on servers without Unicode case mapping',
        () {
      const generic = SieveAccountCapability(
        sieveExtensions: {'fileinto', 'mailboxid', 'imap4flags'},
        implementation: 'Other',
      );
      expect(codec.chooseComparator(generic), asciiCaseMapComparator);
      expect(codec.chooseComparator(_stalwart), unicodeCaseMapComparator);
    });

    test('rejects invalid keywords and rules without action', () {
      expect(
        () => codec.generate(document([
          _rule('Keyword', keywords: ['com espaço']),
        ])),
        throwsA(isA<SieveRuleNotRepresentableException>()),
      );
      expect(
        () => codec.generate(document([_rule('Sem ação')])),
        throwsA(isA<SieveRuleNotRepresentableException>()),
      );
    });

    test('a disabled rule needs no extension', () {
      final doc = document([_rule('Pausada', mailboxIds: ['m1'], enabled: false)]);
      expect(codec.requiredExtensions(doc, capability: _stalwart), isEmpty);
      expect(codec.generate(doc, capability: _stalwart), isNot(contains('require')));
    });
  });

  group('SieveRulesCodec.ensureSupported', () {
    test('reports the missing extensions instead of ignoring the action', () {
      const withoutMailboxId = SieveAccountCapability(
        sieveExtensions: {'fileinto', 'imap4flags'},
      );
      expect(
        () => codec.ensureSupported(
          document([_rule('Mover', mailboxIds: ['m1'])]),
          withoutMailboxId,
        ),
        throwsA(
          isA<SieveExtensionNotSupportedException>().having(
            (e) => e.missingExtensions,
            'missingExtensions',
            {'mailboxid'},
          ),
        ),
      );
      codec.ensureSupported(document([_rule('Lixo', reject: true)]), withoutMailboxId);
    });

    test('maps editor features to extensions', () {
      expect(SieveRuleFeature.moveToMailbox.isSupportedBy(_stalwart), isTrue);
      expect(
        SieveRuleFeature.setFlags.isSupportedBy(
          const SieveAccountCapability(sieveExtensions: {'fileinto'}),
        ),
        isFalse,
      );
    });
  });

  group('SieveRulesCodec.parse', () {
    final rules = [
      _rule('Relatórios', mailboxIds: ['m1'], seen: true, stop: true),
      _rule('Pausada "aspas"', important: true, enabled: false),
      _rule('Lixo', reject: true),
    ];

    test('round-trips rules, order, state and options', () {
      final script = codec.generate(document(rules), capability: _stalwart);
      final parsed = codec.parse(script);

      expect(parsed.integrity, ManagedScriptIntegrity.intact);
      expect(parsed.document!.comparator, unicodeCaseMapComparator);
      expect(parsed.document!.rules.map((rule) => rule.name),
          ['Relatórios', 'Pausada "aspas"', 'Lixo']);
      expect(parsed.document!.rules.map((rule) => rule.isEnabled),
          [true, false, true]);
      expect(parsed.document!.rules.map((rule) => rule.stopProcessing),
          [true, false, false]);
      expect(parsed.document!.rules.map((rule) => rule.id?.id.value),
          ['0', '1', '2']);
      for (var i = 0; i < rules.length; i++) {
        expect(parsed.document!.rules[i].action, rules[i].action);
        expect(parsed.document!.rules[i].conditionGroup, rules[i].conditionGroup);
      }
    });

    test('accepts LF line endings and a missing trailing newline', () {
      final script = codec.generate(document(rules), capability: _stalwart);
      final parsed = codec.parse(script.replaceAll('\r\n', '\n').trimRight());
      expect(parsed.isIntact, isTrue);
    });

    test('accepts a script generated without the optional mailbox require', () {
      const withoutMailbox = SieveAccountCapability(
        sieveExtensions: {'fileinto', 'mailboxid', 'imap4flags'},
        implementation: 'Stalwart',
      );
      final script = codec.generate(document(rules), capability: withoutMailbox);
      expect(script, isNot(contains('"mailbox"')));
      expect(codec.parse(script).isIntact, isTrue);
    });

    test('detects code changed by another client', () {
      final script = codec.generate(document(rules), capability: _stalwart);
      final changed = script.replaceFirst('stop;', 'keep;');
      final parsed = codec.parse(changed);
      expect(parsed.integrity, ManagedScriptIntegrity.modifiedExternally);
    });

    test('detects metadata that no longer matches the code', () {
      final script = codec.generate(document(rules), capability: _stalwart);
      // The first occurrence is inside the metadata JSON.
      final changed = script.replaceFirst('"m1"', '"m9"');
      expect(codec.parse(changed).isIntact, isFalse);
    });

    test('a rename made only in the metadata stays consistent', () {
      final script = codec.generate(document(rules), capability: _stalwart);
      final renamed = codec.parse(script.replaceFirst('Relatórios', 'Outro'));
      expect(renamed.isIntact, isTrue);
      expect(renamed.document!.rules.first.name, 'Outro');
    });

    test('treats scripts without metadata or with unknown versions as foreign',
        () {
      expect(
        codec.parse('require ["fileinto"];\r\nfileinto "INBOX";\r\n').integrity,
        ManagedScriptIntegrity.modifiedExternally,
      );
      expect(
        codec.parse('$managedSieveMetadataPrefix{"v":99,"cmp":"x","rules":[]}')
            .isIntact,
        isFalse,
      );
      expect(codec.parse('${managedSieveMetadataPrefix}not json').isIntact,
          isFalse);
    });

    test('an empty rule list is a valid managed script', () {
      final script = codec.generate(document(const []), capability: _stalwart);
      final parsed = codec.parse(script);
      expect(parsed.isIntact, isTrue);
      expect(parsed.document!.rules, isEmpty);
    });
  });

  test('writes fixtures for server-side validation when requested', () {
    final directory = Platform.environment['SIEVE_FIXTURE_DIR'];
    if (directory == null) return;
    final fixtures = {
      'all-actions': document([
        _rule('Relatórios', mailboxIds: ['m1'], seen: true, stop: true),
        _rule(
          'Chefe',
          combiner: ConditionCombiner.OR,
          conditions: [
            RuleCondition(
              field: Field.from,
              comparator: Comparator.exactlyEquals,
              value: 'chefe@ext.test',
            ),
            RuleCondition(
              field: Field.cc,
              comparator: Comparator.notExactlyEquals,
              value: 'x"y\\z',
            ),
          ],
          important: true,
          keywords: [r'$etiqueta'],
        ),
        _rule('Pausada', mailboxIds: ['m2'], enabled: false),
        _rule('Lixo', reject: true),
      ]),
      'empty': document(const []),
    };
    for (final entry in fixtures.entries) {
      File('$directory/${entry.key}.sieve').writeAsStringSync(
        codec.generate(entry.value, capability: _stalwart),
      );
    }
  });
}
