part of 'main.dart';

extension Settings on HomeState {
  Future<void> fontSettings() async {
    await form(
      '界面字号',
      [
        const Field(
          'scale',
          '文字比例',
          options: {
            '0.9': '较小 · 90%',
            '1.0': '标准 · 100%',
            '1.1': '较大 · 110%',
            '1.2': '大 · 120%',
            '1.3': '特大 · 130%',
          },
        ),
      ],
      {'scale': m.textScale.toStringAsFixed(1)},
      (v) async {
        final scale = double.tryParse(v['scale']);
        if (scale == null || scale < .9 || scale > 1.3) {
          throw ApiFailure('文字比例无效');
        }
        await m.native.call('appearance', {'dark': m.dark, 'textScale': scale});
        m.textScale = scale;
        m.changed();
      },
    );
  }

  Future<void> notificationSettings() async {
    await guard(context, () async {
      final saved = Map<String, dynamic>.from(
        await m.api('GET', '/user/notification'),
      );
      final schema = jsonDecode(
        await rootBundle.loadString('assets/notifications.json'),
      ) as Map;
      final modes = rows(schema['modes']);
      final definitions = Map<String, dynamic>.from(schema['fields']);
      final fields = <Field>[
        Field(
          'notify_type',
          '通知渠道',
          options: {
            'closed': '关闭通知',
            for (final mode in modes) str(mode['value']): str(mode['label']),
          },
        ),
      ];
      final used = <String>{};
      for (final entry in definitions.entries) {
        for (final definition in rows(entry.value)) {
          final label = str(definition['label']), key = '${entry.key}:$label';
          if (!used.add(key)) continue;
          final items = rows(definition['items']);
          fields.add(
            Field(
              key,
              label,
              required: flag(definition['required']),
              help: str(definition['tip']),
              secret: RegExp(
                'password|token|secret|key',
                caseSensitive: false,
              ).hasMatch(label),
              options: items.isEmpty
                  ? null
                  : {
                      for (final item in items)
                        str(item['value']): str(item['label'] ?? item['value']),
                    },
              visible: (v) => v['notify_type'] == entry.key,
            ),
          );
        }
      }
      final initial = <String, dynamic>{
        'notify_type': str(saved['type']).isEmpty ? 'closed' : saved['type'],
      };
      for (final entry in saved.entries) {
        initial['${saved['type']}:${entry.key}'] = str(entry.value);
      }
      await form('面板通知设置', fields, initial, (v) async {
        final type = v['notify_type'],
            body = <String, dynamic>{'type': type == 'closed' ? '' : type};
        for (final definition in rows(definitions[type])) {
          final label = str(definition['label']),
              value = v['$type:$label'] ?? '';
          final original = rows(definition['items'])
              .where((i) => str(i['value']) == value)
              .firstOrNull;
          body[label] = original?['value'] ?? value;
        }
        if (!await overlay(
          () => confirm(context, '保存并发送测试通知？', '青龙服务器会向所配置的渠道发送测试通知。'),
        )) {
          throw ApiFailure('已取消保存');
        }
        await m.api('PUT', '/user/notification', body);
      }, submit: '保存并测试');
    });
  }

  Future<void> logCleanup() async {
    await guard(context, () async {
      final data = await m.api('GET', '/system/config');
      await form(
        '日志自动清理',
        [const Field('days', '保留天数', help: '留空关闭自动清理；填写正整数')],
        {'days': str(data?['info']?['logRemoveFrequency'])},
        (v) async {
          final days = int.tryParse(v['days']);
          if (str(v['days']).isNotEmpty && (days == null || days < 1)) {
            throw ApiFailure('请输入有效天数');
          }
          await m.api('PUT', '/system/config/log-remove-frequency', {
            'days': days,
          });
        },
      );
    });
  }

