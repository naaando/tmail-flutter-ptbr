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
import 'package:tmail_ui_user/features/manage_account/domain/model/create_new_email_rule_filter_request.dart';
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

  Set<String> mailboxes = {'m1', 'm2'};

  @override
  Future<Set<String>> mailboxIds(AccountId accountId) async => mailboxes;

  /// Reads that fail after the next save (network trouble on read-back).
  int failReadsAfterSave = 0;
  bool _savedSinceFailureArmed = false;

  /// Turns the vacation reply on right after the next save.
  bool enableVacationAfterSave = false;

  @override
  Future<SieveRulesSnapshot> read(AccountId accountId) async {
    if (_savedSinceFailureArmed && failReadsAfterSave > 0) {
      failReadsAfterSave--;
      throw Exception('network');
    }
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
    _savedSinceFailureArmed = true;
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
    if (enableVacationAfterSave) {
      scripts.updateAll((key, script) => SieveScript(
            id: script.id,
            name: script.name,
            blobId: script.blobId,
            isActive: false,
          ));
      addScript('v', 'vacation', 'vacation "x";', active: true);
      _state++;
    }
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

  /// Writes [rules] starting from what the datasource last read, as the
  /// rules page does.
  Future<List<TMailRule>> save(
    SieveRuleFilterDataSourceImpl source,
    List<TMailRule> rules,
  ) async {
    final current = await source.getAllTMailRule(accountId);
    return source.replaceAllTMailRules(accountId, rules, currentRules: current);
  }

  setUp(() {
    server = _FakeSieveServer();
    dataSource = SieveRuleFilterDataSourceImpl(server, _capability, _RethrowThrower());
  });

  test('first write creates and activates the managed script', () async {
    final rules = await save(dataSource, [_rule('A'), _rule('B', enabled: false)]);

    expect(rules.map((r) => r.name), ['A', 'B']);
    expect(rules.map((r) => r.isEnabled), [true, false]);
    expect(server.lastActivate, isTrue);
    final status = await dataSource.getRulesStatus(accountId);
    expect(status?.isActive, isTrue);
    expect(status?.isBlocked, isFalse);
  });

  test('persists order and state across a fresh read', () async {
    await save(dataSource, [_rule('A'), _rule('B')]);
    await save(dataSource, [_rule('B', enabled: false), _rule('A')]);

    final reloaded = SieveRuleFilterDataSourceImpl(server, _capability, _RethrowThrower());
    final rules = await reloaded.getAllTMailRule(accountId);
    expect(rules.map((r) => r.name), ['B', 'A']);
    expect(rules.map((r) => r.isEnabled), [false, true]);
  });

  test('never deactivates the automatic reply and reports the block', () async {
    server.addScript('v', 'vacation', 'require "vacation"; vacation "x";', active: true);

    await dataSource.getAllTMailRule(accountId);
    final rules = await save(dataSource, [_rule('A')]);

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

    await save(dataSource, [_rule('A')]);

    expect(server.scripts['x']!.isActive, isTrue);
    expect(server.contents['x'], 'keep;');
    final status = await dataSource.getRulesStatus(accountId);
    expect(status?.blockingScriptName, 'roundcube');
    expect(status?.blockedByVacation, isFalse);
  });

  test('offers activation once nothing else is active', () async {
    server.addScript('v', 'vacation', 'vacation "x";', active: true);
    await save(dataSource, [_rule('A')]);
    server.scripts['v'] = SieveScript(id: Id('v'), name: 'vacation', isActive: false);
    server.bumpState();

    await dataSource.getAllTMailRule(accountId);
    expect((await dataSource.getRulesStatus(accountId))?.canActivate, isTrue);

    await save(dataSource, await dataSource.getAllTMailRule(accountId));
    expect(server.lastActivate, isTrue);
    expect((await dataSource.getRulesStatus(accountId))?.isActive, isTrue);
  });

  test('a concurrent change fails with a conflict and is not overwritten', () async {
    final listed = await save(dataSource, [_rule('A')]);
    server.bumpState();
    final savesBefore = server.saves;

    await expectLater(
      dataSource.replaceAllTMailRules(accountId, [_rule('B')], currentRules: listed),
      throwsA(isA<SieveRulesConflictException>()),
    );
    expect(server.saves, savesBefore);

    // The next attempt reads the current state first and succeeds.
    final rules = await save(dataSource, [_rule('B')]);
    expect(rules.single.name, 'B');
  });

  test('a stale list is refused even after another read refreshed the state', () async {
    // The rules page lists [A] ...
    final pageList = await save(dataSource, [_rule('A')]);
    // ... another tab adds B ...
    final other = SieveRuleFilterDataSourceImpl(server, _capability, _RethrowThrower());
    await other.replaceAllTMailRules(
      accountId,
      [_rule('B'), _rule('A')],
      currentRules: await other.getAllTMailRule(accountId),
    );
    // ... and the editor opened in this tab reads the new state.
    await dataSource.getAllTMailRule(accountId);

    // Toggling A from the page's stale list must not erase B.
    await expectLater(
      dataSource.replaceAllTMailRules(
        accountId,
        [pageList.single.copyWith(isEnabled: false)],
        currentRules: pageList,
      ),
      throwsA(isA<SieveRulesConflictException>()),
    );
    final stored = await dataSource.getAllTMailRule(accountId);
    expect(stored.map((rule) => rule.name), ['B', 'A']);
  });

  test('a list that never loaded cannot replace existing rules', () async {
    await save(dataSource, [_rule('A'), _rule('B')]);
    final fresh = SieveRuleFilterDataSourceImpl(server, _capability, _RethrowThrower());

    await expectLater(
      fresh.createNewEmailRuleFilter(
        accountId,
        CreateNewEmailRuleFilterRequest(const [], _rule('C')),
      ),
      throwsA(isA<SieveRulesConflictException>()),
    );
    await expectLater(
      fresh.replaceAllTMailRules(accountId, [_rule('C')]),
      throwsA(isA<SieveRulesConflictException>()),
    );
    expect((await fresh.getAllTMailRule(accountId)).map((rule) => rule.name), ['A', 'B']);
  });

  test('a managed script whose content cannot be read is never overwritten', () async {
    server.scripts['managed'] = SieveScript(
      id: Id('managed'),
      name: managedSieveScriptName,
      isActive: true,
    );

    expect(await dataSource.getAllTMailRule(accountId), isEmpty);
    expect((await dataSource.getRulesStatus(accountId))?.readOnlyReason,
        EmailRulesReadOnlyReason.modifiedExternally);
    await expectLater(
      dataSource.replaceAllTMailRules(accountId, [_rule('A')], currentRules: const []),
      throwsA(isA<SieveRulesReadOnlyException>()),
    );
  });

  test('a script edited elsewhere becomes read-only and is preserved', () async {
    await save(dataSource, [_rule('A')]);
    final edited = '${server.contents['managed']!}\r\nkeep;\r\n';
    server.contents['managed'] = edited;
    server.bumpState();

    expect(await dataSource.getAllTMailRule(accountId), isEmpty);
    final status = await dataSource.getRulesStatus(accountId);
    expect(status?.readOnlyReason, EmailRulesReadOnlyReason.modifiedExternally);
    await expectLater(
      save(dataSource, [_rule('B')]),
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
      save(dataSource, [_rule('A')]),
      throwsA(isA<SieveRulesReadOnlyException>()),
    );
    expect(server.contents['f'], 'discard;');
  });

  test('fails when the stored content differs from what was sent', () async {
    server.tamperStoredContent = (content) => content.replaceFirst('"m1"', '"m2"');

    await expectLater(
      save(dataSource, [_rule('A')]),
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
      save(small, [_rule('A'), _rule('B')]),
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
      save(limited, [_rule('A')]),
      throwsA(isA<SieveExtensionNotSupportedException>()),
    );
    expect(server.saves, 0);
  });

  test('deleting the last rule keeps an empty managed script', () async {
    final rules = await save(dataSource, [_rule('A')]);

    final remaining = await dataSource.deleteTMailRule(
      accountId,
      DeleteEmailRuleRequest(emailRuleDelete: rules.single, currentEmailRules: rules),
    );

    expect(remaining, isEmpty);
    expect(rules, hasLength(1), reason: 'the request list must not be mutated');
    expect((await dataSource.getRulesStatus(accountId))?.isActive, isTrue);
  });

  test('flags rules whose folder was deleted', () async {
    await save(dataSource, [
      _rule('Existe', mailboxIds: ['m1']),
      _rule('Removida', mailboxIds: ['m9']),
      _rule('Só marca', mailboxIds: const []),
    ]);

    final status = await dataSource.getRulesStatus(accountId);
    expect(status?.rulesWithMissingMailbox, {1});
  });

  test('a transient read-back failure does not turn a save into an error', () async {
    await save(dataSource, [_rule('A')]);
    final current = await dataSource.getAllTMailRule(accountId);
    server.failReadsAfterSave = 1;

    final rules = await dataSource.replaceAllTMailRules(
      accountId,
      [_rule('B')],
      currentRules: current,
    );
    expect(rules.single.name, 'B');
  });

  test('a save that cannot be read back twice is reported as unconfirmed', () async {
    await save(dataSource, [_rule('A')]);
    final current = await dataSource.getAllTMailRule(accountId);
    server.failReadsAfterSave = 2;

    await expectLater(
      dataSource.replaceAllTMailRules(accountId, [_rule('B')], currentRules: current),
      throwsA(isA<SieveRulesVerificationException>()),
    );
  });

  test('vacation turned on during the save is a status, not a failure', () async {
    await save(dataSource, [_rule('A')]);
    server.enableVacationAfterSave = true;

    final rules = await save(dataSource, [_rule('B')]);
    expect(rules.single.name, 'B');
    final status = await dataSource.getRulesStatus(accountId);
    expect(status?.isActive, isFalse);
    expect(status?.blockedByVacation, isTrue);
  });
}
