import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qinglong_mobile/core.dart';
import 'package:qinglong_mobile/main.dart';

class PreviewNative extends Native {
  @override
  Future<dynamic> call(String action, [Json payload = const {}]) async {
    if (action == 'bootstrap') {
      return {
        'servers': [],
        'activeId': '',
        'nativeDock': false,
        'version': '0.22.0',
      };
    }
    if (action == 'forecastTasks') {
      return {
        'rows': [
          for (final row in payload['tasks'] as List)
            {
              'id': row['id'],
              'next': DateTime(2026, 10, 25, 9).millisecondsSinceEpoch,
            },
        ],
        'source': 'panel',
        'zone': 'Asia/Shanghai',
      };
    }
    return {};
  }
}

void main() {
  testWidgets('review new management pages at phone sizes in both themes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final entry in {
        'Roboto': 'C:/Windows/Fonts/msyh.ttc',
        'MaterialIcons': '../.tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      }.entries) {
        final file = File(entry.value);
        if (!file.existsSync()) continue;
        final bytes = await file.readAsBytes();
        final loader = FontLoader(entry.key)
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
      }
    });
    final output = Directory('../dist/flutter-ui-v27')
      ..createSync(recursive: true);
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    final model = PanelModel(native: PreviewNative()), root = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: root,
        child: QinglongApp(model: model),
      ),
    );
    Future<void> frames([int count = 12]) async {
      for (var i = 0; i < count; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> capture(String name) async {
      await frames(3);
      await tester.runAsync(() async {
        final boundary =
            root.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('${output.path}/$name.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull);
    }

    await frames();
    final host = tester.state<HomeState>(find.byType(Home));
    for (final dark in [false, true]) {
      model.dark = dark;
      model.navigate('tasks');
      await frames();
      final theme = dark ? 'dark' : 'light';
      await capture('tasks-$theme');
      final details = host.taskDetails(model.cache['tasks']!.first);
      await frames();
      await capture('task-details-$theme');
      await tester.tap(find.byType(BackButton).first);
      await frames();
      await details;
      model.navigate('envs');
      await frames();
      await capture('envs-$theme');
      final settings = host.dependencySettings();
      await frames();
      await capture('dependency-settings-$theme');
      await tester.drag(
        find
            .descendant(
              of: find.byType(DependencySettingsPage),
              matching: find.byType(ListView),
            )
            .first,
        const Offset(0, -480),
      );
      await frames();
      await capture('dependency-cache-$theme');
      await tester.tap(find.byType(BackButton).first);
      await frames();
      await settings;
      final upload = host.importReview('scripts', 'tasks', {
        'filename': 'sample.py',
        'content': '# cron: 0 9 * * *\nprint(1)',
      });
      await frames();
      await capture('upload-task-$theme');
      await tester.tap(find.byType(BackButton).first);
      await frames();
      await upload;
    }
    tester.view.physicalSize = const Size(960, 1920);
    model.textScale = 1.3;
    model.navigate('tasks');
    await frames();
    await capture('tasks-small-large-text');
    final upload = host.importReview('scripts', 'tasks', {
      'filename': 'sample.py',
      'content': '# cron: 0 9 * * *\nprint(1)',
    });
    await frames();
    await capture('upload-small-large-text');
    await tester.tap(find.byType(BackButton).first);
    await frames();
    await upload;
    await tester.pumpWidget(const SizedBox());
    model.dispose();
    tester.view.reset();
  });
}
