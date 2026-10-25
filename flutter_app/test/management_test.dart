import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:qinglong_mobile/core.dart';

class UploadNative extends Native {
  final calls = <Json>[];
  int? failure;
  Completer<dynamic>? forecast;
  @override
  Future<dynamic> call(String action, [Json payload = const {}]) async {
    if (action == 'forecastTasks') {
      return forecast?.future ??
          {
            'rows': [
              {'id': '1', 'next': 1792803600000, 'state': 'estimated'},
            ],
            'source': 'panel',
            'zone': 'Asia/Shanghai',
          };
    }
    calls.add({...payload});
    if (payload['path'] == '/system/config') {
      return {
        'data': {
          'info': {'timezone': 'Asia/Shanghai'},
        },
      };
    }
    if (payload['method'] == 'GET') return {'data': <Json>[]};
    if (payload['path'] == '/crons' && failure != null) {
      throw ApiFailure('mock task failure', failure!);
    }
    return {'data': null};
  }

  int writes(String path) =>
      calls.where((c) => c['path'] == path && c['method'] == 'POST').length;
}

void main() {
  test(
    'common task schedule presets are valid and include useful calendar rules',
    () {
      expect(taskSchedulePresets.length, 6);
      expect(taskSchedulePresets.values.every(validCron), isTrue);
      expect(taskSchedulePresets['每 5 分钟'], '*/5 * * * *');
      expect(taskSchedulePresets['周一 09:00'], '0 9 * * 1');
    },
  );
  Json values() => {
    'filename': 'sample.py',
    'path': '',
    'name': 'Sample',
    'command': 'task sample.py',
    'schedule': '0 9 * * *',
    'createTask': true,
  };
  PanelModel model(UploadNative native) =>
      PanelModel(native: native)..activeId = 'test-only';
  test(
    'dates use actual creation/update fields and seconds or milliseconds',
    () {
      expect(createdTime({'timestamp': 'modified'}), isNull);
      expect(updatedTime({'timestamp': 'legacy-record'}), isNull);
      expect(panelDate(1792803600), panelDate(1792803600000));
      expect(panelDate('invalid'), isNull);
      expect(panelDate(0), isNull);
      expect(dateLabel(null), '面板未提供');
      expect(
        durationLabel({
          'last_execution_time': 1792803600,
          'last_running_time': 125,
        }),
        '2 分 5 秒',
      );
      expect(
        durationLabel({
          'last_execution_time': 1792803600,
          'last_running_time': 0,
        }),
        '0 秒',
      );
      expect(durationLabel({'last_running_time': 125}), '尚无记录');
    },
  );
  test('invalid task prevents any script upload', () async {
    final native = UploadNative(),
        m = model(native),
        session = ScriptUploadSession(model(native), 'print(1)');
    await expectLater(
      session.submit({...values(), 'schedule': 'bad'}),
      throwsA(isA<ApiFailure>()),
    );
    expect(native.writes('/scripts'), 0);
    expect(native.writes('/crons'), 0);
    session.model.dispose();
    m.dispose();
  });
  test('script upload and task creation complete in order', () async {
    final native = UploadNative(),
        m = model(native),
        session = ScriptUploadSession(m, 'print(1)');
    await session.submit(values());
    expect(native.writes('/scripts'), 1);
    expect(native.writes('/crons'), 1);
    final paths = native.calls
        .where((c) => c['method'] == 'POST')
        .map((c) => c['path'])
        .toList();
    expect(paths, ['/scripts', '/crons']);
    m.dispose();
  });
  test(
    'task validation rejection retries only task and preserves uploaded file',
    () async {
      final native = UploadNative()..failure = 400,
          m = model(native),
          session = ScriptUploadSession(m, 'print(1)');
      await expectLater(session.submit(values()), throwsA(isA<ApiFailure>()));
      native.failure = null;
      await session.submit({...values(), 'schedule': '0 10 * * *'});
      expect(native.writes('/scripts'), 1);
      expect(native.writes('/crons'), 2);
      m.dispose();
    },
  );
  test('unknown task result is never automatically resubmitted', () async {
    final native = UploadNative()..failure = 0,
        m = model(native),
        session = ScriptUploadSession(m, 'print(1)');
    await expectLater(session.submit(values()), throwsA(isA<ApiFailure>()));
    native.failure = null;
    await expectLater(session.submit(values()), throwsA(isA<ApiFailure>()));
    expect(native.writes('/scripts'), 1);
    expect(native.writes('/crons'), 1);
    m.dispose();
  });
  test(
    'switched panel and changed uploaded destination prevent further writes',
    () async {
      final native = UploadNative()..failure = 400,
          m = model(native),
          session = ScriptUploadSession(m, 'print(1)');
      await expectLater(session.submit(values()), throwsA(isA<ApiFailure>()));
      await expectLater(
        session.submit({...values(), 'filename': 'changed.py'}),
        throwsA(isA<ApiFailure>()),
      );
      m.epoch++;
      await expectLater(session.submit(values()), throwsA(isA<ApiFailure>()));
      expect(native.writes('/scripts'), 1);
      expect(native.writes('/crons'), 1);
      m.dispose();
    },
  );
  test(
    'forecasts use panel timezone and suppress disabled task schedule',
    () async {
      final native = UploadNative(), m = model(native);
      m.cache['tasks'] = [
        {'id': 1, 'schedule': '0 9 * * *', 'isDisabled': 0},
      ];
      await m.forecastTasks();
      expect(m.forecasts['1']?['zone'], 'Asia/Shanghai');
      expect(m.nextTaskTime({'id': 1}), contains('估算'));
      expect(m.nextTaskTime({'id': 1, 'isDisabled': 1}), '已禁用');
      m.dispose();
    },
  );
  test('forecast response from previous panel is discarded', () async {
    final native = UploadNative()..forecast = Completer<dynamic>(),
        m = model(native);
    m.cache['tasks'] = [
      {'id': 1, 'schedule': '0 9 * * *'},
    ];
    final pending = m.forecastTasks();
    await Future<void>.delayed(Duration.zero);
    m.epoch++;
    native.forecast!.complete({
      'rows': [
        {'id': '1', 'next': 1792803600000},
      ],
    });
    await pending;
    expect(m.forecasts, isEmpty);
    m.dispose();
  });
  test(
    'demo cache cleanup matches server semantics and does not affect Linux',
    () async {
      final panel = DemoPanel();
      (panel.data['dependencies'] as List).add({
        'id': 90,
        'name': 'bash',
        'type': 2,
        'status': 1,
      });
      await panel.request('PUT', '/system/config/dependence-clean', {
        'type': 'python3',
      });
      final list = panel.data['dependencies'] as List;
      expect(list.first['status'], 2);
      expect(list.last['status'], 1);
      await expectLater(
        panel.request('PUT', '/system/config/dependence-clean', {
          'type': 'linux',
        }),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
}
