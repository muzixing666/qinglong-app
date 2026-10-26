import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinglong_mobile/core.dart';
import 'package:qinglong_mobile/main.dart';

class UiNative extends Native {
  final String? initialPage;
  UiNative({this.initialPage});
  final calls = <String>[];
  final copied = <String>[];
  @override
  Future<dynamic> call(String action, [Json payload = const {}]) async {
    calls.add(action);
    if (action == 'copyText') copied.add(str(payload['text']));
    if (action == 'pickScript') {
      return {
        'filename': 'upload-demo.py',
        'content': '# cron: 0 8 * * *\nprint(1)',
      };
    }
    if (action == 'bootstrap') {
      return {
        'servers': [],
        'activeId': '',
        'nativeDock': false,
        if (initialPage != null) 'shortcutPage': initialPage,
      };
    }
    return {};
  }
}

class _StrictTaskModel extends PanelModel {
  _StrictTaskModel() : super(native: UiNative());
  Json? sent;
  @override
  Future<dynamic> api(String method, String path, [dynamic body]) async {
    if (method == 'PUT' && path == '/crons') {
      sent = Map<String, dynamic>.from(body);
      const allowed = {
        'id',
        'name',
        'command',
        'schedule',
        'labels',
        'extra_schedules',
        'task_before',
        'task_after',
        'log_name',
        'allow_multiple_instances',
        'work_dir',
        'sub_id',
      };
      if (sent!.keys.any((key) => !allowed.contains(key))) {
        throw ApiFailure('validation failed (HTTP 400)');
      }
    }
    return super.api(method, path, body);
  }
}

class _DelayedEnvModel extends PanelModel {
  _DelayedEnvModel() : super(native: UiNative());
  final gate = Completer<void>();
  bool first = true;
  @override
  Future<dynamic> api(String method, String path, [dynamic body]) async {
    if (first && method == 'PUT' && path.endsWith('/move')) {
      first = false;
      await gate.future;
    }
    return super.api(method, path, body);
  }
}