  Future<void> accountSettings() async {
    final option = await overlay(
      () => choose(context, '账号安全', {
        'history': '登录记录',
        'password': '修改账号密码',
        'logout': '退出当前面板账号',
      }),
    );
    if (option == 'history') {
      await route(
        LogPage(
          host: this,
          title: '登录记录',
          path: '/user/login-log',
          scope: m.epoch,
        ),
      );
    }
    if (option == 'password') {
      await form(
        '修改账号密码',
        [
          const Field('username', '账号', required: true),
          const Field('password', '新密码', required: true, secret: true),
        ],
        {'username': m.server?['username'] ?? ''},
        (v) async {
          await m.api('PUT', '/user', v);
          if (!m.demo) {
            await m.updateProfiles('logoutServer', {'id': m.activeId});
          }
        },
      );
    }
    if (option == 'logout' &&
        !m.demo &&
        await overlay(
          () => confirm(context, '退出当前账号？', '本机登录会话将被移除，可在连接管理中重新登录。'),
        )) {
      if (!mounted) return;
      await guard(
        context,
        () => m.updateProfiles('logoutServer', {'id': m.activeId}),
      );
    }
  }
}

class CompatibilityPage extends StatefulWidget {
  final HomeState host;
  const CompatibilityPage({super.key, required this.host});
  @override
  State<CompatibilityPage> createState() => _CompatibilityPageState();
}

class _CompatibilityPageState extends State<CompatibilityPage> {
  final results = <String, String>{};
  String version = '检测中…';
  bool busy = false;
  final checks = {
    '定时任务': '/crons?page=1&size=1',
    '环境变量': '/envs?searchValue=__ql_compat_no_match__',
    '脚本文件': '/scripts',
    '配置文件': '/configs/files',
    '日志目录': '/logs',
    '订阅管理': '/subscriptions',
    '依赖管理': '/dependencies',
    '应用管理': '/apps',
    '通知设置': '/user/notification',
    '仪表盘统计': '/dashboard/overview',
    '系统监控': '/dashboard/system',
  };
  @override
  void initState() {
    super.initState();
    run();
  }

