part of 'main.dart';

extension Files on HomeState {
  Future<void> openTaskScript(Json task) async {
    final candidates = scriptCandidates(str(task['command']));
    if (candidates.length == 1 && candidates.single.contains('/')) {
      final parts = candidates.single.split('/');
      final directory = parts.take(parts.length - 1).join('/');
      if (validDirectory(directory) && validFilename(parts.last)) {
        await openEditor('scripts', {'title': parts.last, 'parent': directory});
        return;
      }
    }
    await m.load('scripts');
    if (m.errors['scripts'] != null) throw ApiFailure(m.errors['scripts']!);
    var list = flatten(m.cache['scripts'] ?? [])
        .where((r) => r['type'] != 'directory')
        .where(
          (r) => candidates.any(
            (name) =>
                filePath(r) == name || str(r['title']) == name.split('/').last,
          ),
        )
        .toList();
    if (list.isEmpty) {
      await m.load('scripts', force: true);
      list = flatten(m.cache['scripts'] ?? [])
          .where((r) => r['type'] != 'directory')
          .where(
            (r) => candidates.any(
              (name) =>
                  filePath(r) == name ||
                  str(r['title']) == name.split('/').last,
            ),
          )
          .toList();
    }
    if (list.isEmpty) throw ApiFailure('未找到命令对应的脚本，请检查脚本路径或到文件页选择');
    final exact = list.where((r) => candidates.contains(filePath(r))).toList();
    if (exact.length == 1) list = exact;
    Json? target = list.length == 1 ? list.first : null;
    if (target == null) {
      final selected = await overlay(
        () => choose(context, '选择要编辑的脚本', {
          for (var i = 0; i < list.length; i++) '$i': filePath(list[i]),
        }),
      );
      if (selected != null) target = list[int.parse(selected)];
    }
    if (target != null) await openEditor('scripts', target);
  }

  Future<String> readFile(String kind, Json row) async {
    final data = await m.api(
      'GET',
      kind == 'configs'
          ? '/configs/detail?${query({'path': row['value'] ?? filePath(row)})}'
          : '/scripts/detail?${query({'file': row['title'], 'path': row['parent'] ?? ''})}',
    );
    return data is String ? data : str(data is Map ? data['content'] : data);
  }

  Future<void> openEditor(String kind, Json row) async {
    final scope = m.epoch;
    unawaited(
      Native.channel.invokeMethod<void>('editorWarm').catchError((_) {}),
    );
    final text = readFile(kind, row);
    await route(
      EditorPage(
        host: this,
        kind: kind,
        node: {...row},
        content: '',
        load: text,
        scope: scope,
      ),
    );
  }

  Future<void> upload(String source) async {
    final kind = source == 'tasks' ? 'scripts' : source;
    final mode = await overlay(
      () => choose(context, '上传${kind == 'configs' ? '配置' : '脚本'}', {
        'local': '本地上传',
        'remote': '远程链接上传',
        if (kind == 'configs') 'clipboard': '识别剪贴板 / 粘贴内容',
      }),
    );
    if (mode == null || !mounted) return;
    final scope = m.epoch;
    if (mode == 'local') {
      await guard(context, () async {
        final result = await m.native.call('pickScript');
        if (result['cancelled'] == true) return;
        if (m.epoch != scope) throw ApiFailure('面板已切换，请重新选择上传位置');
        await importReview(kind, source, Map<String, dynamic>.from(result));
      });
      return;
    }
    if (mode == 'remote') {
      await form(
        '远程上传',
        [
          const Field('url', '文件链接', required: true),
          const Field('filename', '保存文件名', required: true),
          const Field('allowHttp', '允许 HTTP 链接', toggle: true),
        ],
        {},
        (v) async {
          final doc = Map<String, dynamic>.from(
            await m.native.call('fetchText', {
              'url': v['url'],
              'filename': v['filename'],
              'allowHttp': flag(v['allowHttp']),
              'kind': kind,
            }),
          );
          if (scope != m.epoch) throw ApiFailure('面板已切换，请重新选择上传位置');
          await importReview(kind, source, doc);
        },
      );
      return;
    }
    if (!mounted) return;
    final clip = await guard(context, () => m.native.call('readClipboardText'));
    final text = str(clip?['text']);
    final isLink = RegExp(r'^https?://\S+$').hasMatch(text.trim());
    if (isLink) {
      await form(
        '识别到远程链接',
        [
          const Field('url', '文件链接', required: true),
          const Field('filename', '保存文件名', required: true),
          const Field('allowHttp', '允许 HTTP 链接', toggle: true),
        ],
        {
          'url': text.trim(),
          'filename':
              Uri.tryParse(text.trim())?.pathSegments.lastOrNull ?? 'config.sh',
        },
        (v) async {
          final doc = await m.native.call('fetchText', {
            'url': v['url'],
            'filename': v['filename'],
            'allowHttp': flag(v['allowHttp']),
            'kind': kind,
          });
          await importReview(kind, source, Map<String, dynamic>.from(doc));
        },
      );
    } else {
      await importReview(kind, source, {
        'filename': text.trimLeft().startsWith('{')
            ? 'config.json'
            : 'config.sh',
        'content': text,
      });
    }
  }

