import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmail_ui_user/main/bindings/network/jmap_header_form_interceptor.dart';

class _Capture extends RequestInterceptorHandler {
  RequestOptions? options;

  @override
  void next(RequestOptions requestOptions) => options = requestOptions;
}

class _CaptureResponse extends ResponseInterceptorHandler {
  Response? response;

  @override
  void next(Response response) => this.response = response;
}

void main() {
  final interceptor = JmapHeaderFormInterceptor();

  test('asks for the raw form of RFC 2369 and Return-Path headers only', () {
    final handler = _Capture();
    interceptor.onRequest(
      RequestOptions(data: {
        'using': ['urn:ietf:params:jmap:mail'],
        'methodCalls': [
          [
            'Email/get',
            {
              'accountId': 'a',
              'properties': [
                'id',
                'header:List-Unsubscribe:asText',
                'header:List-Post:asText',
                'header:Return-Path:asText',
                'header:X-Priority:asText',
              ],
            },
            'c0',
          ],
        ],
      }),
      handler,
    );

    final properties = ((handler.options!.data as Map)['methodCalls'] as List)
        .first[1]['properties'];
    expect(properties, [
      'id',
      'header:List-Unsubscribe:asRaw',
      'header:List-Post:asRaw',
      'header:Return-Path:asRaw',
      'header:X-Priority:asText',
    ]);
  });

  test('maps the answers back to the keys the app reads', () {
    final handler = _CaptureResponse();
    interceptor.onResponse(
      Response(
        requestOptions: RequestOptions(),
        data: {
          'methodResponses': [
            [
              'Email/get',
              {
                'list': [
                  {
                    'id': 'e1',
                    'header:List-Unsubscribe:asRaw': ' <mailto:u@x.test>',
                    'header:X-Priority:asText': '1',
                  },
                ],
              },
              'c0',
            ],
            [
              'Mailbox/get',
              {
                'list': [
                  {'id': 'm1', 'header:List-Post:asRaw': 'untouched'},
                ],
              },
              'c1',
            ],
          ],
        },
      ),
      handler,
    );

    final responses = (handler.response!.data as Map)['methodResponses'] as List;
    final email = responses[0][1]['list'][0] as Map;
    expect(email['header:List-Unsubscribe:asText'], ' <mailto:u@x.test>');
    expect(email.containsKey('header:List-Unsubscribe:asRaw'), isFalse);
    expect(email['header:X-Priority:asText'], '1');
    expect(responses[1][1]['list'][0]['header:List-Post:asRaw'], 'untouched');
  });

  test('leaves requests that are not JMAP untouched', () {
    final handler = _Capture();
    interceptor.onRequest(RequestOptions(data: 'plain body'), handler);
    expect(handler.options!.data, 'plain body');
  });
}
