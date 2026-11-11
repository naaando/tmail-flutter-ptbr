import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmap_dart_client/http/http_client.dart';
import 'package:jmap_dart_client/jmap/account_id.dart';
import 'package:jmap_dart_client/jmap/core/id.dart';
import 'package:jmap_dart_client/jmap/core/state.dart';
import 'package:rule_filter/sieve/sieve_script.dart';
import 'package:tmail_ui_user/features/manage_account/data/network/sieve_rule_filter_api.dart';
import 'package:tmail_ui_user/features/manage_account/domain/exceptions/sieve_rules_exceptions.dart';

/// Answers each JMAP request with the next queued `methodResponses` and keeps
/// the decoded request bodies for assertions.
class _QueuedJmapAdapter implements HttpClientAdapter {
  final List<List<dynamic>> responses;
  final List<Map<String, dynamic>> requests = [];

  _QueuedJmapAdapter(this.responses);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = options.data;
    requests.add(Map<String, dynamic>.from(
      data is String ? jsonDecode(data) as Map : data as Map,
    ));
    final body = jsonEncode({
      'sessionState': 's1',
      'methodResponses': responses.removeAt(0),
    });
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final accountId = AccountId(Id('acc'));

  (SieveRuleFilterAPI, _QueuedJmapAdapter) build(List<List<dynamic>> responses) {
    final adapter = _QueuedJmapAdapter(responses);
    final dio = Dio(BaseOptions(method: 'POST', baseUrl: 'http://domain.com/jmap'))
      ..httpClientAdapter = adapter;
    return (SieveRuleFilterAPI(HttpClient(dio)), adapter);
  }

  group('SieveRuleFilterAPI.read', () {
    test('lists scripts and downloads only the managed one', () async {
      final (api, adapter) = build([
        [
          [
            'SieveScript/get',
            {
              'accountId': 'acc',
              'state': 'st1',
              'list': [
                {'id': 'v', 'name': 'vacation', 'blobId': 'bv', 'isActive': true},
                {'id': 'm', 'name': 'twake-mail-rules', 'blobId': 'bm', 'isActive': false},
              ],
              'notFound': [],
            },
            'c0',
          ],
        ],
        [
          [
            'Blob/get',
            {
              'accountId': 'acc',
              'list': [
                {'id': 'bm', 'data:asText': '# script'},
              ],
              'notFound': [],
            },
            'c0',
          ],
        ],
      ]);

      final snapshot = await api.read(accountId);

      expect(snapshot.state, State('st1'));
      expect(snapshot.managedScript?.id, Id('m'));
      expect(snapshot.managedContent, '# script');
      expect(snapshot.otherActiveScript?.name, 'vacation');
      final blobCall = adapter.requests[1]['methodCalls'][0];
      expect(blobCall[0], 'Blob/get');
      expect(blobCall[1]['ids'], ['bm']);
      expect(adapter.requests[1]['using'], contains('urn:ietf:params:jmap:blob'));
    });

    test('does not download anything when there is no managed script', () async {
      final (api, adapter) = build([
        [
          [
            'SieveScript/get',
            {'accountId': 'acc', 'state': 'st1', 'list': [], 'notFound': []},
            'c0',
          ],
        ],
      ]);

      final snapshot = await api.read(accountId);

      expect(snapshot.managedScript, isNull);
      expect(adapter.requests, hasLength(1));
    });
  });

  group('SieveRuleFilterAPI.save', () {
    final base = SieveRulesSnapshot(
      state: State('st1'),
      scripts: [SieveScript(id: Id('m'), name: 'twake-mail-rules', blobId: 'old')],
      managedScript: SieveScript(id: Id('m'), name: 'twake-mail-rules', blobId: 'old'),
      managedContent: '# old',
    );

    List<List<dynamic>> uploadAndValidate({Map<String, dynamic>? validateError}) => [
          [
            [
              'Blob/upload',
              {
                'accountId': 'acc',
                'created': {
                  'rules': {'id': 'new-blob', 'type': 'application/sieve', 'size': 10},
                },
              },
              'c0',
            ],
          ],
          [
            [
              'SieveScript/validate',
              {'accountId': 'acc', 'error': validateError},
              'c0',
            ],
          ],
        ];

    test('updates with ifInState and activates when asked', () async {
      final (api, adapter) = build([
        ...uploadAndValidate(),
        [
          [
            'SieveScript/set',
            {
              'accountId': 'acc',
              'oldState': 'st1',
              'newState': 'st2',
              'updated': {'m': null},
            },
            'c0',
          ],
        ],
      ]);

      await api.save(accountId, base: base, content: '# new', activate: true);

      final upload = adapter.requests[0]['methodCalls'][0][1];
      expect(upload['create']['rules']['data'][0]['data:asText'], '# new');
      final set = adapter.requests[2]['methodCalls'][0][1];
      expect(set['ifInState'], 'st1');
      expect(set['update'], {
        'm': {'blobId': 'new-blob'},
      });
      expect(set['onSuccessActivateScript'], 'm');
    });

    test('creates the script and never sends activation when not allowed', () async {
      final (api, adapter) = build([
        ...uploadAndValidate(),
        [
          [
            'SieveScript/set',
            {
              'accountId': 'acc',
              'created': {
                'managed': {'id': 'n', 'blobId': 'new-blob'},
              },
            },
            'c0',
          ],
        ],
      ]);

      await api.save(
        accountId,
        base: SieveRulesSnapshot(state: State('st1'), scripts: const []),
        content: '# new',
        activate: false,
      );

      final set = adapter.requests[2]['methodCalls'][0][1];
      expect(set['create']['managed']['name'], 'twake-mail-rules');
      expect(set.containsKey('onSuccessActivateScript'), isFalse);
    });

    test('stops before writing when validation fails', () async {
      final (api, adapter) = build(uploadAndValidate(
        validateError: {'type': 'invalidScript', 'description': 'line 3'},
      ));

      await expectLater(
        api.save(accountId, base: base, content: '# bad', activate: true),
        throwsA(isA<SieveScriptRejectedException>()
            .having((e) => e.type, 'type', 'invalidScript')
            .having((e) => e.description, 'description', 'line 3')),
      );
      expect(adapter.requests, hasLength(2));
    });

    test('maps stateMismatch to a conflict', () async {
      final (api, _) = build([
        ...uploadAndValidate(),
        [
          [
            'error',
            {'type': 'stateMismatch'},
            'c0',
          ],
        ],
      ]);

      await expectLater(
        api.save(accountId, base: base, content: '# new', activate: true),
        throwsA(isA<SieveRulesConflictException>()),
      );
    });

    test('a 200 response with notUpdated is a failure', () async {
      final (api, _) = build([
        ...uploadAndValidate(),
        [
          [
            'SieveScript/set',
            {
              'accountId': 'acc',
              'notUpdated': {
                'm': {'type': 'overQuota', 'description': 'too many'},
              },
            },
            'c0',
          ],
        ],
      ]);

      await expectLater(
        api.save(accountId, base: base, content: '# new', activate: true),
        throwsA(isA<SieveScriptRejectedException>()
            .having((e) => e.type, 'type', 'overQuota')),
      );
    });
  });
}