Future<void> frames(WidgetTester tester, [int count = 8]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<PanelModel> launch(WidgetTester tester, {PanelModel? supplied}) async {
  tester.view.reset();
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 3;
  final model = supplied ?? PanelModel(native: UiNative());
  await tester.pumpWidget(QinglongApp(model: model));
  await frames(tester);
  return model;
}

void main() {
  testWidgets('small configuration opens as a dismissible modal', (
    tester,
  ) async {
    await launch(tester);
    final host = tester.state<HomeState>(find.byType(Home));
    unawaited(
      host.form(
        '日志清理设置',
        [const Field('days', '保留天数')],
        {'days': '7'},
        (_) async {},
      ),
    );
    await frames(tester);
    expect(find.byType(Dialog), findsOneWidget);
    expect(tester.widget<Dialog>(find.byType(Dialog)).clipBehavior, Clip.antiAlias);
    expect(find.text('日志清理设置'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await frames(tester);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('放弃修改？'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('login history separates result time source and device', (
    tester,
  ) async {
    await launch(tester);
    final host = tester.state<HomeState>(find.byType(Home));
    unawaited(host.route(LoginHistoryPage(host: host)));
    await frames(tester);
    expect(find.text('登录成功'), findsOneWidget);
    expect(find.text('登录失败'), findsOneWidget);
    expect(find.text('IP：192.0.2.10'), findsOneWidget);
    expect(find.text('登录端：电脑端'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '失败'));
    await frames(tester);
    expect(find.text('登录成功'), findsNothing);
    expect(find.text('登录失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'cold shortcut selects its first page without loading tasks first',
    (tester) async {
      final model = await launch(
        tester,
        supplied: PanelModel(native: UiNative(initialPage: 'envs')),
      );
      expect(model.page, 'envs');
      expect(model.cache.containsKey('tasks'), isFalse);
      expect(find.text('环境变量'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('shortcut respects unsaved form changes before leaving', (
    tester,
  ) async {
    final model = await launch(tester);
    final host = tester.state<HomeState>(find.byType(Home));
    unawaited(
      host.form(
        '编辑测试',
        [const Field('name', '名称')],
        {'name': 'before'},
        (_) async {},
      ),
    );
    await frames(tester);
    await tester.enterText(find.byType(TextFormField), 'after');
    final denied = host.openShortcut('envs');
    await frames(tester);
    expect(find.text('放弃修改？'), findsOneWidget);
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('取消')),
    );
    await frames(tester);
    await denied;
    expect(find.byType(FormPage), findsOneWidget);
    expect(model.page, 'tasks');
    final accepted = host.openShortcut('scripts');
    await frames(tester);
    await tester.tap(find.text('确认'));
    await frames(tester);
    await accepted;
    expect(find.byType(FormPage), findsNothing);
    expect(model.page, 'scripts');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('existing task edit submits only panel-editable fields', (
    tester,
  ) async {
    final strict = _StrictTaskModel();
    final model = await launch(tester, supplied: strict);
    final host = tester.state<HomeState>(find.byType(Home));
    model.cache['tasks']!.first['log_name'] = 'legacy(unsafe)';
    unawaited(host.taskForm(model.cache['tasks']!.first));
    await frames(tester);
    await tester.enterText(find.byType(TextFormField).last, '0 10 * * *');
    await tester.tap(find.text('保存'));
    await frames(tester);
    expect(find.byType(FormPage), findsNothing);
    expect(strict.sent?['id'], 1);
    expect(strict.sent?['schedule'], '0 10 * * *');
    expect(strict.sent?.containsKey('createdAt'), isFalse);
    expect(
      strict.sent!.keys,
      unorderedEquals(['id', 'name', 'command', 'schedule']),
    );
    expect(model.cache['tasks']!.first['status'], 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('a real handle drag reorders the card without losing its state', (
    tester,
  ) async {
    final model = await launch(tester);
    tester.view.physicalSize = const Size(1080, 2400);
    model.navigate('envs');
    await frames(tester);
    final handles = find.byIcon(Icons.drag_handle);
    final start = tester.getCenter(handles.first),
        end = tester.getCenter(handles.at(1));
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 100));
    for (var step = 1; step <= 12; step++) {
      await gesture.moveTo(
        Offset.lerp(start, end + const Offset(0, 20), step / 12)!,
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await frames(tester, 4);
    await gesture.up();
    await frames(tester, 12);
    expect(model.cache['envs']!.map(idOf).toList(), ['32', '31', '33']);
    expect(rows(model.demoPanel.data['envs']).map(idOf).toList(), [
      '32',
      '31',
      '33',
    ]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    tester.view.reset();
  });
  testWidgets(
    'consecutive drags update immediately while remote saves are queued',
    (tester) async {
      final delayed = _DelayedEnvModel();
      final model = await launch(tester, supplied: delayed);
      model.navigate('envs');
      await frames(tester);
      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .onReorderItem!(0, 1);
      await frames(tester, 1);
      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .onReorderItem!(2, 0);
      await frames(tester, 1);
      expect(model.cache['envs']!.map(idOf).toList(), ['33', '32', '31']);
      expect(rows(model.demoPanel.data['envs']).map(idOf).toList(), [
        '31',
        '32',
        '33',
      ]);
      expect(
        tester
            .widgetList<ReorderableDragStartListener>(
              find.byType(ReorderableDragStartListener),
            )
            .every((w) => w.enabled),
        isTrue,
      );
      delayed.gate.complete();
      await frames(tester);
      expect(rows(model.demoPanel.data['envs']).map(idOf).toList(), [
        '33',
        '32',
        '31',
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('environment order persists and name groups collapse', (
    tester,
  ) async {
    final model = await launch(tester);
    model.demoPanel.data['envs'] = <Json>[
      {
        'id': 31,
        'name': 'JD_COOKIE',
        'value': 'demo1',
        'remarks': '第一账号',
        'status': 0,
      },
      {'id': 32, 'name': 'OTHER', 'value': 'demo', 'status': 0},
      {
        'id': 33,
        'name': 'JD_COOKIE',
        'value': 'demo2',
        'remarks': '第二账号',
        'status': 0,
      },
    ];
    model.navigate('envs');
    await frames(tester);
    await tester.tap(find.text('分组'));
    await frames(tester);
    expect(find.byKey(const ValueKey('env-group-JD_COOKIE')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('env-group-JD_COOKIE')));
    await frames(tester);
    expect(find.text('第一账号'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('env-group-JD_COOKIE')));
    await frames(tester);
    final groupTop = tester
        .getTopLeft(find.byKey(const ValueKey('env-group-JD_COOKIE')))
        .dy;
    final order = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView).first,
    );
    order.onReorderItem!(1, 2);
    await frames(tester);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('env-group-JD_COOKIE'))).dy,
      groupTop,
    );
    expect(model.cache['envs']!.map(idOf).toList(), ['32', '33', '31']);
    expect(rows(model.demoPanel.data['envs']).map(idOf).toList(), [
      '32',
      '33',
      '31',
    ]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('file folder deletion requires an explicit confirmation', (
    tester,
  ) async {
    final model = await launch(tester);
    model.demoPanel.data['scripts'] = <Json>[
      {
        'title': 'demo-folder',
        'parent': '',
        'type': 'directory',
        'children': <Json>[
          {'title': 'inside.py', 'type': 'file'},
        ],
      },
    ];
    model.demoPanel.content['demo-folder/inside.py'] = 'demo';
    model.navigate('scripts');
    await frames(tester);
    await tester.longPress(find.text('demo-folder').first);
    await frames(tester);
    await tester.tap(find.text('删除文件夹'));
    await frames(tester);
    expect(find.text('确认删除文件夹？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await frames(tester);
    expect(
      model.demoPanel.content.containsKey('demo-folder/inside.py'),
      isTrue,
    );
    await tester.longPress(find.text('demo-folder').first);
    await frames(tester);
    await tester.tap(find.text('删除文件夹'));
    await frames(tester);
    await tester.tap(find.text('确认'));
    await frames(tester);
    expect(model.demoPanel.data['scripts'], isEmpty);
    expect(
      model.demoPanel.content.containsKey('demo-folder/inside.py'),
      isFalse,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('dock shell stays fixed during drag and overscroll', (
    tester,
  ) async {
    final model = await launch(tester);
    final shell = find.byKey(const ValueKey('dock-fixed-shell'));
    final before = tester.getRect(shell);
    expect(tester.widget<ClipRRect>(shell).clipBehavior, isNot(Clip.none));
    final gesture = await tester.startGesture(
      before.centerLeft + const Offset(24, 0),
    );
    for (final dx in [
      before.width * .3,
      before.width * .65,
      before.width + 40,
    ]) {
      await gesture.moveTo(before.centerLeft + Offset(dx, 0));
      await frames(tester, 3);
      expect(tester.getRect(shell), before);
    }
    await gesture.up();
    await frames(tester);
    expect(model.page, 'more');
    expect(tester.getRect(shell), before);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('download and agreement pages show their actual content', (
    tester,
  ) async {
    await launch(tester);
    final host = tester.state<HomeState>(find.byType(Home));
    unawaited(host.route(const AppInfoPage()));
    await frames(tester);
    expect(find.text(downloadUrl), findsOneWidget);
    expect(find.text('前往下载'), findsOneWidget);
    await tester.tap(find.byTooltip('返回').first);
    await frames(tester);
    unawaited(host.route(const AppInfoPage(agreement: true)));
    await frames(tester);
    expect(find.textContaining('青龙掌控用户协议'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'editor opens its shell before a slow file request and handles failure',
    (tester) async {
      final model = await launch(tester);
      final host = tester.state<HomeState>(find.byType(Home));
      final pending = Completer<String>();
      unawaited(
        host.route(
          EditorPage(
            host: host,
            kind: 'scripts',
            node: {'title': 'slow.py', 'parent': ''},
            content: '',
            load: pending.future,
            scope: model.epoch,
          ),
        ),
      );
      await frames(tester);
      expect(find.byType(EditorPage), findsOneWidget);
      expect(find.text('正在读取脚本…'), findsOneWidget);
      pending.completeError(ApiFailure('读取失败演示'));
      await frames(tester);
      expect(find.text('读取失败演示'), findsOneWidget);
      await tester.tap(find.byTooltip('返回').first);
      await frames(tester);
      expect(find.byType(EditorPage), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'task deletion defaults to keeping files and cancellation makes no changes',
    (tester) async {
      final model = await launch(tester);
      final original = model.cache['tasks']!.first;
      model.demoPanel.data['crons'] = [original];
      model.cache['tasks'] = [original];
      model.changed();
      await frames(tester);
      await tester.tap(find.text('更多').first);
      await frames(tester);
      await tester.tap(find.text('删除'));
      await frames(tester);
      final option = find.byKey(const ValueKey('delete-task-scripts'));
      expect(tester.widget<CheckboxListTile>(option).value, isFalse);
      await tester.tap(option);
      await frames(tester);
      expect(find.text('删除任务及 1 个脚本'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await frames(tester);
      expect(model.demoPanel.data['crons'], hasLength(1));
      await tester.tap(find.text('更多').first);
      await frames(tester);
      await tester.tap(find.text('删除'));
      await frames(tester);
      expect(tester.widget<CheckboxListTile>(option).value, isFalse);
      await tester.tap(find.text('仅删除任务'));
      await frames(tester, 15);
      expect(model.demoPanel.data['crons'], isEmpty);
      expect(
        rows(model.demoPanel.data['scripts'])
            .any((r) => r['title'] == 'backup.py'),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('task deletion can explicitly remove its identified script', (
    tester,
  ) async {
    final model = await launch(tester);
    final original = model.cache['tasks']!.first;
    model.demoPanel.data['crons'] = [original];
    model.cache['tasks'] = [original];
    model.changed();
    await frames(tester);
    await tester.tap(find.text('更多').first);
    await frames(tester);
    await tester.tap(find.text('删除'));
    await frames(tester);
    await tester.tap(find.byKey(const ValueKey('delete-task-scripts')));
    await frames(tester);
    await tester.tap(find.text('删除任务及 1 个脚本'));
    await frames(tester, 15);
    expect(model.demoPanel.data['crons'], isEmpty);
    expect(
      rows(model.demoPanel.data['scripts'])
          .any((r) => r['title'] == 'backup.py'),
      isFalse,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('copy task creates a new identity while retaining the original', (
    tester,
  ) async {
    final model = await launch(tester);
    final original = {...model.cache['tasks']!.first};
    final count = (model.demoPanel.data['crons'] as List).length;
    await tester.tap(find.text('更多').first);
    await frames(tester);
    await tester.tap(find.text('复制任务'));
    await frames(tester);
    expect(find.text('复制任务'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      '${original['name']} 副本',
    );
    await tester.tap(find.text('保存'));
    await frames(tester, 15);
    final tasks = rows(model.demoPanel.data['crons']);
    expect(tasks, hasLength(count + 1));
    expect(tasks.where((r) => idOf(r) == idOf(original)), hasLength(1));
    final copy = tasks.firstWhere((r) => r['name'] == '${original['name']} 副本');
    expect(idOf(copy), isNot(idOf(original)));
    expect(copy['command'], original['command']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'task presets fill the visible rule, retain repeated selection and allow custom edits',
    (tester) async {
      final model = await launch(tester);
      await tester.tap(find.text('新建'));
      await frames(tester);
      await tester.enterText(find.byType(TextFormField).at(0), '预设规则验证');
      await tester.enterText(find.byType(TextFormField).at(1), 'task demo.py');
      final hourly = find.byKey(const ValueKey('preset-schedule-0 * * * *'));
      await tester.scrollUntilVisible(
        hourly,
        180,
        scrollable: find
            .descendant(
              of: find.byType(FormPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(hourly);
      await frames(tester);
      final field = find.byType(TextFormField).last;
      expect(tester.widget<TextFormField>(field).controller!.text, '0 * * * *');
      await tester.tap(hourly);
      await frames(tester);
      expect(tester.widget<TextFormField>(field).controller!.text, '0 * * * *');
      await tester.enterText(field, '15 8 * * *');
      await frames(tester);
      expect(
        tester
            .widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .where((chip) => chip.selected),
        isEmpty,
      );
      await tester.tap(hourly);
      await frames(tester);
      await tester.tap(find.text('保存'));
      await frames(tester, 15);
      expect(
        model.cache['tasks']!.firstWhere(
          (row) => row['name'] == '预设规则验证',
        )['schedule'],
        '0 * * * *',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'data refresh and dock tabs preserve theme and retained page state',
    (tester) async {
      final model = await launch(tester);
      final theme = tester.widget<MaterialApp>(find.byType(MaterialApp)).theme;
      final tasks = tester.element(
        find.byWidgetPredicate(
          (w) => w is ResourcePage && w.resource == 'tasks',
          skipOffstage: false,
        ),
      );
      model.navigate('envs');
      await frames(tester);
      model.navigate('tasks');
      await frames(tester);
      model.cache['tasks']!.first['status'] = 0;
      model.changed();
      await frames(tester);
      expect(
        identical(
          theme,
          tester.widget<MaterialApp>(find.byType(MaterialApp)).theme,
        ),
        isTrue,
      );
      expect(
        identical(
          tasks,
          tester.element(
            find.byWidgetPredicate(
              (w) => w is ResourcePage && w.resource == 'tasks',
              skipOffstage: false,
            ),
          ),
        ),
        isTrue,
      );
      model.dark = true;
      model.changed();
      await frames(tester);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.brightness,
        Brightness.dark,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('task details show metadata and history opens a static log', (
    tester,
  ) async {
    final model = await launch(tester);
    final host = tester.state<HomeState>(find.byType(Home));
    final details = host.taskDetails(model.cache['tasks']!.first);
    await frames(tester);
    expect(find.text('任务 ID'), findsOneWidget);
    expect(find.text('创建时间'), findsOneWidget);
    expect(find.text('最后时长'), findsOneWidget);
    await tester.tap(find.text('日志历史'));
    await frames(tester, 14);
    expect(find.text('2026-10-23-070000.log'), findsOneWidget);
    await tester.tap(find.text('2026-10-23-070000.log'));
    await frames(tester, 14);
    expect(find.byType(LogPage), findsOneWidget);
    expect(tester.widget<LogPage>(find.byType(LogPage)).live, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    // The navigator is disposed together with the app.
    details.ignore();
  });
  testWidgets('applications copy both identifiers without showing secret', (
    tester,
  ) async {
    final model = await launch(tester);
    model.navigate('more');
    await frames(tester);
    await tester.ensureVisible(find.text('应用管理'));
    await frames(tester);
    await tester.tap(find.text('应用管理'));
    await frames(tester);
    expect(find.textContaining('demo-only'), findsNothing);
    await tester.tap(find.byTooltip('复制 Client ID'));
    await frames(tester);
    await tester.tap(find.byTooltip('复制 Client Secret'));
    await frames(tester);
    expect((model.native as UiNative).copied, ['demo-client', 'demo-only']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'local script upload and task fields share one form and one save',
    (tester) async {
      final model = await launch(tester);
      await tester.tap(find.text('上传'));
      await frames(tester);
      await tester.tap(find.text('本地上传'));
      await frames(tester, 12);
      expect(find.text('上传脚本与定时任务'), findsOneWidget);
      expect(find.text('* 文件名'), findsOneWidget);
      expect(find.text('* 任务名称'), findsOneWidget);
      expect(find.text('* 定时规则'), findsOneWidget);
      await tester.tap(find.text('上传并保存'));
      await frames(tester, 24);
      expect(find.text('上传脚本与定时任务'), findsNothing);
      expect(
        model.cache['tasks']!.any(
          (row) => row['command'] == 'task upload-demo.py',
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'dependency mirror save and cache cleanup use explicit selection and confirmation',
    (tester) async {
      final model = await launch(tester),
          host = tester.state<HomeState>(find.byType(Home));
      final settings = host.dependencySettings();
      await frames(tester, 12);
      expect(find.text('依赖设置'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField).at(1),
        'https://registry.example.test',
      );
      await frames(tester, 2);
      await tester.tap(find.text('保存').at(1));
      await frames(tester, 15);
      expect(
        model.demoPanel.systemConfig['nodeMirror'],
        'https://registry.example.test',
      );
      await tester.scrollUntilVisible(
        find.text('清理 Python'),
        220,
        scrollable: find
            .descendant(
              of: find.byType(DependencySettingsPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('清理 Python'));
      await frames(tester);
      expect(find.text('清理 Python 依赖缓存？'), findsOneWidget);
      expect((model.demoPanel.data['dependencies'] as List).first['status'], 1);
      await tester.tapAt(const Offset(4, 80));
      await frames(tester);
      expect((model.demoPanel.data['dependencies'] as List).first['status'], 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      settings.ignore();
    },
  );
  testWidgets(
    'application permissions use checkboxes and preserve unknown scopes',
    (tester) async {
      final model = await launch(tester);
      (model.demoPanel.data['apps'] as List).first['scopes'] = [
        'crons',
        'legacy',
      ];
      model.navigate('more');
      await frames(tester);
      await tester.ensureVisible(find.text('应用管理'));
      await frames(tester);
      await tester.tap(find.text('应用管理'));
      await frames(tester);
      await tester.tap(find.text('示例应用'));
      await frames(tester);
      await tester.tap(find.text('编辑').last);
      await frames(tester);
      expect(find.text('编辑应用'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const ValueKey('scope-crons')))
            .value,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('scope-crons')));
      await tester.tap(find.byKey(const ValueKey('scope-envs')));
      await frames(tester);
      await tester.tap(find.text('保存'));
      await frames(tester, 15);
      expect((model.demoPanel.data['apps'] as List).first['scopes'], [
        'legacy',
        'envs',
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('empty permission selection prevents saving', (tester) async {
    var saved = false;
    await tester.pumpWidget(
      MaterialApp(
        home: FormPage(
          title: '权限验证',
          fields: const [
            Field(
              'scopes',
              '权限范围',
              required: true,
              multiple: true,
              options: applicationScopes,
            ),
          ],
          initial: const {'scopes': <String>[]},
          save: (_) async {
            saved = true;
          },
        ),
      ),
    );
    await tester.tap(find.text('保存'));
    await frames(tester);
    expect(saved, isFalse);
    expect(find.text('请至少勾选一项权限范围'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'form prompts only while its values differ from the initial state',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      Widget formPage() => FormPage(
        title: '脏状态验证',
        initial: const {
          'name': '原值',
          'enabled': false,
          'scopes': ['a', 'b'],
        },
        fields: const [
          Field('name', '名称'),
          Field('enabled', '启用', toggle: true),
          Field('scopes', '权限', multiple: true, options: {'a': 'A', 'b': 'B'}),
        ],
        save: (_) async {},
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context)
                    .push<void>(MaterialPageRoute(builder: (_) => formPage())),
                child: const Text('打开表单'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开表单'));
      await frames(tester);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await frames(tester);
      expect(find.text('放弃修改？'), findsNothing);
      expect(find.byType(FormPage), findsNothing);

      await tester.tap(find.text('打开表单'));
      await frames(tester);
      await tester.enterText(find.byType(TextFormField).first, '临时值');
      await tester.enterText(find.byType(TextFormField).first, '原值');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await frames(tester);
      expect(find.text('放弃修改？'), findsNothing);
      expect(find.byType(FormPage), findsNothing);

      await tester.tap(find.text('打开表单'));
      await frames(tester);
      await tester.tap(find.text('启用'));
      await tester.pump();
      await tester.tap(find.text('启用'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await frames(tester);
      expect(find.text('放弃修改？'), findsNothing);
      expect(find.byType(FormPage), findsNothing);

      await tester.tap(find.text('打开表单'));
      await frames(tester);
      await tester.tap(find.text('A'));
      await tester.pump();
      await tester.tap(find.text('A'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await frames(tester);
      expect(find.text('放弃修改？'), findsNothing);
      expect(find.byType(FormPage), findsNothing);

      await tester.tap(find.text('打开表单'));
      await frames(tester);
      await tester.enterText(find.byType(TextFormField).first, '保留修改');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await frames(tester);
      expect(find.text('放弃修改？'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('取消'),
        ),
      );
      await frames(tester);
      expect(find.byType(FormPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('dependency categories filter rows and preselect install type', (
    tester,
  ) async {
    final model = await launch(tester);
    model.demoPanel.data['dependencies'] = <Json>[
      ...rows(model.demoPanel.data['dependencies']),
      {'id': 53, 'name': 'curl', 'type': 2, 'status': 6},
      {'id': 54, 'name': 'unknown-package', 'type': 9, 'status': 5},
    ];
    model.navigate('more');
    await frames(tester);
    await tester.ensureVisible(find.text('依赖管理'));
    await tester.tap(find.text('依赖管理'));
    await frames(tester);
    expect(find.text('axios'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('resource-filter-dependencies-2')),
    );
    await frames(tester);
    expect(find.text('requests'), findsOneWidget);
    expect(find.text('axios'), findsNothing);
    expect(find.text('curl'), findsNothing);
    await tester.tap(find.text('安装'));
    await frames(tester);
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .initialValue,
      '1',
    );
    await tester.tap(find.byType(BackButton).first);
    await frames(tester);
    await tester.tap(
      find.byKey(const ValueKey('resource-filter-dependencies-3')),
    );
    await frames(tester);
    expect(find.text('curl'), findsOneWidget);
    expect(find.text('排队中'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('resource-filter-dependencies-4')),
    );
    await frames(tester);
    expect(find.text('unknown-package'), findsOneWidget);
    expect(find.text('卸载失败'), findsOneWidget);
    await tester.tap(find.text('编辑').first);
    await frames(tester);
    expect(find.text('重新安装'), findsOneWidget);
    expect(find.text('取消安装'), findsOneWidget);
    expect(find.text('启用'), findsNothing);
    expect(find.text('禁用'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'running animation stops when reduced motion or ticker mode is off',
    (tester) async {
      Widget badge(bool reduced, bool ticker) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: TickerMode(
            enabled: ticker,
            child: const Center(child: StateBadge('运行中', animate: true)),
          ),
        ),
      );
      await tester.pumpWidget(badge(true, true));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(badge(false, true));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpWidget(badge(false, false));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('tasks below pinned entries keep panel order after deletion', (
    tester,
  ) async {
    final model = await launch(tester);
    model.cache['tasks'] = List<Json>.generate(
      80,
      (i) => {
        'id': i,
        'name': '任务顺序-$i',
        'command': 'task script-$i.py',
        'schedule': '0 7 * * *',
        'status': 1,
        'isPinned': i == 0 ? 1 : 0,
        'isDisabled': i >= 26 ? 1 : 0,
      },
    );
    model.changed();
    await frames(tester);
    expect(
      tester.getTopLeft(find.text('任务顺序-0')).dy,
      lessThan(tester.getTopLeft(find.text('任务顺序-1')).dy),
    );
    expect(find.text('任务顺序-26'), findsNothing);
    for (final id in [26, 27, 28]) {
      final deletion = model.action('tasks', 'delete', [
        model.cache['tasks']!.firstWhere((r) => r['id'] == id),
      ]);
      await frames(tester);
      await deletion;
      expect(find.text('任务顺序-1'), findsOneWidget);
      expect(find.text('任务顺序-${id + 1}'), findsNothing);
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'small screen and enlarged text keep primary pages usable in both themes',
    (tester) async {
      final model = await launch(tester);
      tester.view.physicalSize = const Size(960, 1920);
      model.textScale = 1.3;
      for (final dark in [false, true]) {
        model.dark = dark;
        model.changed();
        for (final page in ['tasks', 'envs', 'scripts', 'more']) {
          model.navigate(page);
          await frames(tester);
          expect(tester.takeException(), isNull, reason: '$page, dark=$dark');
        }
        await tester.tap(find.text('仪表盘'));
        await frames(tester, 15);
        expect(find.text('93.8%'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'dashboard, dark=$dark');
        await tester.tap(find.byType(BackButton).first);
        await frames(tester);
      }
      await tester.pumpWidget(const SizedBox());
      tester.view.reset();
    },
  );
  testWidgets('task actions patch without snackbar and selection toggles off', (
    tester,
  ) async {
    await launch(tester);
    expect(find.text('定时任务'), findsOneWidget);
    await tester.tap(find.text('运行').first);
    await frames(tester);
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.text('编辑').first);
    await frames(tester);
    await tester.tap(find.text('全选 (0)'));
    await frames(tester);
    expect(find.text('全选 (24)'), findsOneWidget);
    await tester.tap(find.text('全选 (24)'));
    await frames(tester);
    expect(find.text('全选 (0)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('tab returns cached data and preserves search', (tester) async {
    final model = await launch(tester);
    await tester.enterText(find.byType(TextField).first, '备份');
    await frames(tester);
    model.navigate('envs');
    await frames(tester);
    expect(find.text('环境变量'), findsOneWidget);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('已禁用'), findsWidgets);
    final cached = model.cache['tasks'];
    model.navigate('tasks');
    await frames(tester);
    expect(identical(cached, model.cache['tasks']), isTrue);
    expect(find.text('备份'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('upload menu appears immediately and dismisses outside', (
    tester,
  ) async {
    await launch(tester);
    await tester.tap(find.text('上传'));
    await frames(tester);
    expect(find.text('本地上传'), findsOneWidget);
    expect(find.text('远程链接上传'), findsOneWidget);
    await tester.tapAt(const Offset(5, 80));
    await frames(tester);
    expect(find.text('本地上传'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('subscription page loads and form has properly sized fields', (
    tester,
  ) async {
    final model = await launch(tester);
    model.navigate('more');
    await frames(tester);
    await tester.tap(find.text('订阅管理'));
    await frames(tester);
    expect(find.text('维护脚本'), findsOneWidget);
    await tester.tap(find.text('新建'));
    await frames(tester);
    expect(find.text('创建订阅'), findsOneWidget);
    expect(find.text('名称'), findsNothing);
    expect(find.text('* 名称'), findsOneWidget);
    final input = tester.getSize(find.byType(TextFormField).first);
    expect(input.height, greaterThanOrEqualTo(40));
    expect(input.height, lessThan(100));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
