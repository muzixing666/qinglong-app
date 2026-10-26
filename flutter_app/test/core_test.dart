import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:qinglong_mobile/core.dart';
import 'package:qinglong_mobile/main.dart' show diffLines;

class FakeNative extends Native {
  final calls = <String>[];
  Completer<dynamic>? deferred;
  @override
  Future<dynamic> call(String action, [Json payload = const {}]) async {
    calls.add('$action:${payload['path'] ?? ''}');
    if (action == 'bootstrap') {
      return {'servers': [], 'activeId': '', 'nativeDock': false};
    }
    if (action == 'request') {
      return deferred?.future ??
          {
            'data': [
              {'id': 1, 'name': 'a'},
            ],
          };
    }
    return {};
  }
}

void main() {
  test('editable task payload excludes runtime fields without changing advanced settings', () {
    final clean = taskEditableValues({
      'id': 7,
      'name': 'a',
      'command': 'task a.py',
      'schedule': '0 9 * * *',
      'status': 1,
      'pid': 99,
      'createdAt': 'now',
      'updatedAt': 'now',
      'last_execution_time': 10,
      'labels': ['demo'],
      'task_before': 'echo demo',
      'work_dir': '/ql/data/scripts',
    });
    expect(
      clean.keys,
      unorderedEquals([
        'name',
        'command',
        'schedule',
        'labels',
        'task_before',
        'work_dir',
      ]),
    );
    expect(clean['task_before'], 'echo demo');
  });
  test('editor normalizes line endings without hiding real edits', () {
    expect(editorText('a\r\nb\rc\n'), 'a\nb\nc\n');
    expect(editorText('a\r\n'), editorText('a\n'));
    expect(editorText('a \n'), isNot(editorText('a\n')));
    expect(editorText('a\n\n'), isNot(editorText('a\n')));
  });
  test(
    'dependency operations refresh actual queued and cancelled states',
    () async {
      final model = PanelModel(native: FakeNative());
      await model.initialize();
      await model.load('dependencies');
      final item = model.cache['dependencies']!.first;
      await model.action('dependencies', 'reinstall', [item]);
      expect(dependencyState(model.cache['dependencies']!.first), '排队中');
      await model.action('dependencies', 'cancel', [item]);
      expect(dependencyState(model.cache['dependencies']!.first), '已取消');
      model.dispose();
    },
  );
  test(
    'demo application edits and dependency installs accept JSON payloads',
    () async {
      final panel = DemoPanel();
      await panel.request('PUT', '/apps', {
        'id': 61,
        'name': '示例应用',
        'scopes': ['envs'],
      });
      expect((panel.data['apps'] as List).first['scopes'], ['envs']);
      await panel.request('POST', '/dependencies', [
        {'name': 'curl', 'type': 2},
      ]);
      expect((panel.data['dependencies'] as List).last['name'], 'curl');
    },
  );
  test('dependency categories accept panel encodings and all eight states', () {
    expect(dependencyType({'type': 0}), 0);
    expect(dependencyType({'type': '1'}), 1);
    expect(dependencyType({'type': 'python3'}), 1);
    expect(dependencyType({'type': 'Linux'}), 2);
    expect(dependencyType({'type': 'future-runtime'}), -1);
    expect(
      [
        for (var i = 0; i < 8; i++) dependencyState({'status': '$i'}),
      ],
      ['安装中', '已安装', '安装失败', '卸载中', '已卸载', '卸载失败', '排队中', '已取消'],
    );
    expect(dependencyState({}), '未知状态');
    expect(dependencyState({'status': -1}), '未知状态');
    expect(dependencyState({'status': 30}), '未知状态');
  });
  test(
    'pinning preserves panel order across repeated deletions and rebuilds',
    () {
      final source = List<Json>.generate(
        100,
        (i) => {
          'id': i,
          'isPinned': i == 0 || i == 65 ? 1 : 0,
          'isDisabled': i >= 26 ? 1 : 0,
          'status': 1,
        },
      );
      final original = source.map(idOf).toList();
      for (var deletion = 0; deletion < 5; deletion++) {
        final result = pinnedTasksFirst(source);
        expect(result.take(2).map(idOf), ['0', '65']);
        expect(
          result.skip(2).map(idOf),
          source.where((r) => !flag(r['isPinned'])).map(idOf),
        );
        expect(result[2]['id'], 1);
        expect(disabled(result[2]), isFalse);
        expect(pinnedTasksFirst(result).map(idOf), result.map(idOf));
        expect(
          source.map(idOf),
          original.where(
            (id) => int.parse(id) < 26 || int.parse(id) >= 26 + deletion,
          ),
        );
        source.removeWhere((r) => r['id'] == 26 + deletion);
      }
    },
  );
  test('quoted subscription filters import without executing shell text', () {
    final result = subscriptionCommand(
      'ql repo https://github.com/example/demo.git "jd_|task_" "exclude" "utils" "main"',
    );
    expect(result?['name'], 'demo');
    expect(result?['whitelist'], 'jd_|task_');
    expect(result?['branch'], 'main');
    expect(
      subscriptionCommand('ql raw https://example.com/a.py')?['type'],
      'file',
    );
    expect(
      () => subscriptionCommand('ql repo https://example.com/x.git; echo hi'),
      throwsA(isA<ApiFailure>()),
    );
    expect(
      () => subscriptionCommand('ql repo "unfinished'),
      throwsA(isA<ApiFailure>()),
    );
  });
  test(
    'script task quoting roundtrips apostrophes spaces and shell punctuation',
    () {
      for (final name in ["a'b.py", 'a b.js', r'a$(echo).py']) {
        expect(
          scriptCandidates(scriptCommand(name)),
          name.contains(r'$(') ? isEmpty : [name],
        );
      }
      expect(
        () => scriptCommand('a.py', '../outside'),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
  group('JD parser', () {
    test('normalizes web cookie and decodes identity', () {
      final result = JdCookie.parse(
        'Cookie: extra=ignore; pt_pin=%E6%B5%8B%E8%AF%95;pt_key=abc;',
      );
      expect(result.identity, '测试');
      expect(result.cookie, 'pt_key=abc;pt_pin=%E6%B5%8B%E8%AF%95;');
      expect(result.type, contains('来源未判定'));
    });
    test('export and wskey remain distinct', () {
      expect(
        JdCookie.parse("export JD_COOKIE='pt_key=abc;pt_pin=user;'").identity,
        'user',
      );
      expect(JdCookie.parse('pin=user;wskey=abc;').type, 'WSKEY');
    });
    for (final invalid in [
      'pt_key=abc;',
      'pt_pin=user;',
      'pt_key=a;pt_pin=a;pt_pin=b;',
      'pt_key=a;pt_pin=b;wskey=c;',
      'pt_key=a;pt_pin=%XX;',
      'pt_key=a\n;pt_pin=b;',
    ]) {
      test(
        'rejects malformed ${invalid.hashCode}',
        () => expect(() => JdCookie.parse(invalid), throwsA(isA<ApiFailure>())),
      );
    }
  });
  test('task command handles quoted names and rejects evaluation', () {
    expect(scriptCandidates('task "daily/a b.py"'), ['daily/a b.py']);
    expect(scriptCandidates('node -e "evil.js"'), isEmpty);
    expect(scriptCandidates(r'task $(echo evil.js)'), isEmpty);
    expect(scriptCandidates('python /ql/data/scripts/daily/a.py'), [
      'daily/a.py',
    ]);
  });
  test('metadata and cron validation', () {
    final result = scriptMetadata(
      'a.js',
      '// cron: 0 2 * * *\nconst env = new Env("Daily task");',
    );
    expect(result['schedule'], '0 2 * * *');
    expect(result['name'], 'Daily task');
    expect(validCron('*/15 * * * *'), isTrue);
    expect(validCron('0 99 * * *'), isFalse);
    expect(validCron('0 2 * *'), isFalse);
    expect(validCron('0 */0 * * *'), isFalse);
  });
  test('state distinguishes running disabled and queued', () {
    expect(taskState({'status': 0}), '运行中');
    expect(taskState({'status': 3}), '排队中');
    expect(taskState({'status': 1, 'isDisabled': 1}), '已禁用');
    expect(taskState({'status': 1, 'isDisabled': 0}), '待运行');
  });
  test('tree preserves parent and full path', () {
    final list = flatten([
      {
        'title': 'daily',
        'type': 'directory',
        'children': [
          {'title': 'a.py', 'type': 'file'},
        ],
      },
    ]);
    expect(filePath(list.last), 'daily/a.py');
  });
  test('diff reconstructs the selected historical version', () {
    final diff = diffLines('a\nb\nc', 'a\nz\nc');
    expect(diff, contains('- b'));
    expect(diff, contains('+ z'));
    expect(
      diff
          .where((s) => !s.startsWith('- '))
          .map((s) => s.substring(2))
          .join('\n'),
      'a\nz\nc',
    );
  });
  test('bounded diff supports large files', () {
    expect(
      diffLines(
        List.filled(1000, 'a').join('\n'),
        List.filled(1000, 'b').join('\n'),
      ).first,
      contains('较大'),
    );
  });
  test('cached page loads avoid repeat request', () async {
    final native = FakeNative(), m = PanelModel(native: native);
    m.activeId = 'a';
    await m.load('tasks');
    await m.load('tasks');
    expect(native.calls.where((c) => c == 'request:/crons').length, 1);
    await m.load('tasks', force: true);
    expect(native.calls.where((c) => c == 'request:/crons').length, 2);
    m.dispose();
  });
  test(
    'deduplicates in-flight loads and discards switched-panel result',
    () async {
      final native = FakeNative()..deferred = Completer<dynamic>(),
          m = PanelModel(native: native);
      m.activeId = 'a';
      final first = m.load('envs'), second = m.load('envs');
      expect(identical(first, second), isTrue);
      m.epoch++;
      native.deferred!.complete({
        'data': [
          {'id': 1, 'value': 'old-panel'},
        ],
      });
      await first;
      expect(m.cache.containsKey('envs'), isFalse);
      m.dispose();
    },
  );
  test('run/stop patch one task without reload', () async {
    final native = FakeNative(), m = PanelModel(native: native);
    m.activeId = 'a';
    m.cache['tasks'] = [
      {'id': 1, 'status': 1, 'isDisabled': 0},
      {'id': 2, 'status': 1, 'isDisabled': 1},
    ];
    await m.action('tasks', 'run', [m.cache['tasks']!.first]);
    expect(m.cache['tasks']!.first['status'], 0);
    expect(m.cache['tasks']!.last['isDisabled'], 1);
    expect(native.calls, ['request:/crons/run']);
    await m.action('tasks', 'stop', [m.cache['tasks']!.first]);
    expect(m.cache['tasks']!.first['status'], 1);
    m.dispose();
  });
  test('demo history restore has atomic hash precondition', () async {
    final demo = DemoPanel();
    final list = await demo.request(
      'GET',
      '/scripts/history?filename=backup.py',
      null,
    );
    expect(list['versions'], isNotEmpty);
    await expectLater(
      demo.request('PUT', '/scripts/history/restore', {
        'filename': 'backup.py',
        'expectedHash': 'wrong',
      }),
      throwsA(isA<ApiFailure>()),
    );
    final detail = await demo.request(
      'GET',
      '/scripts/history/detail?filename=backup.py',
      null,
    );
    await demo.request('PUT', '/scripts/history/restore', {
      'filename': 'backup.py',
      'expectedHash': detail['currentHash'],
    });
    expect(digest(demo.content['backup.py']!), detail['version']['hash']);
  });
}