  Future<void> importReview(String kind, String source, Json doc) async {
    final scope = m.epoch;
    if (kind == 'scripts') {
      final session = ScriptUploadSession(m, str(doc['content']));
      final metadata = scriptMetadata(
        str(doc['filename']),
        str(doc['content']),
      );
      void destinationChanged(Json values) {
        final oldCommand = str(values['_autoCommand']);
        if (!validFilename(str(values['filename'])) ||
            !validDirectory(str(values['path']))) {
          return;
        }
        final command = scriptCommand(
          str(values['filename']),
          str(values['path']),
        );
        if (str(values['command']) == oldCommand) values['command'] = command;
        values['_autoCommand'] = command;
      }

      final directory = str(m.views['scriptsDir']);
      final command = scriptCommand(str(doc['filename']), directory);
      await form(
        '上传脚本与定时任务',
        [
          Field(
            'filename',
            '文件名',
            section: '脚本文件',
            required: true,
            changed: destinationChanged,
          ),
          Field(
            'path',
            '目标目录',
            section: '脚本文件',
            help: '留空上传到根目录',
            changed: destinationChanged,
          ),
          const Field('overwrite', '允许覆盖已有脚本', section: '脚本文件', toggle: true),
          const Field(
            'createTask',
            '同时创建定时任务',
            section: '定时任务',
            toggle: true,
            help: '上传后添加任务，不立即运行',
          ),
          Field(
            'name',
            '任务名称',
            section: '定时任务',
            required: true,
            visible: (v) => flag(v['createTask']),
          ),
          Field(
            'command',
            '执行命令',
            section: '定时任务',
            required: true,
            multiline: true,
            visible: (v) => flag(v['createTask']),
          ),
          Field(
            'schedule',
            '定时规则',
            section: '定时任务',
            required: true,
            help: '支持 5 / 6 位 cron，可使用下方预设',
            presets: taskSchedulePresets,
            visible: (v) => flag(v['createTask']),
          ),
        ],
        {
          ...metadata,
          'filename': doc['filename'],
          'path': directory,
          'createTask': source == 'tasks',
          'command': command,
          '_autoCommand': command,
        },
        session.submit,
        submit: '上传并保存',
      );
      return;
    }
    await form(
      '确认上传',
      [
        const Field('filename', '文件名', required: true),
        if (kind == 'scripts') const Field('path', '目标目录（留空为根目录）'),
        if (kind == 'configs')
          const Field('content', '配置内容', required: true, multiline: true),
        const Field('overwrite', '允许覆盖已有文件', toggle: true),
        if (source == 'tasks')
          const Field('createTask', '上传后添加定时任务', toggle: true),
      ],
      {
        'filename': doc['filename'],
        'path': m.views['scriptsDir'] ?? '',
        'content': doc['content'],
        'createTask': true,
      },
      (v) async {
        if (scope != m.epoch) throw ApiFailure('面板已切换');
        if (!validFilename(v['filename'])) throw ApiFailure('文件名无效');
        if (!validDirectory(str(v['path']))) throw ApiFailure('目标目录无效');
        await m.load(kind, force: true);
        if (m.errors[kind] != null) throw ApiFailure(m.errors[kind]!);
        final exists = flatten(m.cache[kind] ?? []).any(
          (r) =>
              str(r['title']) == v['filename'] &&
              (kind == 'configs' || str(r['parent']) == str(v['path'])),
        );
        if (exists && !flag(v['overwrite'])) {
          throw ApiFailure('文件已存在，请更改文件名或勾选允许覆盖');
        }
        await m.api(
          kind == 'configs'
              ? 'POST'
              : exists
              ? 'PUT'
              : 'POST',
          kind == 'configs' ? '/configs/save' : '/scripts',
          kind == 'configs'
              ? {'name': v['filename'], 'content': v['content']}
              : {
                  'filename': v['filename'],
                  'path': v['path'],
                  'content': doc['content'],
                },
        );
        await m.load(kind, force: true);
      },
      submit: '上传',
    );
  }

