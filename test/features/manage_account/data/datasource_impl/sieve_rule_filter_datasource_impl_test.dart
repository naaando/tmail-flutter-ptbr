import 'package:flutter_test/flutter_test.dart';
import 'package:jmap_dart_client/http/http_client.dart';
import 'package:jmap_dart_client/jmap/account_id.dart';
import 'package:jmap_dart_client/jmap/core/id.dart';
import 'package:jmap_dart_client/jmap/core/state.dart';
import 'package:jmap_dart_client/jmap/mail/mailbox/mailbox.dart';
import 'package:dio/dio.dart';
import 'package:rule_filter/rule_filter/rule_action.dart';
import 'package:rule_filter/rule_filter/rule_append_in.dart';
import 'package:rule_filter/rule_filter/rule_condition.dart';
import 'package:rule_filter/rule_filter/rule_condition_group.dart';
import 'package:rule_filter/rule_filter/tmail_rule.dart';
import 'package:rule_filter/sieve/sieve_account_capability.dart';
import 'package:rule_filter/sieve/sieve_rules_codec.dart';
import 'package:rule_filter/sieve/sieve_script.dart';
import 'package:tmail_ui_user/features/manage_account/data/datasource_impl/sieve_rule_filter_datasource_impl.dart';
import 'package:tmail_ui_user/features/manage_account/data/network/sieve_rule_filter_api.dart';
import 'package:tmail_ui_user/features/manage_account/domain/exceptions/sieve_rules_exceptions.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/delete_email_rule_request.dart';
import 'package:tmail_ui_user/features/manage_account/domain/model/email_rules_status.dart';
import 'package:tmail_ui_user/main/exceptions/thrower/exception_thrower.dart';

const _capability = SieveAccountCapability(
  maxSizeScript: 102400,
  sieveExtensions: {'fileinto', 'mailbox', 'mailboxid', 'imap4flags'},
  implementation: 'Stalwart v1.0.0',
);

class _RethrowThrower extends ExceptionThrower {
  @override
  throwException(dynamic error, dynamic stackTrace) => throw error;
}

/// In-memory server: keeps the scripts and enforces `ifInState` like
/// Stalwart, so the datasource is exercised against realistic behaviour.
class _FakeSieveServer extends SieveRuleFilterAPI {
  _FakeSieveServer() : super(HttpClient(Dio()));

  int _state = 1;
  final Map<String, SieveScript> scripts = {};
  final Map<String, String> contents = {};
  int saves = 0;
  bool? lastActivate;
  String Function(String content)? tamperStoredContent;

  void addScript(String id, String name, String content, {bool active = false}) {
    scripts[id] = SieveScript(id: Id(id), name: name, blobId: 'b$id', isActive: active);
    contents[id] = content;
  }

  /// Simulates a change made by another session or client.
  void bumpState() => _state++;

  @override
  Future<SieveRulesSnapshot> read(AccountId accountId) async {
    final managed = scripts.values
        .where((script) => script.name == managedSieveScriptName)
        .firstOrNull;
    return SieveRulesSnapshot(
      state: State('$_state'),
      scripts: scripts.values.toList(),
      managedScript: managed,
      managedContent: managed == null ? null : contents[managed.id.value],
    );
  }

  @override
  Future<void> save(
    AccountId accountId, {
    required SieveRulesSnapshot base,
    required String content,
    required bool activate,
  }) async {
    if (base.state != State('$_state')) {
      throw const SieveRulesConflictException();
    }
    saves++;
    lastActivate = activate;
    final id = base.managedScript?.id.value ?? 'managed';
    final stored = tamperStoredContent?.call(content) ?? content;
    contents[id] = stored;
    if (activate) {
      scripts.updateAll((key, script) => SieveScript(
            id: script.id,
            name: script.name,
            blobId: script.blobId,
            isActive: key == id,
          ));
    }
    scripts[id] = SieveScript(
      id: Id(id),
      name: managedSieveScriptName,
      blobId: 'b$id-$_state',
      isActive: activate || (scripts[id]?.isActive ?? false),
    );
    _state++;
  }
}

