import 'dart:ui' as ui;
import 'dart:async';

import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qinglong_mobile/core.dart';
import 'package:qinglong_mobile/main.dart';
import 'package:qinglong_mobile/reference_ui/navigation_dock.dart' as fc;
import 'package:qinglong_mobile/reference_ui/liquid_glass.dart' as fg;
import 'package:qinglong_mobile/reference_ui/icons/icons.dart' as fi;

class TrackingNative extends Native {
  bool failEditorReads = false;
  @override
  Future<String> editorGet([int? viewId]) {
    if (failEditorReads) {
      throw PlatformException(code: 'EDITOR', message: '模拟连接异常');
    }
    return super.editorGet(viewId);
  }

  Json dockState = {};
  @override
  Future<dynamic> call(String action, [Json payload = const {}]) {
    if (action == 'dockState') dockState = {...payload};
    return super.call(action, payload);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Flutter screens interoperate with the existing Android services', (
    tester,
  ) async {
    final native = TrackingNative();
    final model = PanelModel(native: native);
    await tester.pumpWidget(QinglongApp(model: model));
    Future<void> frames([int count = 10]) async {
      for (var i = 0; i < count; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await frames(35);
    expect(model.initialized, isTrue);
    expect(model.demo, isTrue);
    expect(model.nativeDock, isTrue);
    final desktop = await Native.channel.invokeMapMethod<String, dynamic>(
      'desktopCapabilities',
    );
    expect(desktop?['shortcuts'], 4);
    expect(find.text('定时任务'), findsOneWidget);
    final optics = await model.native.call('dockDebug');
    expect(optics['visible'], isFalse);
    expect(find.byType(fc.NavigationDock), findsOneWidget);
    expect(fg.LiquidGlassHost.debugShaderLoaded, isTrue);
    final bootstrap = await model.native.call('bootstrap');
    expect(bootstrap['version'], '0.22.0');
    final forecast = await native.call('forecastTasks', {
      'timezone': 'Asia/Shanghai',
      'now': DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
      'tasks': [
        {'id': 'native-check', 'schedule': '0 9 * * *'},
      ],
    });
    expect(
      forecast['rows'][0]['next'],
      DateTime.utc(2026, 1, 1, 1).millisecondsSinceEpoch,
    );
    final count = (bootstrap['servers'] as List).length;
    await tester.tap(find.text('上传'));
    await frames(5);
    expect(find.text('本地上传'), findsOneWidget);
    await tester.tapAt(const Offset(5, 85));
    await frames();
    await tester.tap(find.text('编辑').first);
    await frames(4);
    await tester.tap(find.text('全选 (0)'));
    await frames(4);
    expect(find.text('全选 (24)'), findsOneWidget);
    await tester.tap(find.text('全选 (24)'));
    await frames(4);
    expect(find.text('全选 (0)'), findsOneWidget);
    await tester.tap(find.text('完成'));
    await frames();
    final cached = model.cache['tasks'];
    for (final target in [
      'envs',
      'scripts',
      'more',
      'tasks',
      'envs',
      'tasks',
    ]) {
      model.navigate(target);
      await frames(10);
      final background = await model.native.call('dockDebug');
      expect(background['visible'], isFalse);
      expect(
        tester
            .widget<fc.NavigationDock>(find.byType(fc.NavigationDock))
            .selectedIndex,
        ['tasks', 'envs', 'scripts', 'more'].indexOf(target),
      );
    }
    for (final target in ['envs', 'tasks', 'scripts', 'more', 'tasks']) {
      model.navigate(target);
      await frames(1);
    }
    await frames(15);
    final rapidBackground = await model.native.call('dockDebug');
    expect(rapidBackground['visible'], isFalse);
    expect(
      tester
          .widget<fc.NavigationDock>(find.byType(fc.NavigationDock))
          .selectedIndex,
      0,
    );
    expect(identical(cached, model.cache['tasks']), isTrue);
    final host = tester.state<HomeState>(find.byType(Home));
    final details = host.taskDetails(model.cache['tasks']!.first);
    await frames(8);
    expect(find.text('创建时间'), findsOneWidget);
    await tester.tap(find.text('日志历史'));
    await frames(12);
    expect(find.text('2026-10-23-070000.log'), findsOneWidget);
    await tester.tap(find.byType(BackButton).first);
    await frames(6);
    await tester.tap(find.byType(BackButton).first);
    await frames(6);
    await details;
    final editTask = host.taskForm({...model.cache['tasks']!.first});
    await frames(8);
    final fiveMinutes = find.byKey(
      const ValueKey('preset-schedule-*/5 * * * *'),
    );
    await tester.scrollUntilVisible(
      fiveMinutes,
      180,
      scrollable: find
          .descendant(
            of: find.byType(FormPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await frames(3);
    await tester.tap(fiveMinutes);
    await frames(6);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).last)
          .controller!
          .text,
      '*/5 * * * *',
    );
    await tester.tap(find.text('保存'));
    await frames(12);
    await editTask;
    expect(model.cache['tasks']!.first['schedule'], '*/5 * * * *');
    final uploaded = host.importReview('scripts', 'tasks', {
      'filename': 'preset-upload-demo.py',
      'content': '# cron: 0 9 * * *\nprint(1)',
    });
    await frames(8);
    final weekly = find.byKey(const ValueKey('preset-schedule-0 9 * * 1'));
    await tester.scrollUntilVisible(
      weekly,
      180,
      scrollable: find
          .descendant(
            of: find.byType(FormPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await frames(3);
    await tester.tap(weekly);
    await frames(6);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).last)
          .controller!
          .text,
      '0 9 * * 1',
    );
    await tester.tap(find.text('上传并保存'));
    await frames(14);
    await uploaded;
    expect(
      model.cache['tasks']!.any(
        (row) =>
            row['command'] == 'task preset-upload-demo.py' &&
            row['schedule'] == '0 9 * * 1',
      ),
      isTrue,
    );
    model.demoPanel.content['backup.py'] =
        '${model.demoPanel.content['backup.py']}\n${List.generate(80, (i) => '# scroll-only line $i').join('\n')}'
            .replaceAll('\n', '\r\n');
    await tester.tap(find.text('每日数据备份').first);
    await frames(25);
    expect(find.byType(EditorPage), findsOneWidget);
    await model.native.editorAction('jump:65');
    await frames(3);
    await model.native.editorAction('top');
    await frames(3);
    await tester.tap(find.byTooltip('返回').first);
    await frames(10);
    expect(find.text('放弃未保存的修改？'), findsNothing);
    expect(find.byType(EditorPage), findsNothing);
    await tester.tap(find.text('每日数据备份').first);
    await frames(25);
    expect(find.byType(EditorPage), findsOneWidget);
    final initial = await model.native.editorGet();
    expect(initial, contains('Backup started'));
    final editorHost = tester.state<HomeState>(
      find.byType(Home, skipOffstage: false),
    );
    unawaited(
      editorHost.route(
        EditorPage(
          host: editorHost,
          kind: 'scripts',
          node: {'title': 'nested.py', 'parent': ''},
          content: 'print("nested")',
          scope: model.epoch,
        ),
      ),
    );
    await frames(20);
    expect(await model.native.editorGet(), contains('nested'));
    await tester.tap(find.byTooltip('返回').first);
    await frames(10);
    expect(await model.native.editorGet(), contains('Backup started'));
    native.failEditorReads = true;
    await tester.tap(find.byTooltip('返回').first);
    await frames(5);
    expect(find.text('编辑器连接异常'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await frames(5);
    native.failEditorReads = false;
    await tester.tap(find.text('编辑工具'));
    await frames(5);
    expect(find.text('搜索'), findsOneWidget);
    await model.native.editorAction('search');
    await frames(5);
    await model.native.editorAction('top');
    await model.native.editorAction('font:16');
    await Native.channel.invokeMethod(
      'editorInsert',
      '\n# integration-only demo change\n',
    );
    await frames(5);
    expect(
      await Native.channel.invokeMethod<String>('editorRecovery'),
      contains('integration-only'),
    );
    expect(await model.native.editorGet(), contains('integration-only'));
    await tester.tap(find.byTooltip('返回').first);
    await frames(5);
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await frames(5);
    await tester.tap(find.text('保存'));
    await frames(10);
    expect(model.demoPanel.content['backup.py'], contains('integration-only'));
    await tester.tap(find.byTooltip('返回').first);
    await frames(10);
    expect(find.byType(EditorPage), findsNothing);
    await tester.tap(find.text('每日数据备份').first);
    await frames(20);
    native.failEditorReads = true;
    await tester.tap(find.byTooltip('返回').first);
    await frames(5);
    expect(find.text('编辑器连接异常'), findsOneWidget);
    await tester.tap(find.text('直接返回'));
    await frames(10);
    native.failEditorReads = false;
    expect(find.byType(EditorPage), findsNothing);
    await tester.tap(find.byTooltip('更多操作').first);
    await frames(5);
    model.demoPanel.log = List.generate(
      150,
      (i) => 'demo log line $i',
    ).join('\n');
    await tester.tap(find.text('查看日志'));
    await frames(10);
    expect(find.byType(LogPage), findsOneWidget);
    await tester.tap(find.byTooltip('返回顶部'));
    await frames(5);
    final logScroll = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView).last)
        .controller;
    expect(logScroll?.offset, 0);

    expect(find.byType(TextField), findsNothing);
    final before = model.demoPanel.log.length;
    await frames(25);
    expect(model.demoPanel.log.length, greaterThan(before));
    await tester.tap(find.byTooltip('搜索').first);
    await frames(5);
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '演示');
    await frames(5);
    expect(find.textContaining('/'), findsWidgets);
    await tester.tap(find.byType(BackButton).first);
    await frames();
    model.navigate('more');
    await frames();
    await tester.tap(find.text('订阅管理'));
    await frames(10);
    expect(find.text('维护脚本'), findsOneWidget);
    await tester.tap(find.text('新建'));
    await frames();
    expect(find.text('创建订阅'), findsOneWidget);
    await tester.tap(find.byType(BackButton).first);
    await frames();
    await tester.tap(find.byType(BackButton).first);
    await frames();
    await tester.tap(find.text('仪表盘'));
    await frames(15);
    expect(find.text('93.8%'), findsOneWidget);
    await tester.tap(find.byType(BackButton).first);
    await frames();
    await tester.ensureVisible(find.text('依赖管理'));
    await tester.tap(find.text('依赖管理'));
    await frames();
    await tester.tap(
      find.byKey(const ValueKey('resource-filter-dependencies-2')),
    );
    await frames(4);
    expect(find.text('requests'), findsOneWidget);
    expect(find.text('axios'), findsNothing);
    await tester.tap(find.text('安装'));
    await frames(5);
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .initialValue,
      '1',
    );
    await tester.tap(find.byType(BackButton).first);
    await frames(5);
    await tester.tap(find.byType(BackButton).first);
    await frames();
    await tester.ensureVisible(find.text('应用管理'));
    await tester.tap(find.text('应用管理'));
    await frames();
    await tester.tap(find.text('示例应用'));
    await frames(5);
    await tester.tap(find.text('编辑').last);
    await frames(5);
    expect(find.byType(TextFormField), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('scope-crons')));
    await frames(3);
    await tester.tap(find.byKey(const ValueKey('scope-configs')));
    await frames(3);
    await tester.tap(find.text('保存'));
    await frames();
    expect((model.demoPanel.data['apps'] as List).first['scopes'], [
      'envs',
      'configs',
    ]);
    await tester.tap(find.byType(BackButton).first);
    await frames();
    // Local demo only: copy, shared-script protection, then bulk removal.
    model.demoPanel.data['crons'] = <Json>[
      {
        'id': 9001,
        'name': '删除流程演示',
        'command': 'task remove-demo.py',
        'schedule': '0 9 * * *',
        'status': 1,
      },
    ];
    (model.demoPanel.data['scripts'] as List).add({
      'title': 'remove-demo.py',
      'parent': '',
      'type': 'file',
    });
    await model.load('tasks', force: true);
    model.navigate('tasks');
    await frames();
    await tester.tap(find.text('更多').first);
    await frames();
    await tester.tap(find.text('复制任务'));
    await frames();
    expect(find.text('复制任务'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await frames(12);
    expect(model.demoPanel.data['crons'], hasLength(2));
    await tester.tap(find.text('更多').first);
    await frames();
    await tester.tap(find.text('删除'));
    await frames();
    final scriptsOption = find.byKey(const ValueKey('delete-task-scripts'));
    expect(tester.widget<CheckboxListTile>(scriptsOption).onChanged, isNull);
    expect(find.textContaining('另有 1 个任务使用'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await frames();
    await tester.tap(find.text('编辑').first);
    await frames();
    await tester.tap(find.text('全选 (0)'));
    await frames();
    await tester.tap(find.text('删除'));
    await frames();
    await tester.tap(scriptsOption);
    await frames();
    await tester.tap(find.text('删除任务及 1 个脚本'));
    await frames(12);
    expect(model.demoPanel.data['crons'], isEmpty);
    expect(
      rows(model.demoPanel.data['scripts'])
          .any((r) => r['title'] == 'remove-demo.py'),
      isFalse,
    );
    final after = await model.native.call('bootstrap');
    expect((after['servers'] as List).length, count);
    expect(tester.takeException(), isNull);
    // Check the ported renderer's actual atlas pixels, including a static
    // background change without scrolling or a native PixelCopy handshake.
    for (final sample in [
      ('tasks', const Color(0xffd02838)),
      ('envs', const Color(0xff2878d0)),
      ('scripts', const Color(0xff28b068)),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: fg.LiquidGlassScope(
            enabled: true,
            child: fg.LiquidGlassHost(
              enabled: true,
              child: Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: sample.$2)),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: fc.NavigationDock(
                      selectedIndex: 0,
                      onSelected: (_) {},
                      destinations: const [
                        fc.NavigationDockDestination(
                          glyph: fi.AppGlyphs.clock,
                          label: '任务',
                        ),
                        fc.NavigationDockDestination(
                          glyph: fi.AppGlyphs.code,
                          label: '变量',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await frames(10);
      final capture = fg.LiquidGlassHost.debugLastCapture;
      expect(capture, isNotNull);
      expect(capture!.panes, isNotEmpty);
      final pane = capture.panes.firstWhere((pane) => pane.level == 0);
      final pixels = (await pane.atlas.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final w = pane.atlas.width;
      final center = pane.place.center;
      for (var y = center.dy.toInt() - 2; y <= center.dy.toInt() + 2; y++) {
        for (var x = center.dx.toInt() - 2; x <= center.dx.toInt() + 2; x++) {
          final offset = (y * w + x) * 4;
          expect(
            pixels.getUint8(offset),
            closeTo((sample.$2.r * 255).round(), 3),
          );
          expect(
            pixels.getUint8(offset + 1),
            closeTo((sample.$2.g * 255).round(), 3),
          );
          expect(
            pixels.getUint8(offset + 2),
            closeTo((sample.$2.b * 255).round(), 3),
          );
        }
      }
    }
    debugPrint(
      'FlClash dock atlas pixels verified; fragmentShaderLoaded=${fg.LiquidGlassHost.debugShaderLoaded}; shaderFilterSupported=${ui.ImageFilter.isShaderFilterSupported}',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