  Future<void> openLog(String kind, Json row) async {
    final path = kind == 'tasks'
        ? '/crons/${idOf(row)}/log?tail=true&limit=65536'
        : kind == 'subscriptions'
        ? '/subscriptions/${idOf(row)}/log?tail=true&limit=65536'
        : kind == 'dependencies'
        ? '/dependencies/${idOf(row)}'
        : '/logs/detail?${query({'file': row['title'], 'path': row['parent'] ?? '', 'tail': 'true', 'limit': 65536})}';
    await route(
      LogPage(
        host: this,
        title: str(row['name'] ?? row['title'] ?? '日志'),
        path: path,
        live: kind == 'logs' || kind == 'tasks' || kind == 'subscriptions',
        scope: m.epoch,
      ),
    );
  }
}

class EditorPage extends StatefulWidget {
  final HomeState host;
  final String kind, content;
  final Future<String>? load;
  final Json node;
  final int scope;
  const EditorPage({
    super.key,
    required this.host,
    required this.kind,
    required this.node,
    required this.content,
    this.load,
    required this.scope,
  });
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  HomeState get h => widget.host;
  late String saved = editorText(widget.content);
  late bool fileReady = widget.load == null;
  late String filename = str(widget.node['title'] ?? widget.node['value']);
  bool expanded = false, busy = false, leaving = false;
  bool ready = false;
  String? loadingError;
  int editorVersion = 0;
  int? editorId;
  bool checkingBack = false;
  @override
  void initState() {
    super.initState();
    h.leaveGuards[this] = () async {
      if (!mounted) return true;
      if (busy || checkingBack) return false;
      if (!ready) return true;
      try {
        final text = editorText(await h.m.native.editorGet(editorId));
        if (!mounted || text == saved) return true;
        return await h.overlay(
          () => confirm(context, '放弃未保存的修改？', '切换页面后当前修改将丢失。'),
        );
      } catch (_) {
        if (!mounted) return true;
        return await h.overlay(
          () => confirm(context, '编辑器连接异常', '切换页面会关闭编辑器，未保存的内容可能丢失。确认切换？'),
        );
      }
    };
    if (widget.load != null) unawaited(loadContent(widget.load!));
  }

  @override
  void dispose() {
    h.leaveGuards.remove(this);
    super.dispose();
  }

  Future<void> loadContent(Future<String> pending) async {
    try {
      final text = await pending;
      if (!mounted) return;
      scope();
      setState(() {
        saved = editorText(text);
        fileReady = true;
        loadingError = null;
      });
    } catch (e) {
      if (mounted) setState(() => loadingError = '$e');
    }
  }

  void scope() {
    if (widget.scope != h.m.epoch) throw ApiFailure('面板已切换，请重新打开文件');
  }