TMailRule _rule(String name, {bool enabled = true, List<String> mailboxIds = const ['m1']}) {
  return TMailRule(
    name: name,
    conditionGroup: RuleConditionGroup(
      conditionCombiner: ConditionCombiner.AND,
      conditions: [
        RuleCondition(field: Field.subject, comparator: Comparator.contains, value: name),
      ],
    ),
    action: RuleAction(
      appendIn: RuleAppendIn(mailboxIds: mailboxIds.map((id) => MailboxId(Id(id))).toList()),
      markAsSeen: true,
    ),
    isEnabled: enabled,
  );
}

void main() {
  final accountId = AccountId(Id('acc'));
  late _FakeSieveServer server;
  late SieveRuleFilterDataSourceImpl dataSource;

  setUp(() {
    server = _FakeSieveServer();
    dataSource = SieveRuleFilterDataSourceImpl(server, _capability, _RethrowThrower());
  });

  test('first write creates and activates the managed script', () async {
    final rules = await dataSource.replaceAllTMailRules(accountId, [_rule('A'), _rule('B', enabled: false)]);

    expect(rules.map((r) => r.name), ['A', 'B']);
    expect(rules.map((r) => r.isEnabled), [true, false]);
    expect(server.lastActivate, isTrue);
    final status = await dataSource.getRulesStatus(accountId);
    expect(status?.isActive, isTrue);
    expect(status?.isBlocked, isFalse);
  });

  test('persists order and state across a fresh read', () async {
    await dataSource.replaceAllTMailRules(accountId, [_rule('A'), _rule('B')]);
    await dataSource.replaceAllTMailRules(accountId, [_rule('B', enabled: false), _rule('A')]);

    final reloaded = SieveRuleFilterDataSourceImpl(server, _capability, _RethrowThrower());
    final rules = await reloaded.getAllTMailRule(accountId);
    expect(rules.map((r) => r.name), ['B', 'A']);
    expect(rules.map((r) => r.isEnabled), [false, true]);
  });

  test('never deactivates the automatic reply and reports the block', () async {
    server.addScript('v', 'vacation', 'require "vacation"; vacation "x";', active: true);

    await dataSource.getAllTMailRule(accountId);
    final rules = await dataSource.replaceAllTMailRules(accountId, [_rule('A')]);

    expect(rules, hasLength(1));
    expect(server.lastActivate, isFalse);
    expect(server.scripts['v']!.isActive, isTrue);
    final status = await dataSource.getRulesStatus(accountId);
    expect(status?.blockedByVacation, isTrue);
    expect(status?.isActive, isFalse);
    expect(status?.canActivate, isFalse);
  });

  test('never deactivates an unknown active script', () async {
    server.addScript('x', 'roundcube', 'keep;', active: true);

    await dataSource.replaceAllTMailRules(accountId, [_rule('A')]);

    expect(server.scripts['x']!.isActive, isTrue);
    expect(server.contents['x'], 'keep;');
    final status = await dataSource.getRulesStatus(accountId);
    expect(status?.blockingScriptName, 'roundcube');
    expect(status?.blockedByVacation, isFalse);
  });

  test('offers activation once nothing else is active', () async {
    server.addScript('v', 'vacation', 'vacation "x";', active: true);
    await dataSource.replaceAllTMailRules(accountId, [_rule('A')]);
    server.scripts['v'] = SieveScript(id: Id('v'), name: 'vacation', isActive: false);
    server.bumpState();

    await dataSource.getAllTMailRule(accountId);
    expect((await dataSource.getRulesStatus(accountId))?.canActivate, isTrue);

    await dataSource.replaceAllTMailRules(accountId, await dataSource.getAllTMailRule(accountId));
    expect(server.lastActivate, isTrue);
    expect((await dataSource.getRulesStatus(accountId))?.isActive, isTrue);
  });

  test('a concurrent change fails with a conflict and is not overwritten', () async {
    await dataSource.replaceAllTMailRules(accountId, [_rule('A')]);
    server.bumpState();
    final savesBefore = server.saves;

    await expectLater(
      dataSource.replaceAllTMailRules(accountId, [_rule('B')]),
      throwsA(isA<SieveRulesConflictException>()),
    );
    expect(server.saves, savesBefore);

    // The next attempt reads the current state first and succeeds.
    final rules = await dataSource.replaceAllTMailRules(accountId, [_rule('B')]);
    expect(rules.single.name, 'B');
  });

  test('a script edited elsewhere becomes read-only and is preserved', () async {
    await dataSource.replaceAllTMailRules(accountId, [_rule('A')]);
    final edited = '${server.contents['managed']!}\r\nkeep;\r\n';
    server.contents['managed'] = edited;
    server.bumpState();

    expect(await dataSource.getAllTMailRule(accountId), isEmpty);
    final status = await dataSource.getRulesStatus(accountId);
    expect(status?.readOnlyReason, EmailRulesReadOnlyReason.modifiedExternally);
    await expectLater(
      dataSource.replaceAllTMailRules(accountId, [_rule('B')]),
      throwsA(isA<SieveRulesReadOnlyException>()),
    );
    expect(server.contents['managed'], edited);
  });

  test('a foreign script with the managed name is never overwritten', () async {
    server.addScript('f', managedSieveScriptName, 'discard;');

    await dataSource.getAllTMailRule(accountId);
    expect((await dataSource.getRulesStatus(accountId))?.readOnlyReason,
        EmailRulesReadOnlyReason.nameConflict);
    await expectLater(
      dataSource.replaceAllTMailRules(accountId, [_rule('A')]),
      throwsA(isA<SieveRulesReadOnlyException>()),
    );
    expect(server.contents['f'], 'discard;');
  });

  test('fails when the stored content differs from what was sent', () async {
    server.tamperStoredContent = (content) => content.replaceFirst('"m1"', '"m2"');

    await expectLater(
      dataSource.replaceAllTMailRules(accountId, [_rule('A')]),
      throwsA(isA<SieveRulesVerificationException>()),
    );
  });

  test('refuses scripts above the server limit before uploading', () async {
    final small = SieveRuleFilterDataSourceImpl(
      server,
      const SieveAccountCapability(
        maxSizeScript: 200,
        sieveExtensions: {'fileinto', 'mailbox', 'mailboxid', 'imap4flags'},
      ),
      _RethrowThrower(),
    );

    await expectLater(
      small.replaceAllTMailRules(accountId, [_rule('A'), _rule('B')]),
      throwsA(isA<SieveScriptTooLargeException>()),
    );
    expect(server.saves, 0);
  });

  test('refuses actions whose extension the server lacks', () async {
    final limited = SieveRuleFilterDataSourceImpl(
      server,
      const SieveAccountCapability(sieveExtensions: {'fileinto'}),
      _RethrowThrower(),
    );

    await expectLater(
      limited.replaceAllTMailRules(accountId, [_rule('A')]),
      throwsA(isA<SieveExtensionNotSupportedException>()),
    );
    expect(server.saves, 0);
  });

  test('deleting the last rule keeps an empty managed script', () async {
    final rules = await dataSource.replaceAllTMailRules(accountId, [_rule('A')]);

    final remaining = await dataSource.deleteTMailRule(
      accountId,
      DeleteEmailRuleRequest(emailRuleDelete: rules.single, currentEmailRules: rules),
    );

    expect(remaining, isEmpty);
    expect(rules, hasLength(1), reason: 'the request list must not be mutated');
    expect((await dataSource.getRulesStatus(accountId))?.isActive, isTrue);
  });
}
