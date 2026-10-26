part of 'main.dart';

class ResourcePage extends StatefulWidget {
  final HomeState host;
  final String resource;
  final bool showTitle;
  const ResourcePage({
    super.key,
    required this.host,
    required this.resource,
    this.showTitle = true,
  });
  @override
  State<ResourcePage> createState() => _ResourcePageState();
}

class _ResourcePageState extends State<ResourcePage>
    with AutomaticKeepAliveClientMixin {
  void update(VoidCallback action) => setState(action);
  HomeState get h => widget.host;
  PanelModel get m => h.m;
  late String key = widget.resource;
  final search = TextEditingController();
  final selected = <String>{};
  bool editing = false;
  int filter = 0;
  String directory = '';
  bool groupEnvs = false, envReordering = false;
  final collapsedEnvNames = <String>{};
  final envMoves = <({String source, String target, bool after, int scope})>[];
  List<Json>? envCommitted;
  int envOrderScope = -1;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    m.addListener(changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!['tasks', 'envs', 'scripts'].contains(widget.resource)) {
        unawaited(m.load(key));
      }
      changed();
    });
  }

  void changed() {
    if (!mounted) return;
    if (['tasks', 'envs', 'scripts'].contains(widget.resource) &&
        widget.resource != m.page &&
        !(widget.resource == 'scripts' &&
            ['configs', 'logs'].contains(m.page))) {
      return;
    }
    if ((widget.resource == m.page ||
            (widget.resource == 'scripts' &&
                ['scripts', 'configs', 'logs'].contains(m.page))) &&
        !m.cache.containsKey(key) &&
        !m.loading.contains(key) &&
        !m.errors.containsKey(key)) {
      unawaited(m.load(key));
    }
    setState(() {});
  }

  @override
  void dispose() {
    m.removeListener(changed);
    search.dispose();
    super.dispose();
  }

  List<Json> get displayed {
    var list = m.cache[key] ?? <Json>[];
    if (['scripts', 'logs'].contains(key)) {
      list = flatten(list).where((r) => str(r['parent']) == directory).toList();
    }
    final word = search.text.trim().toLowerCase();
    list = list
        .where(
          (r) =>
              word.isEmpty ||
              [
                r['name'],
                r['command'],
                r['remarks'],
                r['remark'],
                r['title'],
              ].any((v) => str(v).toLowerCase().contains(word)),
        )
        .toList();
    if (key == 'tasks') {
      list = list
          .where(
            (r) =>
                filter == 0 ||
                filter == 1 && running(r) ||
                filter == 2 && !running(r) && !disabled(r) ||
                filter == 3 && disabled(r),
          )
          .toList();
      list = pinnedTasksFirst(list);
    }
    if (key == 'envs' && filter != 0) {
      list = list
          .where((r) => filter == 1 ? r['status'] != 1 : r['status'] == 1)
          .toList();
    }
    if (key == 'dependencies' && filter != 0) {
      list = list
          .where(
            (row) => filter == 4
                ? !dependencyTypes.containsKey(dependencyType(row))
                : dependencyType(row) == filter - 1,
          )
          .toList();
    }
    return list;
  }

  Future<void> bulk(String operation) async {
    final items = displayed.where((r) => selected.contains(idOf(r))).toList();
    if (items.isEmpty) return;
    if (key == 'tasks' && operation == 'delete') {
      if (await h.deleteTasks(items) && mounted) {
        setState(() {
          selected.clear();
          editing = false;
        });
      }
      return;
    }
    if (operation == 'delete' &&
        !await h.overlay(
          () => confirm(context, '删除 ${items.length} 项？', '删除后无法直接撤销，请确认已备份。'),
        )) {
      return;
    }
    if (!mounted) return;
    await guard(context, () async {
      await m.action(key, operation, items);
      if (mounted) {
        setState(() {
          selected.clear();
          editing = false;
        });
      }
    });
  }

  Future<void> menu(Json row) async {
    final operation = await h.overlay(
      () => choose(context, '${row['name'] ?? row['title'] ?? '操作'}', {
        'edit': '编辑',
        if (key == 'tasks') ...{
          'copy-task': '复制任务',
          'details': '任务详情',
          'history': '日志历史',
          'log': '查看日志',
          'pin': flag(row['isPinned']) ? '取消置顶' : '置顶任务',
        },
        if (['tasks', 'envs', 'subscriptions'].contains(key))
          'toggle': key == 'envs'
              ? (row['status'] == 1 ? '启用' : '禁用')
              : (disabled(row) ? '启用' : '禁用'),
        if (key == 'envs') ...{'copy': '复制变量值', 'move': '调整顺序'},
        if (key == 'applications') ...{
          'copy-id': '复制 Client ID',
          'copy': '复制 Client Secret',
          'reset': '重置密钥',
        },
        if (key == 'dependencies') ...{
          'reinstall': '重新安装',
          'cancel': '取消安装',
          'log': '查看安装日志',
        },
        'delete': '删除',
      }),
    );
    if (operation == null) return;
    if (!mounted) return;
    await guard(context, () async {
      switch (operation) {
        case 'copy-task':
          await h.taskForm(row, duplicate: true);
        case 'details':
          await h.taskDetails(row);
        case 'history':
          await h.taskHistory(row);
        case 'copy-id':
          await m.native.call('copyText', {
            'text': str(row['client_id'] ?? row['clientId']),
          });
        case 'edit':
          if (key == 'dependencies') {
            return;
          }
          await h.newRow(key, row);
        case 'log':
          await h.openLog(key, row);
        case 'pin':
          await m.action(key, flag(row['isPinned']) ? 'unpin' : 'pin', [row]);
        case 'toggle':
          await m.action(
            key,
            key == 'envs'
                ? (row['status'] == 1 ? 'enable' : 'disable')
                : (disabled(row) ? 'enable' : 'disable'),
            [row],
          );
        case 'delete':
          if (key == 'tasks') {
            await h.deleteTasks([row]);
            return;
          }
          if (await h.overlay(
            () => confirm(
              context,
              '删除此项目？',
              '${row['name'] ?? row['title']} 将从面板删除。',
            ),
          )) {
            await m.action(key, 'delete', [row]);
          }
        case 'copy':
          await m.native.call('copyText', {
            'text': key == 'envs'
                ? str(row['value'])
                : str(row['client_secret'] ?? row['clientSecret']),
          });
        case 'reset':
          if (await h.overlay(
            () => confirm(context, '重置密钥？', '使用此密钥的客户端需要更新配置。'),
          )) {
            await m.api('PUT', '/apps/${idOf(row)}/reset-secret');
            await m.load(key, force: true);
          }
        case 'move':
          await h.form(
            '调整变量顺序',
            [const Field('position', '目标序号', required: true)],
            {'position': (m.cache[key]!.indexOf(row) + 1).toString()},
            (v) async {
              final position = int.tryParse(v['position']);
              if (position == null ||
                  position < 1 ||
                  position > m.cache[key]!.length) {
                throw ApiFailure('序号超出范围');
              }
              await m.api('PUT', '/envs/${idOf(row)}/move', {
                'fromIndex': m.cache[key]!.indexOf(row),
                'toIndex': position - 1,
              });
              await m.load(key, force: true);
            },
          );
        case 'reinstall':
        case 'cancel':
          await m.action(key, operation, [row]);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return replicaBuild(context);
  }
}

extension Management on HomeState {
  Future<void> taskForm(Json? row, {bool duplicate = false}) async {
    final create = row == null || duplicate;
    await form(
      duplicate
          ? '复制任务'
          : row == null
          ? '新建任务'
          : '编辑任务',
      [
        const Field('name', '任务名称', required: true),
        const Field('command', '执行命令', required: true, multiline: true),
        const Field(
          'schedule',
          '定时规则',
          required: true,
          help: '支持 5 / 6 位 cron；按面板时区执行，也可手动修改',
          presets: taskSchedulePresets,
        ),
      ],
      duplicate ? taskCopyValues(row!) : row ?? {'schedule': '0 9 * * *'},
      (v) async {
        if (!validCron(v['schedule'])) throw ApiFailure('定时规则格式不正确');
        await m.api(
          create ? 'POST' : 'PUT',
          '/crons',
          create
              ? taskEditableValues(v)
              : {
                  for (final key in ['name', 'command', 'schedule'])
                    key: v[key],
                  'id': row['id'] ?? row['_id'],
                },
        );
        await m.load('tasks', force: true);
      },
    );
  }

  Future<void> envForm([Json? row]) async {
    await form(
      row == null ? '新建变量' : '编辑变量',
      [
        const Field('name', '变量名称', required: true),
        const Field('value', '变量值', required: true, multiline: true),
        const Field('remarks', '备注', multiline: true),
      ],
      row ?? {},
      (v) async {
        final body = {
          for (final key in ['name', 'value', 'remarks', 'labels'])
            if (v.containsKey(key)) key: v[key],
          if (row != null) 'id': row['id'] ?? row['_id'],
        };
        await m.api(
          row == null ? 'POST' : 'PUT',
          '/envs',
          row == null ? [body] : body,
        );
        await m.load('envs', force: true);
      },
    );
  }

  Future<void> envDetail(Json row) async {
    final operation = await overlay(
      () => showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (c) {
          bool reveal = false;
          return StatefulBuilder(
            builder: (c, state) => SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(c).height * .85,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 25),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        str(row['name']),
                        style: Theme.of(c).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      StateBadge(
                        row['status'] == 1 ? '已禁用' : '已启用',
                        color: row['status'] == 1 ? warm : accent,
                      ),
                      const SizedBox(height: 15),
                      SelectableText(
                        reveal ? str(row['value']) : '••••••••••••',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '备注：${str(row['remarks']).isEmpty ? '无' : row['remarks']}',
                      ),
                      metadataLine(c, '创建', dateLabel(createdTime(row))),
                      metadataLine(c, '更新', dateLabel(updatedTime(row))),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          actionButton(
                            reveal ? '隐藏' : '显示',
                            reveal
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            () => state(() => reveal = !reveal),
                          ),
                          actionButton(
                            '复制',
                            Icons.copy,
                            () => guard(
                              c,
                              () => m.native.call('copyText', {
                                'text': row['value'],
                              }),
                            ),
                          ),
                          actionButton(
                            '编辑',
                            Icons.edit_outlined,
                            () => Navigator.pop(c, 'edit'),
                            primary: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    if (operation == 'edit') await envForm(row);
  }

  Future<void> envTools() async {
    final operation = await overlay(
      () => choose(context, '变量工具', {
        'jd': '京东 CK 助手',
        'export': '导出变量备份',
        'import': '导入变量备份',
        'sync': '同步到其他面板',
      }),
    );
    if (operation == 'jd') {
      await route(JdPage(host: this));
      return;
    }
    if (operation == 'export') {
      if (!mounted) return;
      await guard(context, () async {
        final list = rows(await m.api('GET', '/envs'));
        if (await overlay(
          () => confirm(context, '导出变量备份？', '备份文件包含完整变量值，请妥善保管。'),
        )) {
          await m.native.call('exportText', {
            'filename': 'qinglong-envs.json',
            'content': jsonEncode({
              'format': 'qinglong-envs',
              'version': 1,
              'envs': list,
            }),
          });
        }
      });
    }
    if (operation == 'import') {
      if (!mounted) return;
      await guard(context, () async {
        final file = await m.native.call('pickScript');
        if (file['cancelled'] == true) return;
        final raw = jsonDecode(file['content']);
        final list = rows(raw is Map ? raw['envs'] : raw);
        if (list.isEmpty ||
            list.any((r) => str(r['name']).isEmpty || r['value'] is! String)) {
          throw ApiFailure('不是有效的变量备份文件');
        }
        if (await overlay(
          () => confirm(context, '导入 ${list.length} 个变量？', '将新增变量，不会覆盖同名变量。'),
        )) {
          await m.api(
            'POST',
            '/envs',
            list
                .map(
                  (r) => {
                    'name': r['name'],
                    'value': r['value'],
                    'remarks': r['remarks'] ?? '',
                  },
                )
                .toList(),
          );
          await m.load('envs', force: true);
        }
      });
    }
    if (operation == 'sync') {
      final target = await overlay(
        () => choose(context, '同步到面板', {
          for (final s in m.servers)
            if (s['id'] != m.activeId) str(s['id']): str(s['name']),
        }),
      );
      if (target == null) return;
      if (!mounted) return;
      await guard(context, () async {
        final list = rows(await m.api('GET', '/envs'));
        if (await overlay(
          () => confirm(
            context,
            '新增同步 ${list.length} 项？',
            '目标面板已有的同名变量将保留。请确认目标面板可信。',
          ),
        )) {
          await m.native.call('request', {
            'serverId': target,
            'method': 'POST',
            'path': '/envs',
            'body': list
                .map(
                  (r) => {
                    'name': r['name'],
                    'value': r['value'],
                    'remarks': r['remarks'] ?? '',
                  },
                )
                .toList(),
          });
        }
      });
    }
  }

  Future<void> dependencyForm({int type = 0}) async {
    await form(
      '安装依赖',
      [
        const Field(
          'type',
          '依赖类型',
          options: {'0': 'Node.js', '1': 'Python', '2': 'Linux'},
        ),
        const Field(
          'name',
          '依赖名称',
          required: true,
          multiline: true,
          help: '多个名称换行分隔',
        ),
        const Field('remark', '备注'),
      ],
      {'type': '$type'},
      (v) async {
        final names = str(v['name'])
            .split(RegExp(r'\s+'))
            .where((s) => s.isNotEmpty)
            .toSet();
        if (names.any((n) => RegExp(r'[;&|`<>]').hasMatch(n))) {
          throw ApiFailure('依赖名称包含无效字符');
        }
        await m.api(
          'POST',
          '/dependencies',
          names
              .map(
                (n) => {
                  'name': n,
                  'type': int.parse(v['type']),
                  'remark': v['remark'] ?? '',
                },
              )
              .toList(),
        );
        await m.load('dependencies', force: true);
      },
      submit: '安装',
    );
  }

  Future<void> applicationForm([Json? row]) async {
    final selectedScopes = (row?['scopes'] as List? ?? ['crons', 'envs'])
        .map(str)
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    await form(
      row == null ? '新建应用' : '编辑应用',
      [
        const Field('name', '应用名称', required: true),
        Field(
          'scopes',
          '权限范围',
          required: true,
          multiple: true,
          options: {
            ...applicationScopes,
            for (final scope in selectedScopes)
              if (!applicationScopes.containsKey(scope)) scope: '其他权限（$scope）',
          },
          help: '勾选此应用可以访问的面板功能',
        ),
      ],
      {'name': row?['name'] ?? '', 'scopes': selectedScopes},
      (v) async {
        await m.api(row == null ? 'POST' : 'PUT', '/apps', {
          'name': v['name'],
          'scopes': List<String>.from(v['scopes']),
          if (row != null) 'id': row['id'],
        });
        await m.load('applications', force: true);
      },
    );
  }

  Future<void> subscriptionForm([Json? row]) async {
    final initial = <String, dynamic>{
      'type': 'public-repo',
      'schedule_type': 'crontab',
      'schedule': '0 1 * * *',
      'autoAddCron': true,
      'autoDelCron': true,
      'pull_type': 'ssh-key',
      'interval_type': 'days',
      'interval_value': '1',
      ...?row,
    };
    if (row?['interval_schedule'] is Map) {
      initial['interval_type'] = row!['interval_schedule']['type'];
      initial['interval_value'] = str(row['interval_schedule']['value']);
    }
    if (row?['pull_option'] is Map) {
      initial.addAll(Map<String, dynamic>.from(row!['pull_option']));
    }
    final fields = <Field>[
      Field(
        'name',
        '名称',
        required: true,
        help: '支持粘贴 ql repo / raw 命令，自动填入配置',
        changed: (v) {
          try {
            final imported = subscriptionCommand(str(v['name']));
            if (imported != null) v.addAll(imported);
          } catch (_) {
            /* Incomplete typing stays editable; required fields still validate on save. */
          }
        },
      ),
      const Field(
        'type',
        '类型',
        required: true,
        options: {'public-repo': '公开仓库', 'private-repo': '私有仓库', 'file': '单文件'},
      ),
      const Field('url', '链接', required: true),
      Field('branch', '分支', visible: (v) => v['type'] != 'file'),
      const Field('alias', '唯一值', help: '留空根据仓库链接和分支自动生成'),
      Field(
        'pull_type',
        '私有仓库验证',
        options: const {'ssh-key': 'SSH 私钥', 'user-pwd': '账号密码'},
        visible: (v) => v['type'] == 'private-repo',
      ),
      Field(
        'private_key',
        'SSH 私钥',
        multiline: true,
        visible: (v) =>
            v['type'] == 'private-repo' && v['pull_type'] == 'ssh-key',
      ),
      Field(
        'username',
        '仓库账号',
        visible: (v) =>
            v['type'] == 'private-repo' && v['pull_type'] == 'user-pwd',
      ),
      Field(
        'password',
        '仓库密码',
        secret: true,
        visible: (v) =>
            v['type'] == 'private-repo' && v['pull_type'] == 'user-pwd',
      ),
      const Field(
        'schedule_type',
        '定时类型',
        options: {'crontab': 'crontab', 'interval': 'interval'},
      ),
      Field(
        'schedule',
        '定时规则',
        required: true,
        help: '秒（可选） 分 时 天 月 周',
        visible: (v) => v['schedule_type'] == 'crontab',
      ),
      Field(
        'interval_type',
        '间隔单位',
        options: const {
          'seconds': '秒',
          'minutes': '分',
          'hours': '时',
          'days': '天',
        },
        visible: (v) => v['schedule_type'] == 'interval',
      ),
      Field(
        'interval_value',
        '间隔数值',
        required: true,
        visible: (v) => v['schedule_type'] == 'interval',
      ),
      const Field('whitelist', '白名单', help: '多个关键词使用竖线 | 分隔'),
      const Field('blacklist', '黑名单', help: '多个关键词使用竖线 | 分隔'),
      const Field('dependences', '依赖文件', help: '多个关键词使用竖线 | 分隔'),
      const Field('extensions', '文件后缀'),
      const Field('sub_before', '执行前', multiline: true),
      const Field('sub_after', '执行后', multiline: true),
      const Field(
        'proxy',
        '代理',
        help: 'HTTP / SOCKS5，例如 http://127.0.0.1:1080',
      ),
      const Field('autoAddCron', '自动添加任务', toggle: true),
      const Field('autoDelCron', '自动删除任务', toggle: true),
    ];
    await form(row == null ? '创建订阅' : '编辑订阅', fields, initial, (v) async {
      if (v['schedule_type'] == 'crontab' && !validCron(v['schedule'])) {
        throw ApiFailure('定时规则格式不正确');
      }
      final interval = int.tryParse(str(v['interval_value']));
      if (v['schedule_type'] == 'interval' &&
          (interval == null || interval < 1)) {
        throw ApiFailure('间隔必须为正整数');
      }
      final uri = Uri.tryParse(v['url']);
      if (v['type'] != 'private-repo' &&
          (uri == null ||
              !['http', 'https'].contains(uri.scheme) ||
              uri.host.isEmpty)) {
        throw ApiFailure('订阅链接格式不正确');
      }
      final proxy = str(v['proxy']);
      if (proxy.isNotEmpty &&
          !['http', 'https', 'socks5'].contains(Uri.tryParse(proxy)?.scheme)) {
        throw ApiFailure('代理格式不正确');
      }
      final body = <String, dynamic>{
        for (final name in [
          'name',
          'type',
          'url',
          'branch',
          'schedule_type',
          'whitelist',
          'blacklist',
          'dependences',
          'extensions',
          'sub_before',
          'sub_after',
          'proxy',
        ])
          name: v[name] ?? '',
        'alias': str(v['alias']).isEmpty
            ? ('${uri?.pathSegments.join('_').replaceAll('.git', '') ?? 'subscription'}_${v['branch'] ?? ''}')
                  .replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_')
            : v['alias'],
        'schedule': v['schedule_type'] == 'crontab' ? v['schedule'] : '',
        'autoAddCron': flag(v['autoAddCron']),
        'autoDelCron': flag(v['autoDelCron']),
        if (row != null) 'id': row['id'],
      };
      if (v['schedule_type'] == 'interval') {
        body['interval_schedule'] = {
          'type': v['interval_type'],
          'value': interval,
        };
      }
      if (v['type'] == 'private-repo') {
        if (v['pull_type'] == 'ssh-key' &&
            str(v['private_key']).isEmpty &&
            (row?['pull_option'] == null ||
                row?['pull_type'] != v['pull_type'])) {
          throw ApiFailure('请填写 SSH 私钥');
        }
        if (v['pull_type'] == 'user-pwd' &&
            (str(v['username']).isEmpty || str(v['password']).isEmpty) &&
            (row?['pull_option'] == null ||
                row?['pull_type'] != v['pull_type'])) {
          throw ApiFailure('请同时填写仓库账号与密码');
        }
        body['pull_type'] = v['pull_type'];
        body['pull_option'] = v['pull_type'] == 'ssh-key'
            ? {'private_key': v['private_key'] ?? ''}
            : {
                'username': v['username'] ?? '',
                'password': v['password'] ?? '',
              };
      }
      if (v['type'] == 'file') body['branch'] = '';
      if (str(body['alias']).length > 100) {
        body['alias'] = str(body['alias']).substring(0, 100);
      }
      await m.api(row == null ? 'POST' : 'PUT', '/subscriptions', body);
      await m.load('subscriptions', force: true);
    });
  }
}

class MorePage extends StatelessWidget {
  final HomeState host;
  const MorePage({super.key, required this.host});
  @override
  Widget build(BuildContext context) => replicaMore(context, host);
}

Future<void> showAboutDialogResult(BuildContext context) async {
  showAboutDialog(
    context: context,
    applicationName: '青龙掌控',
    applicationVersion: '0.22.0 · Flutter',
    applicationIcon: Image.asset('assets/app-icon.png', width: 50, height: 50),
    children: [
      const Text('by：Muzixing'),
      const SizedBox(height: 8),
      const Text('连接已有青龙面板。功能可用性以面板版本、接口和当前账号权限为准。'),
    ],
  );
}

class ServersPage extends StatefulWidget {
  final HomeState host;
  const ServersPage({super.key, required this.host});
  @override
  State<ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends State<ServersPage> {
  HomeState get h => widget.host;
  Future<void> edit([Json? row]) async {
    await h.form(
      row == null ? '添加面板' : '编辑面板',
      [
        const Field('name', '面板名称', required: true),
        const Field(
          'url',
          '面板地址',
          required: true,
          help: '例如 https://ql.example.com',
        ),
        const Field(
          'authMode',
          '登录方式',
          options: {'password': '账号密码', 'application': '开放接口应用'},
        ),
        Field(
          'username',
          '账号',
          required: true,
          visible: (v) => v['authMode'] == 'password',
        ),
        Field(
          'password',
          '密码',
          secret: true,
          help: row == null ? '' : '留空可保留有效的现有会话',
          visible: (v) => v['authMode'] == 'password',
        ),
        Field('code', '两步验证码', visible: (v) => v['authMode'] == 'password'),
        Field(
          'clientId',
          'Client ID',
          required: true,
          visible: (v) => v['authMode'] == 'application',
        ),
        Field(
          'clientSecret',
          'Client Secret',
          secret: true,
          visible: (v) => v['authMode'] == 'application',
        ),
        const Field(
          'allowHttp',
          '允许 HTTP 明文连接',
          toggle: true,
          help: '只有面板确实使用 HTTP 时才需要开启',
        ),
      ],
      row ?? {'authMode': 'password', 'allowHttp': false},
      (v) => h.m.updateProfiles('saveServer', v),
      submit: '验证并保存',
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('连接管理'),
      actions: [
        TextButton.icon(
          onPressed: () => edit(),
          icon: const Icon(Icons.add, size: 19),
          label: const Text('添加'),
        ),
      ],
    ),
    body: ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: h.m.servers.length + 1,
      onReorderItem: (from, to) async {
        if (from >= h.m.servers.length) return;
        if (to > h.m.servers.length) to = h.m.servers.length;
        final ids = h.m.servers.map((s) => s['id']).toList();
        ids.insert(to, ids.removeAt(from));
        await guard(
          context,
          () => h.m.updateProfiles('reorderServers', {'ids': ids}),
        );
        if (mounted) setState(() {});
      },
      itemBuilder: (c, i) {
        if (i == h.m.servers.length) {
          return GlassCard(
            key: const ValueKey('demo'),
            child: ListTile(
              title: const Text('演示面板'),
              subtitle: const Text('本地数据，可用于体验界面'),
              leading: const Icon(Icons.science_outlined),
              onTap: () async {
                await h.m.changePanel(demonstration: true);
                if (c.mounted) Navigator.pop(c);
              },
            ),
          );
        }
        final row = h.m.servers[i];
        return GlassCard(
          key: ValueKey(row['id']),
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(str(row['name'])),
                subtitle: Text(
                  str(row['url']),
                  style: const TextStyle(fontSize: 12),
                ),
                leading: Icon(
                  row['id'] == h.m.activeId && !h.m.demo
                      ? Icons.check_circle
                      : Icons.dns_outlined,
                  color: accent,
                ),
                onTap: () async {
                  await guard(c, () => h.m.changePanel(id: row['id']));
                  if (c.mounted) Navigator.pop(c);
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => edit(row),
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    label: const Text('编辑'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      if (await h.overlay(
                        () => confirm(c, '删除连接？', '只删除本机保存的连接配置。'),
                      )) {
                        if (!c.mounted) return;
                        await guard(
                          c,
                          () => h.m.updateProfiles('deleteServer', {
                            'id': row['id'],
                          }),
                        );
                        if (mounted) setState(() {});
                      }
                    },
                    icon: const Icon(Icons.delete_outline, size: 17),
                    label: const Text('删除'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}
