part of 'main.dart';

extension TaskInspection on HomeState {
  Future<void> taskDetails(Json row) =>
      route(TaskDetailsPage(host: this, task: row, scope: m.epoch));
  Future<void> taskHistory(Json row) =>
      route(TaskHistoryPage(host: this, task: row, scope: m.epoch));
  Future<void> dependencySettings() =>
      route(DependencySettingsPage(host: this, scope: m.epoch));
}

Widget metadataLine(BuildContext context, String label, String value) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        '$label $value',
        style: TextStyle(
          fontSize: 11,
          height: 1.4,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );

class TaskDetailsPage extends StatelessWidget {
  final HomeState host;
  final Json task;
  final int scope;
  const TaskDetailsPage({
    super.key,
    required this.host,
    required this.task,
    required this.scope,
  });
  void checkScope() {
    if (host.m.epoch != scope) throw ApiFailure('面板已切换，请返回重新打开');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('任务详情')),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => guard(context, () async {
              checkScope();
              await host.openLog('tasks', task);
            }),
            icon: const Icon(Icons.article_outlined),
            label: const Text('当前日志'),
          ),
          FilledButton.icon(
            onPressed: () => guard(context, () async {
              checkScope();
              await host.taskHistory(task);
            }),
            icon: const Icon(Icons.history_rounded),
            label: const Text('日志历史'),
          ),
        ],
      ),
    ),
    body: ListenableBuilder(
      listenable: host.m,
      builder: (context, _) {
        if (host.m.epoch != scope) {
          return const Center(child: Text('面板已切换，请返回重新打开'));
        }
        final row =
            (host.m.cache['tasks'] ?? [])
                .where((r) => idOf(r) == idOf(task))
                .firstOrNull ??
            task;
        final forecast = host.m.forecasts[idOf(row)];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    str(row['name']),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  StateBadge(
                    taskState(row),
                    color: disabled(row) ? warm : accent,
                    animate: running(row),
                  ),
                  const SizedBox(height: 12),
                  for (final entry in <String, String>{
                    '任务 ID': idOf(row),
                    '创建时间': dateLabel(createdTime(row)),
                    '更新时间': dateLabel(updatedTime(row)),
                    '定时规则': str(row['schedule']),
                    '下次运行': host.m.nextTaskTime(row),
                    '最后运行': panelDate(row['last_execution_time']) == null
                        ? '尚未执行'
                        : dateLabel(row['last_execution_time']),
                    '最后时长': durationLabel(row),
                    '执行命令': str(row['command']),
                  }.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 3),
                          SelectableText(
                            entry.value,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  if (!disabled(row))
                    Text(
                      '下次运行按${forecast?['source'] == 'panel' ? '面板' : '设备'}时区 ${forecast?['zone'] ?? ''} 估算；实际调度以面板为准。',
                      style: const TextStyle(fontSize: 11),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

class TaskHistoryPage extends StatefulWidget {
  final HomeState host;
  final Json task;
  final int scope;
  const TaskHistoryPage({
    super.key,
    required this.host,
    required this.task,
    required this.scope,
  });
  @override
  State<TaskHistoryPage> createState() => _TaskHistoryPageState();
}

class _TaskHistoryPageState extends State<TaskHistoryPage> {
  List<Json> logs = [];
  bool busy = true;
  String? error;
  String search = '';
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  void checkScope() {
    if (widget.scope != widget.host.m.epoch) {
      throw ApiFailure('面板已切换，请重新打开日志历史');
    }
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      checkScope();
      final result = await widget.host.m.api(
        'GET',
        '/crons/${idOf(widget.task)}/logs',
      );
      checkScope();
      if (result is! List) throw ApiFailure('当前面板未提供可识别的日志历史');
      final list = rows(result)
        ..sort(
          (a, b) => (panelDate(b['time'])?.millisecondsSinceEpoch ?? 0)
              .compareTo(panelDate(a['time'])?.millisecondsSinceEpoch ?? 0),
        );
      if (mounted) setState(() => logs = list);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ApiFailure && [403, 404].contains(e.status)
              ? '面板不支持日志历史，或当前账号没有访问权限'
              : '$e',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> open(Json row) async {
    checkScope();
    final filename = str(row['filename']), directory = str(row['directory']);
    if (!validFilename(filename) || !validDirectory(directory)) {
      throw ApiFailure('面板返回的日志路径无效');
    }
    await widget.host.route(
      LogPage(
        host: widget.host,
        title: filename,
        path:
            '/logs/detail?${query({'file': filename, 'path': directory, 'tail': 'true', 'limit': 65536})}',
        live: false,
        scope: widget.scope,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = logs
        .where(
          (r) =>
              str(r['filename']).toLowerCase().contains(search.toLowerCase()),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志历史'),
        actions: [
          IconButton(
            tooltip: '刷新历史',
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: TextField(
              onChanged: (v) => setState(() => search = v),
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: '搜索日志文件名',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          if (busy) const LinearProgressIndicator(minHeight: 2),
          if (error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
          Expanded(
            child: RefreshIndicator(
              onRefresh: load,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                itemCount: list.isEmpty ? 1 : list.length,
                itemBuilder: (c, i) => list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            busy
                                ? '正在读取…'
                                : logs.isEmpty
                                ? '暂无历史日志'
                                : '没有匹配的日志',
                          ),
                        ),
                      )
                    : GlassCard(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.history_rounded),
                          title: Text(
                            str(list[i]['filename']),
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            dateLabel(list[i]['time']),
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => guard(c, () => open(list[i])),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DependencySettingsPage extends StatefulWidget {
  final HomeState host;
  final int scope;
  const DependencySettingsPage({
    super.key,
    required this.host,
    required this.scope,
  });
  @override
  State<DependencySettingsPage> createState() => _DependencySettingsPageState();
}

class _DependencySettingsPageState extends State<DependencySettingsPage> {
  static const fields = {
    'dependenceProxy': ('依赖代理', 'dependence-proxy', 'HTTP / SOCKS5 代理；留空取消代理'),
    'nodeMirror': ('Node.js 镜像源', 'node-mirror', 'npm registry 地址；留空恢复默认'),
    'pythonMirror': ('Python 镜像源', 'python-mirror', 'pip index 地址；留空恢复默认'),
    'linuxMirror': ('Linux 镜像源', 'linux-mirror', '软件源地址；留空恢复默认'),
  };
  final controllers = {
    for (final key in fields.keys) key: TextEditingController(),
  };
  final messages = <String, String>{};
  final dirty = <String>{};
  String? error, saving;
  bool loading = true, loaded = false;
  void checkScope() {
    if (widget.scope != widget.host.m.epoch) {
      throw ApiFailure('面板已切换，请重新打开依赖设置');
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      checkScope();
      final info = await widget.host.m.readSystemInfo(force: true);
      checkScope();
      if (mounted) {
        setState(() {
          for (final key in fields.keys) {
            if (!dirty.contains(key)) controllers[key]!.text = str(info[key]);
          }
          loaded = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> save(String key) async {
    final text = controllers[key]!.text.trim();
    if (text.isNotEmpty) {
      final uri = Uri.tryParse(text);
      final allowed = key == 'dependenceProxy'
          ? ['http', 'https', 'socks5', 'socks5h']
          : ['http', 'https'];
      if (uri == null ||
          !allowed.contains(uri.scheme) ||
          uri.host.isEmpty ||
          RegExp(r'[\s\x00-\x1f]').hasMatch(text)) {
        setState(
          () => messages[key] =
              '请输入有效的${key == 'dependenceProxy' ? '代理' : 'HTTP / HTTPS 镜像'}地址',
        );
        return;
      }
    }
    setState(() => saving = key);
    try {
      checkScope();
      final result = await widget.host.m.api(
        'PUT',
        '/system/config/${fields[key]!.$2}',
        {key: text},
      );
      checkScope();
      final info = await widget.host.m.readSystemInfo(force: true);
      checkScope();
      final persisted = str(info[key]).trim() == text;
      final output = result is Map ? str(result['output']) : '';
      if (mounted) {
        setState(() {
          if (persisted) dirty.remove(key);
          messages[key] =
              '${persisted ? '配置已保存' : '面板已接收，请刷新核对配置'}${output.isEmpty ? '' : '\n执行输出：\n${output.length > 4000 ? output.substring(output.length - 4000) : output}'}';
        });
      }
    } catch (e) {
      if (mounted) setState(() => messages[key] = '设置未确认完成：$e。可刷新核对，避免重复提交。');
    } finally {
      if (mounted) setState(() => saving = null);
    }
  }

  Future<void> clean(String type) async {
    final label = type == 'node' ? 'Node.js' : 'Python';
    if (!await confirm(
      context,
      '清理 $label 依赖缓存？',
      '青龙会移除对应依赖缓存，并把已安装的 $label 依赖标记为安装失败。相关脚本可能需要重新安装依赖后才能运行。此操作不会自动重装依赖。',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => saving = 'clean');
    try {
      checkScope();
      await widget.host.m.api('PUT', '/system/config/dependence-clean', {
        'type': type,
      });
      checkScope();
      await widget.host.m.load('dependencies', force: true);
      if (mounted) {
        setState(() => messages['clean'] = '$label 缓存已清理，请按需重新安装依赖。');
      }
    } catch (e) {
      if (mounted) setState(() => messages['clean'] = '未能确认清理结果：$e');
    } finally {
      if (mounted) setState(() => saving = null);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: saving == null && dirty.isEmpty,
    onPopInvokedWithResult: (didPop, result) async {
      if (!didPop &&
          saving == null &&
          await confirm(context, '放弃未保存的设置？', '已保存的配置会保留，未保存的输入将丢失。') &&
          context.mounted) {
        dirty.clear();
        Navigator.pop(context);
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('依赖设置'),
        actions: [
          IconButton(
            tooltip: '重新读取设置',
            onPressed: loading || saving != null ? null : load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (loading) const LinearProgressIndicator(minHeight: 2),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(error!),
            ),
          for (final entry in fields.entries)
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.value.$1,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(
                        onPressed:
                            !loaded ||
                                saving != null ||
                                !dirty.contains(entry.key)
                            ? null
                            : () => save(entry.key),
                        child: Text(saving == entry.key ? '保存中…' : '保存'),
                      ),
                    ],
                  ),
                  TextField(
                    controller: controllers[entry.key],
                    style: const TextStyle(fontSize: 13, height: 1.4),
                    enabled: loaded && saving == null,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => setState(() => dirty.add(entry.key)),
                    decoration: InputDecoration(
                      hintText: entry.key == 'dependenceProxy'
                          ? 'http://127.0.0.1:7890'
                          : 'https://…',
                      suffixIcon: IconButton(
                        tooltip: '清空（保存后生效）',
                        onPressed: !loaded || saving != null
                            ? null
                            : () {
                                controllers[entry.key]!.clear();
                                setState(() => dirty.add(entry.key));
                              },
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(entry.value.$3, style: const TextStyle(fontSize: 11)),
                  if (messages[entry.key] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SelectableText(
                        messages[entry.key]!,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '依赖缓存',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  '清理会影响已安装依赖，可能需要重装。面板仅提供 Node.js 与 Python 清理接口。',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final type in ['node', 'python3'])
                      OutlinedButton.icon(
                        onPressed: !loaded || saving != null
                            ? null
                            : () => clean(type),
                        icon: const Icon(
                          Icons.cleaning_services_outlined,
                          size: 17,
                        ),
                        label: Text(
                          '清理 ${type == 'node' ? 'Node.js' : 'Python'}',
                        ),
                      ),
                  ],
                ),
                if (messages['clean'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(messages['clean']!),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