  Future<void> waitForEditor(int id) async {
    editorId = id;
    final generation = editorVersion;
    for (var attempt = 0; attempt < 50; attempt++) {
      if (!mounted || generation != editorVersion) return;
      try {
        if (await Native.channel
                .invokeMethod<bool>('editorReady', id)
                .timeout(const Duration(seconds: 2)) ==
            true) {
          if (mounted && generation == editorVersion) {
            setState(() => ready = true);
          }
          return;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (mounted && generation == editorVersion) {
      setState(() => loadingError = '代码编辑器加载失败，请重试');
    }
  }

  Future<void> back() async {
    if (busy || checkingBack || leaving) return;
    checkingBack = true;
    try {
      if (ready) {
        try {
          final text = editorText(await h.m.native.editorGet(editorId));
          if (text != saved &&
              !await h.overlay(
                () => confirm(context, '放弃未保存的修改？', '返回后当前修改将丢失。'),
              )) {
            return;
          }
        } catch (_) {
          if (!mounted) return;
          final choice = await h.overlay(
            () => showDialog<String>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('编辑器连接异常'),
                content: const Text(
                  '暂时无法读取当前内容。可以复制最近同步的内容后返回，或直接离开；未同步的修改可能丢失。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, 'cancel'),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(c, 'leave'),
                    child: const Text('直接返回'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(c, 'copy'),
                    child: const Text('复制内容并返回'),
                  ),
                ],
              ),
            ),
          );
          if (choice == null || choice == 'cancel') return;
          if (choice == 'copy') {
            try {
              final recovery = await Native.channel
                  .invokeMethod<String>('editorRecovery', editorId)
                  .timeout(const Duration(seconds: 2));
              if (recovery == null) throw ApiFailure('没有可恢复内容');
              await h.m.native.call('copyText', {'text': recovery});
            } catch (_) {
              if (mounted) {
                showError(context, ApiFailure('内容复制失败，可取消后重试或选择直接返回'));
              }
              return;
            }
          }
        }
      }
      if (!mounted) return;
      setState(() => leaving = true);
      Navigator.pop(context);
    } finally {
      checkingBack = false;
    }
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      scope();
      final text = editorText(await h.m.native.editorGet(editorId));
      if (text == saved) return;
      await h.m.api(
        widget.kind == 'configs' ? 'POST' : 'PUT',
        widget.kind == 'configs' ? '/configs/save' : '/scripts',
        widget.kind == 'configs'
            ? {'name': widget.node['value'] ?? filename, 'content': text}
            : {
                'filename': filename,
                'path': widget.node['parent'] ?? '',
                'content': text,
              },
      );
      saved = text;
      if (mounted) showAppToast('已保存');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> fileMenu() async {
    final operation = await h.overlay(
      () => choose(context, '文件操作', {
        'export': '导出',
        if (widget.kind == 'scripts') ...{
          'task': '从此脚本新建任务',
          'history': '历史对比与恢复',
          'rename': '重命名',
          'delete': '删除文件',
        },
      }),
    );
    if (operation == null || !mounted) return;
    await guard(context, () async {
      scope();
      if (operation == 'export') {
        await h.m.native.call('exportText', {
          'filename': filename,
          'content': await h.m.native.editorGet(editorId),
        });
      }
      if (operation == 'task') {
        final text = await h.m.native.editorGet(editorId);
        final initial = scriptMetadata(filename, text);
        initial['command'] = scriptCommand(
          filename,
          str(widget.node['parent']),
        );
        await h.form(
          '从脚本新建任务',
          [
            const Field('name', '任务名称', required: true),
            const Field('command', '执行命令', required: true),
            const Field('schedule', '定时规则', required: true),
          ],
          initial,
          (v) async {
            scope();
            if (!validCron(v['schedule'])) throw ApiFailure('定时规则格式不正确');
            await h.m.api('POST', '/crons', v);
            await h.m.load('tasks', force: true);
          },
        );
      }
      if (operation == 'history') {
        if (editorText(await h.m.native.editorGet(editorId)) != saved) {
          throw ApiFailure('请先保存或撤销当前修改后查看历史');
        }
        final restored = await h.route<bool>(
          HistoryPage(
            host: h,
            node: {...widget.node, 'title': filename},
            scope: widget.scope,
          ),
        );
        if (restored == true) {
          saved = editorText(
            await h.readFile(widget.kind, {...widget.node, 'title': filename}),
          );
          if (mounted) {
            setState(() {
              ready = false;
              loadingError = null;
              editorVersion++;
            });
          }
        }
      }
      if (operation == 'rename') {
        await h.form(
          '重命名文件',
          [const Field('filename', '新文件名', required: true)],
          {'filename': filename},
          (v) async {
            scope();
            if (!validFilename(v['filename'])) throw ApiFailure('文件名无效');
            await h.m.api('PUT', '/scripts/rename', {
              'filename': filename,
              'path': widget.node['parent'] ?? '',
              'newFilename': v['filename'],
            });
            setState(() => filename = v['filename']);
            await h.m.load('scripts', force: true);
          },
        );
      }
      if (operation == 'delete' &&
          await h.overlay(
            () => confirm(context, '删除文件？', '此操作无法直接撤销，未保存内容也会丢失。'),
          )) {
        await h.m.api('DELETE', '/scripts', {
          'filename': filename,
          'path': widget.node['parent'] ?? '',
        });
        await h.m.load('scripts', force: true);
        if (mounted) {
          setState(() => leaving = true);
          Navigator.pop(context);
        }
      }
    });
  }

  Future<void> scanDependencies() async {
    final text = await h.m.native.editorGet(editorId);
    final python = filename.endsWith('.py');
    final pattern = python
        ? RegExp(r'^\s*(?:from|import)\s+([a-zA-Z_]\w*)', multiLine: true)
        : RegExp(r'''(?:require\s*\(\s*|from\s+)["'](@?[^"'/]+(?:/[^"']+)?)''');
    final excluded = {
      'os',
      'sys',
      'json',
      'time',
      'datetime',
      're',
      'math',
      'path',
      'fs',
      'http',
      'https',
      'crypto',
      'util',
      'collections',
      'random',
      'typing',
      'asyncio',
      'logging',
    };
    final names = pattern
        .allMatches(text)
        .map((x) => x[1]!)
        .where(
          (n) =>
              !excluded.contains(n) &&
              !n.startsWith('.') &&
              !n.startsWith('node:'),
        )
        .toSet()
        .toList();
    if (names.isEmpty) throw ApiFailure('没有识别到外部依赖');
    await h.form(
      '安装识别到的依赖',
      [
        const Field(
          'names',
          '依赖名称',
          multiline: true,
          required: true,
          help: '静态识别可能不完整，请核对包名',
        ),
      ],
      {'names': names.join('\n')},
      (v) async {
        await h.m.api(
          'POST',
          '/dependencies',
          str(v['names'])
              .split(RegExp(r'\s+'))
              .where((s) => s.isNotEmpty)
              .map((n) => {'name': n, 'type': python ? 1 : 0})
              .toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: leaving,
    onPopInvokedWithResult: (p, r) {
      if (!p) back();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          onPressed: back,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(
          filename,
          style: const TextStyle(fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton.icon(
            onPressed: busy || !ready ? null : save,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: Text(busy ? '保存中' : '保存'),
          ),
          IconButton(
            tooltip: '文件操作',
            onPressed: busy || !ready ? null : fileMenu,
            icon: const Icon(Icons.more_horiz),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(
                  filename.split('.').last.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => expanded = !expanded),
                  icon: Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                  ),
                  label: Text(expanded ? '收起工具' : '编辑工具'),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Wrap(
                      spacing: 7,
                      runSpacing: 5,
                      children: [
                        _compactButton(
                          context,
                          '粘贴',
                          Icons.content_paste,
                          () => guard(context, () async {
                            final value = await h.m.native.call(
                              'readClipboardText',
                            );
                            await Native.channel.invokeMethod('editorInsert', {
                              'viewId': editorId,
                              'text': str(value['text']),
                            });
                          }),
                        ),
                        _compactButton(
                          context,
                          '字号',
                          Icons.text_fields,
                          () => h.form(
                            '代码字号',
                            [const Field('size', '字号（10–24）', required: true)],
                            {'size': '14'},
                            (v) async {
                              final size = int.tryParse(v['size']);
                              if (size == null || size < 10 || size > 24) {
                                throw ApiFailure('请输入 10–24 的字号');
                              }
                              await h.m.native.editorAction(
                                'font:$size',
                                editorId,
                              );
                            },
                          ),
                        ),
                        for (final e in {
                          'undo': ('撤销', Icons.undo),
                          'redo': ('重做', Icons.redo),
                          'search': ('搜索', Icons.search),
                          'top': ('顶部', Icons.vertical_align_top),
                        }.entries)
                          _compactButton(
                            context,
                            e.value.$1,
                            e.value.$2,
                            () => h.m.native.editorAction(e.key, editorId),
                          ),
                        _compactButton(
                          context,
                          '跳行',
                          Icons.format_list_numbered,
                          () => h.form(
                            '跳转到行',
                            [const Field('line', '行号', required: true)],
                            {'line': '1'},
                            (v) async {
                              final line = int.tryParse(v['line']);
                              if (line == null || line < 1) {
                                throw ApiFailure('请输入有效行号');
                              }
                              await h.m.native.editorAction(
                                'jump:$line',
                                editorId,
                              );
                            },
                          ),
                        ),
                        _compactButton(
                          context,
                          '识别依赖',
                          Icons.inventory_2_outlined,
                          () => guard(context, scanDependencies),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (fileReady)
                  AndroidView(
                    key: ValueKey(editorVersion),
                    viewType: 'ql-code-editor',
                    onPlatformViewCreated: waitForEditor,
                    creationParamsCodec: const StandardMessageCodec(),
                    creationParams: {
                      'filename': filename,
                      'content': saved,
                      'dark': h.m.dark,
                    },
                  ),
                if (!ready)
                  ColoredBox(
                    color: _surface(context),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (loadingError == null) ...[
                            const SizedBox(
                              width: 23,
                              height: 23,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              fileReady ? '正在准备代码编辑器…' : '正在读取脚本…',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ] else ...[
                            Text(
                              loadingError!,
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 10),
                            _compactButton(context, '重试', Icons.refresh, () {
                              setState(() {
                                loadingError = null;
                                editorVersion++;
                              });
                              if (!fileReady) {
                                unawaited(
                                  loadContent(
                                    h.readFile(widget.kind, widget.node),
                                  ),
                                );
                              }
                            }),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class LogPage extends StatefulWidget {
  final HomeState host;
  final String title, path;
  final int scope;
  final bool live;
  const LogPage({
    super.key,
    required this.host,
    required this.title,
    required this.path,
    required this.scope,
    this.live = false,
  });
  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> with WidgetsBindingObserver {
  final scroll = ScrollController(), queryController = TextEditingController();
  final focus = FocusNode();
  Timer? timer;
  String text = '', error = '';
  bool busy = false, searching = false, paused = false, follow = true;
  int failures = 0, current = 0;
  List<int> get matches {
    final q = queryController.text.toLowerCase();
    if (q.isEmpty) return [];
    final source = text.toLowerCase(), result = <int>[];
    var from = 0;
    while (result.length < 2000) {
      final i = source.indexOf(q, from);
      if (i < 0) break;
      result.add(i);
      from = i + q.length;
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
    scroll.addListener(() {
      if (scroll.hasClients) {
        follow = scroll.position.maxScrollExtent - scroll.offset < 70;
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    scroll.dispose();
    queryController.dispose();
    focus.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refresh();
    } else {
      timer?.cancel();
    }
  }

  Future<void> refresh() async {
    if (busy || !mounted || widget.scope != widget.host.m.epoch) return;
    timer?.cancel();
    setState(() => busy = true);
    try {
      final data = await widget.host.m.api('GET', widget.path);
      final next = data is String
          ? data
          : data is Map
          ? str(
              data['log'] is List
                  ? (data['log'] as List).join('\n')
                  : data['log'] ?? data['content'],
            )
          : data is List
          ? data.join('\n')
          : str(data);
      if (!mounted || widget.scope != widget.host.m.epoch) return;
      final changed = next != text;
      setState(() {
        text = next;
        error = '';
        failures = 0;
      });
      if (changed && follow && !searching) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          failures++;
        });
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        if (widget.live &&
            widget.scope == widget.host.m.epoch &&
            !paused &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) {
          timer = Timer(
            Duration(seconds: (2 * (failures + 1)).clamp(2, 15)),
            refresh,
          );
        }
      }
    }
  }

  void jump(int delta) {
    final list = matches;
    if (list.isEmpty) return;
    setState(() => current = (current + delta) % list.length);
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.65,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: MediaQuery.sizeOf(context).width - 28);
    final position = painter
        .getOffsetForCaret(TextPosition(offset: list[current]), Rect.zero)
        .dy;
    painter.dispose();
    if (scroll.hasClients) {
      scroll.animateTo(
        (position - 25).clamp(0, scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  Widget highlighted() {
    final list = matches;
    if (list.isEmpty) {
      return SelectableText(
        text.isEmpty ? '等待日志输出…' : text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.65,
        ),
      );
    }
    final spans = <TextSpan>[];
    var start = 0;
    for (var i = 0; i < list.length; i++) {
      final position = list[i];
      spans.add(TextSpan(text: text.substring(start, position)));
      spans.add(
        TextSpan(
          text: text.substring(
            position,
            position + queryController.text.length,
          ),
          style: TextStyle(
            backgroundColor: i == current
                ? const Color(0xffffbd55)
                : const Color(0xfff6e3ad),
            color: ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      start = position + queryController.text.length;
    }
    spans.add(TextSpan(text: text.substring(start)));
    return SelectableText.rich(
      TextSpan(children: spans),
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
        height: 1.65,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.title,
        style: const TextStyle(fontSize: 15),
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        IconButton(
          tooltip: '返回顶部',
          icon: const Icon(Icons.vertical_align_top),
          onPressed: () {
            if (scroll.hasClients) {
              follow = false;
              scroll.animateTo(
                0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
              );
            }
          },
        ),
        IconButton(
          tooltip: searching ? '关闭搜索' : '搜索',
          onPressed: () {
            setState(() => searching = !searching);
            if (searching) {
              focus.requestFocus();
            } else {
              queryController.clear();
            }
          },
          icon: Icon(searching ? Icons.search_off : Icons.search),
        ),
        IconButton(
          tooltip: '刷新',
          onPressed: busy ? null : refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
        PopupMenuButton<String>(
          onSelected: (v) => guard(context, () async {
            await widget.host.m.native.call(
              v == 'copy' ? 'copyText' : 'exportText',
              v == 'copy'
                  ? {'text': text}
                  : {'filename': 'qinglong.log', 'content': text},
            );
          }),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'copy', child: Text('复制日志')),
            PopupMenuItem(value: 'export', child: Text('导出日志')),
          ],
        ),
      ],
    ),
    body: Column(
      children: [
        if (widget.live)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                StateBadge(paused ? '已暂停' : '实时日志', animate: !paused),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    setState(() => paused = !paused);
                    if (paused) {
                      timer?.cancel();
                    } else {
                      refresh();
                    }
                  },
                  icon: Icon(paused ? Icons.play_arrow : Icons.pause, size: 18),
                  label: Text(paused ? '继续' : '暂停'),
                ),
              ],
            ),
          ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          child: searching
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(13, 5, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: TextField(
                            focusNode: focus,
                            controller: queryController,
                            onChanged: (_) => setState(() => current = 0),
                            decoration: const InputDecoration(
                              hintText: '搜索日志',
                              prefixIcon: Icon(Icons.search, size: 18),
                            ),
                          ),
                        ),
                      ),
                      Text(
                        ' ${matches.isEmpty ? 0 : current + 1}/${matches.length}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      IconButton(
                        tooltip: '上一个匹配',
                        onPressed: () => jump(-1),
                        icon: const Icon(Icons.keyboard_arrow_up),
                      ),
                      IconButton(
                        tooltip: '下一个匹配',
                        onPressed: () => jump(1),
                        icon: const Icon(Icons.keyboard_arrow_down),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
        if (error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              error,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        Expanded(
          child: Container(
            width: double.infinity,
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xff1e1e22)
                : const Color(0xfffcf9fb),
            child: SingleChildScrollView(
              controller: scroll,
              padding: const EdgeInsets.all(14),
              child: highlighted(),
            ),
          ),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.small(
      tooltip: '回到日志末尾',
      onPressed: () {
        follow = true;
        if (scroll.hasClients) {
          scroll.animateTo(
            scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      },
      child: const Icon(Icons.vertical_align_bottom),
    ),
  );
}
