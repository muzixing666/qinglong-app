import 'package:flutter_test/flutter_test.dart';
import 'package:qinglong_mobile/core.dart';

class DeleteNative extends Native {
  final panel = DemoPanel();
  final calls = <Json>[];
  String? failDelete;
  void Function()? afterTaskDelete;
  void Function(String, String)? onRequest;
  @override
  Future<dynamic> call(String action, [Json payload = const {}]) async {
    if (action == 'forecastTasks') return {'rows': []};
    final method = str(payload['method']), path = str(payload['path']);
    calls.add({...payload});
    onRequest?.call(method, path);
    if (method == 'DELETE' && path == failDelete) {
      throw ApiFailure('permission denied', 403);
    }
    final result = await panel.request(method, path, payload['body']);
    if (method == 'DELETE' && path == '/crons') afterTaskDelete?.call();
    return {'data': result};
  }
}

void main() {
  Json task(int id, String command) => {
    'id': id,
    'name': 'Task $id',
    'command': command,
    'schedule': '0 9 * * *',
  };
  Json file(String name, [String parent = '']) => {
    'title': name,
    'parent': parent,
    'type': 'file',
  };
  (PanelModel, DeleteNative) fixture() {
    final native = DeleteNative();
    native.panel.data['crons'] = [task(1, 'task backup.py')];
    native.panel.data['scripts'] = [file('backup.py')];
    final model = PanelModel(native: native)..activeId = 'test';
    return (model, native);
  }

  test('deleting a task keeps its script by default', () async {
    final (model, native) = fixture();
    final result = await model.deleteTasksAndScripts([
      task(1, 'task backup.py'),
    ], {});
    expect(native.panel.data['crons'], isEmpty);
    expect(native.panel.data['scripts'], hasLength(1));
    expect(result.removedScripts, isEmpty);
    expect(
      native.calls.where(
        (c) => c['path'] == '/scripts' && c['method'] == 'DELETE',
      ),
      isEmpty,
    );
  });
  test('selected script is deleted once with the official object body after its task', () async {
    final (model, native) = fixture();
    final result = await model.deleteTasksAndScripts(
      [task(1, 'task backup.py')],
      {'backup.py'},
    );
    expect(result.removedScripts, ['backup.py']);
    final writes = native.calls.where((c) => c['method'] == 'DELETE').toList();
    expect(writes.map((c) => c['path']), ['/crons', '/scripts']);
    expect(writes.last['body'], {
      'filename': 'backup.py',
      'path': '',
      'type': 'file',
    });
  });
  test('remaining task references retain a shared script', () async {
    final (model, native) = fixture();
    (native.panel.data['crons'] as List).add(task(2, 'node backup.py'));
    final result = await model.deleteTasksAndScripts(
      [task(1, 'task backup.py')],
      {'backup.py'},
    );
    expect(result.retainedScripts, ['backup.py']);
    expect(native.panel.data['scripts'], hasLength(1));
  });
  test(
    'a reference created during task deletion also retains the script',
    () async {
      final (model, native) = fixture();
      native.afterTaskDelete = () =>
          (native.panel.data['crons'] as List).add(task(9, 'task backup.py'));
      final result = await model.deleteTasksAndScripts(
        [task(1, 'task backup.py')],
        {'backup.py'},
      );
      expect(result.retainedScripts, ['backup.py']);
      expect(native.panel.data['scripts'], hasLength(1));
    },
  );
  test('failed task deletion never starts file deletion', () async {
    final (model, native) = fixture();
    native.failDelete = '/crons';
    await expectLater(
      model.deleteTasksAndScripts([task(1, 'task backup.py')], {'backup.py'}),
      throwsA(isA<ApiFailure>()),
    );
    expect(
      native.calls.where(
        (c) => c['path'] == '/scripts' && c['method'] == 'DELETE',
      ),
      isEmpty,
    );
  });
  test(
    'file failure is reported after the task has actually been removed',
    () async {
      final (model, native) = fixture();
      native.failDelete = '/scripts';
      final result = await model.deleteTasksAndScripts(
        [task(1, 'task backup.py')],
        {'backup.py'},
      );
      expect(native.panel.data['crons'], isEmpty);
      expect(result.failedScripts.keys, ['backup.py']);
      expect(native.panel.data['scripts'], hasLength(1));
    },
  );
  test('ambiguous basename, compound command and custom working directory are not guessed', () {
    final files = [file('demo.py', 'a'), file('demo.py', 'b')];
    expect(taskScriptPlan([task(1, 'task demo.py')], [], files).files, isEmpty);
    expect(
      taskScriptPlan([task(1, 'cd a && python demo.py')], [], files).files,
      isEmpty,
    );
    expect(
      taskScriptPlan(
        [
          {...task(1, 'task a/demo.py'), 'work_dir': '/tmp'},
        ],
        [],
        files,
      ).files,
      isEmpty,
    );
    expect(
      taskScriptPlan(
        [task(1, 'task /ql/data/scripts/a/demo.py')],
        [],
        files,
      ).files.keys,
      ['a/demo.py'],
    );
  });
  test('switching panels during preparation prevents mutations', () async {
    final (model, native) = fixture();
    native.onRequest = (method, path) {
      if (path == '/scripts') model.epoch++;
    };
    await expectLater(
      model.deleteTasksAndScripts([task(1, 'task backup.py')], {'backup.py'}),
      throwsA(isA<ApiFailure>()),
    );
    expect(native.calls.where((c) => c['method'] == 'DELETE'), isEmpty);
  });
  test('copied task retains editable configuration but has independent identity and ownership', () {
    final original = {
      ...task(1, 'task backup.py'),
      'status': 0,
      'sub_id': 8,
      'pid': 123,
      'labels': ['daily'],
      'task_before': 'echo before',
      'extra_schedules': [
        {'schedule': '0 10 * * *'},
      ],
    };
    final copy = taskCopyValues(original);
    expect(copy['name'], 'Task 1 副本');
    expect(copy.keys, isNot(contains('id')));
    expect(copy.keys, isNot(contains('sub_id')));
    expect(copy.keys, isNot(contains('status')));
    expect(copy['task_before'], 'echo before');
    (copy['labels'] as List).add('new');
    expect(original['labels'], ['daily']);
  });
}