  Future<void> run() async {
    if (busy) return;
    setState(() => busy = true);
    final scope = widget.host.m.epoch;
    try {
      final system = await widget.host.m.api('GET', '/system');
      if (mounted) {
        setState(
          () => version = str(system?['version']).isEmpty
              ? '版本未知'
              : str(system['version']),
        );
      }
    } catch (e) {
      if (mounted) setState(() => version = '$e');
    }
    final pending = checks.entries.toList();
    Future<void> worker() async {
      while (pending.isNotEmpty && mounted && scope == widget.host.m.epoch) {
        final item = pending.removeAt(0);
        String result;
        try {
          final data = await widget.host.m.api('GET', item.value);
          if (data is! List && data is! Map) throw ApiFailure('响应格式不受支持');
          result = '可用';
        } catch (e) {
          result = e is ApiFailure
              ? switch (e.status) {
                  401 => '登录失效',
                  403 => '权限不足',
                  404 || 410 => '接口不可用',
                  429 => '请求受限',
                  _ => '暂未确认',
                }
              : '连接失败';
        }
        if (mounted) setState(() => results[item.key] = result);
      }
    }

    await Future.wait([worker(), worker()]);
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('兼容检测'),
      actions: [
        IconButton(
          tooltip: '重新检测',
          onPressed: busy ? null : run,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('青龙面板版本', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 6),
              Text(
                version,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '检测只读取接口。显示可用代表读取成功，写入操作仍取决于账号权限。',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        if (busy) const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 12),
        ...checks.keys.map(
          (name) => GlassCard(
            child: Row(
              children: [
                Expanded(child: Text(name)),
                StateBadge(
                  results[name] ?? '等待检测',
                  color: results[name] == '可用' ? accent : warm,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class DashboardPage extends StatefulWidget {
  final HomeState host;
  const DashboardPage({super.key, required this.host});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final data = <String, dynamic>{};
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() => busy = true);
    final scope = widget.host.m.epoch;
    final jobs = {
      '任务': '/crons',
      '变量': '/envs',
      '订阅': '/subscriptions',
      '版本': '/system',
      '统计': '/dashboard/overview',
      '系统': '/dashboard/system',
      '趋势': '/dashboard/trend?days=7',
    };
    await Future.wait(
      jobs.entries.map((e) async {
        try {
          final result = await widget.host.m.api('GET', e.value);
          if (mounted && scope == widget.host.m.epoch) {
            setState(
              () => data[e.key] = e.key == '变量'
                  ? {'count': rows(result).length}
                  : result,
            );
          }
        } catch (_) {
          if (mounted) setState(() => data[e.key] = null);
        }
      }),
    );
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final stats = data['统计'] is Map ? data['统计'] as Map : const {},
        system = data['系统'] is Map ? data['系统'] as Map : const {},
        tasks = rows(data['任务']);
    final metrics = {
      '任务总数': data['任务'] == null ? '—' : '${tasks.length}',
      '运行中': data['任务'] == null ? '—' : '${tasks.where(running).length}',
      '环境变量': str(data['变量']?['count']).isEmpty
          ? '—'
          : str(data['变量']['count']),
      '订阅数量': data['订阅'] == null ? '—' : '${rows(data['订阅']).length}',
      '今日执行': str(stats['todayRuns']).isEmpty ? '—' : str(stats['todayRuns']),
      '成功率': stats['successRate'] == null ? '—' : '${stats['successRate']}%',
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('仪表盘'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (busy) const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 4),
            GlassCard(
              pinned: true,
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '当前面板',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.host.m.demo
                              ? '示例面板'
                              : str(widget.host.m.server?['name']),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '青龙 ${str(data['版本']?['version']).isEmpty ? '版本待获取' : str(data['版本']['version'])}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: _primary(context).withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(23),
                    ),
                    child: Icon(
                      Icons.dns_rounded,
                      size: 29,
                      color: _primary(context),
                    ),
                  ),
                ],
              ),
            ),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisExtent: 110 * MediaQuery.textScalerOf(context).scale(1),
              crossAxisSpacing: 10,
              mainAxisSpacing: 0,
              children: metrics.entries
                  .map(
                    (e) => GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(e.key, style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 7),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              e.value,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.w700,
                                color: _primary(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '系统信息',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  for (final e in {
                    '面板版本': data['版本']?['version'],
                    '系统': system['platform'],
                    '处理器': system['cpus'],
                    '内存占用': system['memUsagePercent'] == null
                        ? null
                        : '${system['memUsagePercent']}%',
                    '运行时间': system['uptime'] == null
                        ? null
                        : '${(num.tryParse(str(system['uptime'])) ?? 0) ~/ 3600} 小时',
                    '平均负载': system['loadAvg'] is List
                        ? (system['loadAvg'] as List).join(' / ')
                        : null,
                  }.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.key,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              e.value == null ? '暂不可用' : str(e.value),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
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
                    '近七日执行趋势',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  if (data['趋势'] is! List)
                    const Text('面板未提供此信息')
                  else
                    SizedBox(
                      height: 130 * MediaQuery.textScalerOf(context).scale(1),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: rows(data['趋势']).map((r) {
                          final success = num.tryParse(str(r['success'])) ?? 0,
                              fail = num.tryParse(str(r['fail'])) ?? 0;
                          final maximum = rows(data['趋势']).fold<num>(
                            1,
                            (a, b) =>
                                a >
                                    (num.tryParse(str(b['success'])) ?? 0) +
                                        (num.tryParse(str(b['fail'])) ?? 0)
                                ? a
                                : (num.tryParse(str(b['success'])) ?? 0) +
                                      (num.tryParse(str(b['fail'])) ?? 0),
                          );
                          return Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  '${success + fail}',
                                  style: const TextStyle(fontSize: 10),
                                ),
                                const SizedBox(height: 5),
                                Container(
                                  width: 19,
                                  height: (90 * fail / maximum).toDouble(),
                                  color: warm,
                                ),
                                Container(
                                  width: 19,
                                  height: (90 * success / maximum).toDouble(),
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: .7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  str(r['date']).split('T').first,
                                  style: const TextStyle(fontSize: 9),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
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
                    '最近任务',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  ...tasks
                      .take(5)
                      .map(
                        (r) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(str(r['name'])),
                          trailing: StateBadge(
                            taskState(r),
                            animate: running(r),
                            color: disabled(r) ? warm : accent,
                          ),
                          onTap: () => guard(
                            context,
                            () => widget.host.openTaskScript(r),
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
}

class HistoryPage extends StatefulWidget {
  final HomeState host;
  final Json node;
  final int scope;
  const HistoryPage({
    super.key,
    required this.host,
    required this.node,
    required this.scope,
  });
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Json> versions = [];
  Json? detail;
  List<String> comparison = [];
  String? error;
  bool busy = false, restoreBlocked = false;
  String get params => query({
    'filename': widget.node['title'],
    'path': widget.node['parent'] ?? '',
  });
  void scope() {
    if (widget.scope != widget.host.m.epoch) throw ApiFailure('面板已切换');
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      scope();
      final data = await widget.host.m.api('GET', '/scripts/history?$params');
      final list = rows(data?['versions']);
      if (data is! Map ||
          !RegExp(
            r'^[a-f0-9]{64}$',
            caseSensitive: false,
          ).hasMatch(str(data['currentHash']))) {
        throw ApiFailure('面板未提供受支持的脚本历史接口');
      }
      if (mounted) {
        setState(() {
          versions = list.take(100).toList();
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> select(Json version) async {
    setState(() => busy = true);
    try {
      scope();
      final data = Map<String, dynamic>.from(
        await widget.host.m.api(
          'GET',
          '/scripts/history/detail?$params&${query({'id': version['id']})}',
        ),
      );
      final old = data['version'];
      if (data['current'] is! String ||
          old is! Map ||
          old['content'] is! String ||
          utf8.encode(data['current']).length > 1048576 ||
          utf8.encode(old['content']).length > 1048576 ||
          digest(data['current']) != data['currentHash'] ||
          digest(old['content']) != old['hash'] ||
          str(old['id']) != str(version['id'])) {
        throw ApiFailure('历史内容校验失败，请刷新后重试');
      }
      if (mounted) {
        setState(() {
          detail = data;
          comparison = diffLines(data['current'], data['version']['content']);
          restoreBlocked = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> restore() async {
    if (detail == null || restoreBlocked) return;
    if (!await widget.host.overlay(
      () => confirm(context, '恢复所选历史版本？', '这会覆盖服务器上的当前脚本，恢复前会再次校验文件。'),
    )) {
      return;
    }
    setState(() => busy = true);
    bool submitted = false;
    try {
      scope();
      final current = await widget.host.readFile('scripts', widget.node);
      if (digest(current) != detail!['currentHash']) {
        throw ApiFailure('当前文件已变化，请重新载入历史后比较');
      }
      submitted = true;
      await widget.host.m.api('PUT', '/scripts/history/restore', {
        'filename': widget.node['title'],
        'path': widget.node['parent'] ?? '',
        'id': detail!['version']['id'],
        'expectedHash': detail!['currentHash'],
      });
      final latest = await widget.host.readFile('scripts', widget.node);
      if (digest(latest) != detail!['version']['hash']) {
        throw ApiFailure('恢复结果尚未确认，请重新打开文件核对');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          restoreBlocked = submitted;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('历史对比与恢复'),
        actions: [
          IconButton(
            tooltip: '刷新历史',
            onPressed: busy
                ? null
                : () {
                    setState(() => detail = null);
                    load();
                  },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (busy) const LinearProgressIndicator(minHeight: 2),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          if (detail == null)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      '仅在面板提供历史接口时可用。恢复使用带当前文件校验的专用接口。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  ...versions.map(
                    (v) => GlassCard(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(str(v['createdAt'])),
                        subtitle: Text(
                          '${v['size'] ?? '—'} 字节 · ${str(v['hash']).substring(0, 8.clamp(0, str(v['hash']).length))}',
                        ),
                        trailing: const Icon(Icons.compare_arrows),
                        onTap: busy ? null : () => select(v),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() => detail = null),
                    icon: const Icon(Icons.arrow_back, size: 17),
                    label: const Text('版本列表'),
                  ),
                  const Spacer(),
                  actionButton(
                    '恢复此版本',
                    Icons.restore,
                    busy || restoreBlocked ? null : restore,
                    primary: true,
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('− 当前版本  /  + 历史版本', style: TextStyle(fontSize: 12)),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(14),
                itemCount: comparison.length,
                itemBuilder: (c, i) {
                  final line = comparison[i];
                  return Container(
                    color: line.startsWith('+')
                        ? accent.withValues(alpha: .1)
                        : line.startsWith('-')
                        ? Colors.red.withValues(alpha: .07)
                        : null,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    child: SelectableText(
                      line,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: line.startsWith('+')
                            ? accent
                            : line.startsWith('-')
                            ? const Color(0xffad4545)
                            : null,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

List<String> diffLines(String current, String historical) {
  final a = current.split('\n'), b = historical.split('\n');
  if (a.length * b.length > 800000) {
    return [
      '对比内容较大，以下按版本分段显示',
      ...a.take(3000).map((s) => '- $s'),
      ...b.take(3000).map((s) => '+ $s'),
    ];
  }
  final dp = List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      dp[i][j] = a[i] == b[j]
          ? dp[i + 1][j + 1] + 1
          : dp[i + 1][j] > dp[i][j + 1]
          ? dp[i + 1][j]
          : dp[i][j + 1];
    }
  }
  final result = <String>[];
  var i = 0, j = 0;
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && a[i] == b[j]) {
      result.add('  ${a[i]}');
      i++;
      j++;
    } else if (j < b.length &&
        (i == a.length || dp[i][j + 1] >= dp[i + 1][j])) {
      result.add('+ ${b[j++]}');
    } else {
      result.add('- ${a[i++]}');
    }
  }
  return result;
}

class JdPage extends StatefulWidget {
  final HomeState host;
  const JdPage({super.key, required this.host});
  @override
  State<JdPage> createState() => _JdPageState();
}

class _JdPageState extends State<JdPage> {
  final controller = TextEditingController();
  JdCookie? parsed;
  String? error;
  bool busy = false, reveal = false;
  HomeState get h => widget.host;
  @override
  void dispose() {
    controller.clear();
    controller.dispose();
    super.dispose();
  }

  void parse() {
    try {
      setState(() {
        parsed = JdCookie.parse(controller.text);
        error = null;
      });
    } catch (e) {
      setState(() {
        parsed = null;
        error = '$e';
      });
    }
  }

  Future<void> login() async {
    setState(() => busy = true);
    try {
      final result = await h.m.native.call('jdLogin');
      if (result['cancelled'] != true && mounted) {
        controller.text = str(result['cookie']);
        parse();
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> review() async {
    final value = parsed;
    if (value == null || value.type == 'WSKEY') return;
    final scope = h.m.epoch, panel = h.m.activeId;
    setState(() => busy = true);
    try {
      final list = rows(await h.m.api('GET', '/envs'));
      final matches = list.where((r) {
        if (r['name'] != 'JD_COOKIE') return false;
        try {
          return JdCookie.parse(str(r['value'])).identity == value.identity;
        } catch (_) {
          return false;
        }
      }).toList();
      Json? target;
      if (matches.length == 1) target = matches.first;
      if (matches.length > 1) {
        final id = await h.overlay(
          () => choose(context, '存在多个相同账号，请选择更新项', {
            for (var i = 0; i < matches.length; i++)
              '$i':
                  '序号 ${list.indexOf(matches[i]) + 1} · ${matches[i]['remarks'] ?? '无备注'} · ${matches[i]['status'] == 1 ? '已禁用' : '已启用'}',
          }),
        );
        if (id == null) return;
        target = matches[int.parse(id)];
      }
      final selected = target;
      final fingerprint = selected == null
          ? null
          : jsonEncode([
              selected['id'] ?? selected['_id'],
              selected['name'],
              selected['value'],
              selected['remarks'],
              selected['status'],
            ]);
      await h.form(
        selected == null ? '新增京东变量' : '更新京东变量',
        [
          const Field('panel', '目标面板', readOnly: true),
          const Field('account', '账号（已脱敏）', readOnly: true),
          const Field('type', '识别类型', readOnly: true),
          const Field('remarks', '备注', help: '更新时留空保留原备注'),
        ],
        {
          'panel': h.m.demo ? '本地演示' : str(h.m.server?['name']),
          'account': value.identity.length > 3
              ? '${value.identity.substring(0, 2)}***${value.identity.substring(value.identity.length - 1)}'
              : '***',
          'type': value.type,
          'remarks': '',
        },
        (v) async {
          if (scope != h.m.epoch || panel != h.m.activeId) {
            throw ApiFailure('面板已切换，请重新预览');
          }
          final fresh = rows(await h.m.api('GET', '/envs'));
          if (selected != null) {
            final actual = fresh
                .where((r) => idOf(r) == idOf(selected))
                .firstOrNull;
            if (actual == null ||
                jsonEncode([
                      actual['id'] ?? actual['_id'],
                      actual['name'],
                      actual['value'],
                      actual['remarks'],
                      actual['status'],
                    ]) !=
                    fingerprint) {
              throw ApiFailure('变量已变化，请返回后重新预览');
            }
          } else if (fresh.any((r) {
            try {
              return r['name'] == 'JD_COOKIE' &&
                  JdCookie.parse(str(r['value'])).identity == value.identity;
            } catch (_) {
              return false;
            }
          })) {
            throw ApiFailure('此账号已存在，请返回后重新预览');
          }
          final body = {
            'name': 'JD_COOKIE',
            'value': value.cookie,
            'remarks': str(v['remarks']).isEmpty
                ? (selected?['remarks'] ?? '')
                : v['remarks'],
            if (selected != null) 'id': selected['id'] ?? selected['_id'],
          };
          await h.m.api(
            selected == null ? 'POST' : 'PUT',
            '/envs',
            selected == null ? [body] : body,
          );
          await h.m.load('envs', force: true);
          controller.clear();
          if (mounted) setState(() => parsed = null);
        },
        submit: selected == null ? '确认新增' : '确认更新',
      );
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('京东 CK 助手')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '登录提取网页 CK',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 9),
              const Text(
                '在京东官方页面完成登录后，点击提取。只读取本 App 登录窗口的 Cookie。',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 15),
              actionButton(
                busy ? '处理中…' : '打开京东登录',
                Icons.open_in_new,
                busy ? null : login,
                primary: true,
              ),
            ],
          ),
        ),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '粘贴识别',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                obscureText: !reveal,
                maxLines: 1,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  hintText: 'Cookie 或 export JD_COOKIE=…',
                  suffixIcon: IconButton(
                    tooltip: reveal ? '隐藏' : '显示',
                    onPressed: () => setState(() => reveal = !reveal),
                    icon: Icon(
                      reveal
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  actionButton(
                    '读取剪贴板',
                    Icons.content_paste,
                    busy
                        ? null
                        : () => guard(context, () async {
                            controller.text = str(
                              (await h.m.native.call(
                                'readClipboardText',
                              ))['text'],
                            );
                            parse();
                          }),
                  ),
                  actionButton('识别', Icons.manage_search, busy ? null : parse),
                ],
              ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(error!, style: const TextStyle(color: Colors.red)),
          ),
        if (parsed != null)
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StateBadge(parsed!.type),
                const SizedBox(height: 10),
                const Text('已识别完整字段，敏感值已隐藏。', style: TextStyle(fontSize: 13)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    actionButton(
                      '复制标准格式',
                      Icons.copy,
                      busy
                          ? null
                          : () => guard(
                              context,
                              () => h.m.native.call('copyText', {
                                'text': parsed!.cookie,
                              }),
                            ),
                    ),
                    if (parsed!.type != 'WSKEY')
                      actionButton(
                        '预览导入 JD_COOKIE',
                        Icons.playlist_add_check,
                        busy ? null : review,
                        primary: true,
                      ),
                  ],
                ),
                if (parsed!.type == 'WSKEY')
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('WSKEY 仅支持识别和复制，不会写入 JD_COOKIE。'),
                  ),
              ],
            ),
          ),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'pt_key + pt_pin 可识别为网页 CK，但不能仅凭字段可靠区分 MCK / APPCK。提取结果不代表在线有效性检测。',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    ),
  );
}
