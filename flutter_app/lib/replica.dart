part of 'main.dart';

Color _line(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? const Color(0xffd8dce7).withValues(alpha: .07)
    : const Color(0xff454954).withValues(alpha: .07);
Color _surface(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? const Color(0xff252527)
    : const Color(0xfffcf9fb);
Color _soft(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? const Color(0xff34343a)
    : const Color(0xffe6e4ea);
Color _primary(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? const Color(0xff74b4ff)
    : accent;
Widget _compactButton(
  BuildContext c,
  String title,
  IconData icon,
  VoidCallback? action, {
  bool primary = false,
  bool soft = false,
}) => OriginAction(
  action: action,
  builder: (onTap) => SizedBox(
    height: 34,
    child: TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: primary
            ? Theme.of(c).colorScheme.onPrimary
            : _primary(c),
        backgroundColor: primary
            ? _primary(c)
            : soft
            ? _soft(c)
            : _surface(c),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(40, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide.none,
        ),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(
        title,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  ),
);

extension _ReplicaResources on _ResourcePageState {
  Widget replicaBuild(BuildContext c) {
    final list = displayed;
    final title =
        {
          'tasks': '定时任务',
          'envs': '环境变量',
          'scripts': '脚本文件',
          'configs': '配置文件',
          'logs': '运行日志',
          'subscriptions': '订阅管理',
          'dependencies': '依赖管理',
          'applications': '应用管理',
        }[key] ??
        key;
    Future<void> runAll() async {
      if (await h.overlay(() => confirm(c, '运行全部已启用任务？', '将执行当前面板全部未禁用的任务。')) &&
          c.mounted) {
        await guard(
          c,
          () => m.action(
            key,
            'run',
            (m.cache[key] ?? []).where((r) => !disabled(r)).toList(),
          ),
        );
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        if (widget.showTitle) ...[
                          Flexible(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 7),
                        ],
                        Text(
                          '${list.length} 项',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(c).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (['tasks', 'scripts', 'configs'].contains(key)) ...[
                    _compactButton(
                      c,
                      '上传',
                      Icons.file_upload_outlined,
                      () => h.upload(key),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (key == 'envs') ...[
                    _compactButton(c, '工具', Icons.tune, () => h.envTools()),
                    const SizedBox(width: 6),
                  ],
                  if (key != 'logs')
                    _compactButton(
                      c,
                      key == 'dependencies'
                          ? '安装'
                          : key == 'envs'
                          ? '添加'
                          : '新建',
                      Icons.add,
                      () => key == 'dependencies'
                          ? h.dependencyForm(
                              type: filter >= 1 && filter <= 3 ? filter - 1 : 0,
                            )
                          : h.newRow(key),
                      primary: true,
                    ),
                ],
              ),
              const SizedBox(height: 9),
              if (widget.resource == 'scripts') ...[
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: _soft(c),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _line(c)),
                  ),
                  child: Row(
                    children: [
                      for (final e in {
                        'scripts': '脚本',
                        'configs': '配置',
                        'logs': '日志',
                      }.entries)
                        Expanded(
                          child: TextButton(
                            style: TextButton.styleFrom(
                              backgroundColor: key == e.key
                                  ? _surface(c)
                                  : Colors.transparent,
                              foregroundColor: key == e.key
                                  ? _primary(c)
                                  : Theme.of(c).colorScheme.onSurfaceVariant,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                            onPressed: () {
                              update(() {
                                key = e.key;
                                directory = '';
                                search.clear();
                                filter = 0;
                              });
                              unawaited(m.load(key));
                            },
                            child: Text(
                              e.value,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 9),
              ],
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    SizedBox(
                      height: 38,
                      child: TextField(
                        controller: search,
                        style: const TextStyle(fontSize: 13),
                        onChanged: (_) => update(() {}),
                        decoration: InputDecoration(
                          hintText: key == 'tasks'
                              ? '搜索任务名称或命令'
                              : key == 'envs'
                              ? '名称、备注或值'
                              : '搜索$title',
                          prefixIcon: const Icon(Icons.search, size: 17),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 30,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 6,
                          ),
                          fillColor: _soft(c),
                          suffixIcon: search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: '清空搜索',
                                  icon: const Icon(Icons.close, size: 15),
                                  onPressed: () => update(() => search.clear()),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (key == 'dependencies') ...[
                          Expanded(
                            child: _compactButton(
                              c,
                              '依赖设置',
                              Icons.tune_rounded,
                              h.dependencySettings,
                              soft: true,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (key == 'tasks') ...[
                          Expanded(
                            child: _compactButton(
                              c,
                              '运行全部',
                              Icons.playlist_play,
                              runAll,
                              soft: true,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (!['scripts', 'configs', 'logs'].contains(key)) ...[
                          Expanded(
                            child: _compactButton(
                              c,
                              editing ? '完成' : '编辑',
                              editing ? Icons.done : Icons.edit_note,
                              () => update(() {
                                editing = !editing;
                                selected.clear();
                              }),
                              soft: true,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: _compactButton(
                            c,
                            '刷新',
                            Icons.refresh_rounded,
                            () => m.load(key, force: true),
                            soft: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (key == 'tasks' || key == 'envs' || key == 'dependencies')
                SizedBox(
                  height: 48,
                  child: Row(
                    children:
                        (key == 'tasks'
                                ? ['全部', '进行中', '待运行', '已禁用']
                                : key == 'envs'
                                ? ['全部', '已启用', '已禁用']
                                : [
                                    '全部',
                                    ...dependencyTypes.values,
                                    if ((m.cache[key] ?? []).any(
                                      (row) => !dependencyTypes.containsKey(
                                        dependencyType(row),
                                      ),
                                    ))
                                      '其他',
                                  ])
                            .asMap()
                            .entries
                            .map(
                              (e) => Expanded(
                                child: InkWell(
                                  key: ValueKey(
                                    'resource-filter-$key-${e.key}',
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => update(() {
                                    filter = e.key;
                                    if (key == 'dependencies') selected.clear();
                                  }),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    curve: Curves.easeOutCubic,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                      vertical: 5,
                                    ),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: e.key == filter
                                          ? _primary(c).withValues(alpha: .13)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(11),
                                      border: Border.all(
                                        color: e.key == filter
                                            ? _primary(c).withValues(alpha: .24)
                                            : Colors.transparent,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          e.value,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            height: 1.15,
                                            fontSize: key == 'dependencies'
                                                ? 12
                                                : 14,
                                            fontWeight: e.key == filter
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                            color: e.key == filter
                                                ? _primary(c)
                                                : Theme.of(c)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                          ),
                                        ),
                                        if (key == 'dependencies')
                                          Text(
                                            '${(m.cache[key] ?? []).where((row) => e.key == 0 || (e.key == 4 ? !dependencyTypes.containsKey(dependencyType(row)) : dependencyType(row) == e.key - 1)).length}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              height: 1.1,
                                              color: Theme.of(c)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ),
              if (editing)
                Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => update(() {
                          if (list.isNotEmpty &&
                              list.every((r) => selected.contains(idOf(r)))) {
                            selected.removeAll(list.map(idOf));
                          } else {
                            selected.addAll(list.map(idOf));
                          }
                        }),
                        icon: Icon(
                          list.isNotEmpty &&
                                  list.every((r) => selected.contains(idOf(r)))
                              ? Icons.deselect
                              : Icons.select_all,
                          size: 17,
                        ),
                        label: Text(
                          '全选 (${selected.length})',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (final e in {
                          if (key == 'tasks') ...{
                            'run': ('运行', Icons.play_arrow),
                            'stop': ('停止', Icons.stop),
                          },
                          if ([
                            'tasks',
                            'envs',
                            'subscriptions',
                          ].contains(key)) ...{
                            'enable': ('启用', Icons.check_circle_outline),
                            'disable': ('禁用', Icons.block),
                          },
                          if (key == 'dependencies') ...{
                            'reinstall': ('重新安装', Icons.download_rounded),
                            'cancel': ('取消安装', Icons.cancel_outlined),
                          },
                          'delete': ('删除', Icons.delete_outline),
                        }.entries)
                          Expanded(
                            child: TextButton(
                              onPressed: selected.isEmpty
                                  ? null
                                  : () => bulk(e.key),
                              child: Column(
                                children: [
                                  Icon(e.value.$2, size: 18),
                                  const SizedBox(height: 3),
                                  Text(
                                    e.value.$1,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              if (directory.isNotEmpty)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.arrow_upward, size: 17),
                  title: Text(directory, style: const TextStyle(fontSize: 11)),
                  onTap: () => update(() {
                    directory = directory.contains('/')
                        ? directory.substring(0, directory.lastIndexOf('/'))
                        : '';
                    m.views['scriptsDir'] = directory;
                  }),
                ),
            ],
          ),
        ),
        if (m.loading.contains(key))
          const LinearProgressIndicator(minHeight: 2),
        if (m.errors[key] != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              m.errors[key]!,
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => m.load(key, force: true),
            child: list.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 70),
                      Center(
                        child: Text(
                          m.loading.contains(key)
                              ? '正在加载…'
                              : search.text.trim().isNotEmpty
                              ? '未找到匹配内容'
                              : key == 'dependencies' && filter != 0
                              ? '此分类暂无依赖'
                              : '暂无内容',
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    key: PageStorageKey('$key-$directory'),
                    padding: const EdgeInsets.fromLTRB(12, 9, 12, 94),
                    itemCount: list.length,
                    itemBuilder: (c, i) =>
                        replicaItem(c, list[i], i, list.length),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> openReplica(Json row) async {
    if (editing) {
      update(
        () => selected.contains(idOf(row))
            ? selected.remove(idOf(row))
            : selected.add(idOf(row)),
      );
      return;
    }
    if (key == 'tasks') {
      await guard(context, () => h.openTaskScript(row));
    } else if (['scripts', 'configs', 'logs'].contains(key)) {
      if (row['type'] == 'directory') {
        update(() => directory = filePath(row));
        m.views['scriptsDir'] = directory;
      } else {
        await guard(
          context,
          () => key == 'logs' ? h.openLog(key, row) : h.openEditor(key, row),
        );
      }
    } else if (key == 'envs') {
      await h.envDetail(row);
    } else {
      await menu(row);
    }
  }

  Widget replicaItem(BuildContext c, Json row, int index, int length) {
    final task = key == 'tasks',
        env = key == 'envs',
        file = ['scripts', 'configs', 'logs'].contains(key),
        pinned = task && flag(row['isPinned']),
        off = env ? row['status'] == 1 : disabled(row),
        active =
            (task || key == 'subscriptions') && running(row) ||
            key == 'dependencies' && [0, 3].contains(dependencyStatus(row));
    final status = task
        ? taskState(row)
        : env || key == 'subscriptions'
        ? (off
              ? '已禁用'
              : active
              ? '运行中'
              : '已启用')
        : key == 'dependencies'
        ? dependencyState(row)
        : '';
    final statusColor = key == 'dependencies'
        ? switch (dependencyStatus(row)) {
            0 || 3 => const Color(0xff236fb9),
            1 => const Color(0xff267d50),
            2 || 5 => const Color(0xffaa492c),
            6 => const Color(0xff98611f),
            _ => const Color(0xff536e7b),
          }
        : active
        ? const Color(0xff236fb9)
        : off
        ? const Color(0xffaa492c)
        : env
        ? const Color(0xff267d50)
        : const Color(0xff536e7b);
    final title = str(row['name'] ?? row['title'] ?? row['value']);
    final visible =
        m.views.putIfAbsent('env-visible', () => <String>{}) as Set<String>;
    Widget more() => IconButton(
      tooltip: '更多操作',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      onPressed: () => menu(row),
      icon: const Icon(Icons.more_horiz, size: 21),
    );
    Widget footerAction(
      String label,
      IconData icon,
      VoidCallback action, {
      bool tinted = false,
    }) => OriginAction(
      action: action,
      builder: (onTap) => TextButton.icon(
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          minimumSize: const Size(42, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          backgroundColor: tinted
              ? _primary(c).withValues(alpha: .10)
              : Colors.transparent,
          foregroundColor: tinted
              ? _primary(c)
              : Theme.of(c).colorScheme.onSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 10)),
      ),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (editing) ...[
              Icon(
                selected.contains(idOf(row))
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 21,
                color: _primary(c),
              ),
              const SizedBox(width: 7),
            ],
            if (env) ...[
              Container(
                width: 23,
                height: 23,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _soft(c),
                  border: Border.all(color: _line(c)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${index + 1}'.padLeft(2, '0'),
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(c).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (file) ...[
              Container(
                width: 31,
                height: 34,
                decoration: BoxDecoration(
                  color: _primary(c).withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  row['type'] == 'directory'
                      ? Icons.folder_outlined
                      : key == 'logs'
                      ? Icons.description_outlined
                      : Icons.code,
                  size: 19,
                  color: _primary(c),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (pinned) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: _primary(c).withValues(alpha: .13),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '置顶',
                            style: TextStyle(
                              color: _primary(c),
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: env || file ? 13 : 14,
                            fontWeight: task
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (file)
                    Text(
                      row['type'] == 'directory' ? '文件夹' : filePath(row),
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(c).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (status.isNotEmpty) ...[
              const SizedBox(width: 7),
              StateBadge(status, color: statusColor, animate: active),
            ],
            if (!task && !file && !editing)
              SizedBox(width: 30, height: 30, child: more()),
          ],
        ),
        if (task || key == 'subscriptions') ...[
          const SizedBox(height: 3),
          Row(
            children: [
              Icon(
                Icons.schedule,
                size: 11,
                color: Theme.of(c).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  str(row['schedule']).isEmpty ? '间隔执行' : str(row['schedule']),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(c).colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            str(row[task ? 'command' : 'url']),
            style: const TextStyle(fontSize: 12, height: 1.4),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          if (task) ...[
            metadataLine(
              c,
              'ID ${idOf(row)} · 创建',
              dateLabel(createdTime(row), compact: true),
            ),
            Wrap(
              spacing: 12,
              children: [
                metadataLine(c, '下次', m.nextTaskTime(row, compact: true)),
                metadataLine(c, '用时', durationLabel(row)),
              ],
            ),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  row['last_execution_time'] == null
                      ? '尚未执行'
                      : '上次 ${formatLast(row['last_execution_time'])}',
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(c).colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              footerAction(
                '日志',
                Icons.description_outlined,
                () => h.openLog(key, row),
              ),
              const SizedBox(width: 3),
              footerAction(
                active ? '停止' : '运行',
                active ? Icons.stop : Icons.play_arrow,
                () => guard(
                  c,
                  () => m.action(key, active ? 'stop' : 'run', [row]),
                ),
                tinted: true,
              ),
              const SizedBox(width: 3),
              Tooltip(
                message: '更多操作',
                child: footerAction('更多', Icons.more_horiz, () => menu(row)),
              ),
            ],
          ),
        ],
        if (env) ...[
          metadataLine(
            c,
            '备注',
            str(row['remarks']).isEmpty ? '无' : str(row['remarks']),
          ),
          Wrap(
            spacing: 12,
            children: [
              metadataLine(c, '创建', dateLabel(createdTime(row), compact: true)),
              metadataLine(c, '更新', dateLabel(updatedTime(row), compact: true)),
            ],
          ),
          const SizedBox(height: 7),
          Container(
            height: 34,
            decoration: BoxDecoration(
              color: _soft(c),
              border: Border.all(color: _line(c)),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 9),
                    child: Text(
                      visible.contains(idOf(row))
                          ? str(row['value'])
                          : '••••••••••••••••',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: visible.contains(idOf(row)) ? 0 : 1.1,
                        color: Theme.of(c).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 35,
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: _line(c))),
                  ),
                  child: IconButton(
                    tooltip: '复制变量值',
                    padding: EdgeInsets.zero,
                    onPressed: () => guard(
                      c,
                      () => m.native.call('copyText', {'text': row['value']}),
                    ),
                    icon: const Icon(Icons.copy_outlined, size: 18),
                  ),
                ),
                Container(
                  width: 35,
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: _line(c))),
                  ),
                  child: IconButton(
                    tooltip: visible.contains(idOf(row)) ? '隐藏变量值' : '显示变量值',
                    padding: EdgeInsets.zero,
                    onPressed: () => update(
                      () => visible.contains(idOf(row))
                          ? visible.remove(idOf(row))
                          : visible.add(idOf(row)),
                    ),
                    icon: Icon(
                      visible.contains(idOf(row))
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (key == 'dependencies') ...[
          const SizedBox(height: 5),
          Row(
            children: [
              Icon(
                switch (dependencyType(row)) {
                  0 => Icons.javascript,
                  1 => Icons.code_rounded,
                  2 => Icons.terminal,
                  _ => Icons.extension_outlined,
                },
                size: 14,
                color: _primary(c),
              ),
              const SizedBox(width: 5),
              Text(
                dependencyTypes[dependencyType(row)] ?? '其他',
                style: TextStyle(fontSize: 11, color: _primary(c)),
              ),
              if (str(row['remark']).isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    str(row['remark']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(c).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
        if (key == 'applications') ...[
          const SizedBox(height: 5),
          for (final entry in {
            'Client ID': str(row['client_id'] ?? row['clientId']),
            'Client Secret': str(row['client_secret'] ?? row['clientSecret']),
          }.entries)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${entry.key}  ${entry.key == 'Client Secret' && entry.value.isNotEmpty
                        ? '••••••••••••'
                        : entry.value.isEmpty
                        ? '面板未提供'
                        : entry.value}',
                    style: const TextStyle(fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: '复制 ${entry.key}',
                  visualDensity: VisualDensity.compact,
                  onPressed: entry.value.isEmpty
                      ? null
                      : () => guard(
                          c,
                          () =>
                              m.native.call('copyText', {'text': entry.value}),
                        ),
                  icon: const Icon(Icons.copy_outlined, size: 17),
                ),
              ],
            ),
          if (row['scopes'] is List && (row['scopes'] as List).isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '权限：${(row['scopes'] as List).map((scope) => applicationScopes[str(scope)] ?? str(scope)).join('、')}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(c).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ],
    );
    final grouped = file;
    final radius = grouped
        ? BorderRadius.vertical(
            top: index == 0 ? const Radius.circular(13) : Radius.zero,
            bottom: index == length - 1
                ? const Radius.circular(13)
                : Radius.zero,
          )
        : BorderRadius.circular(20);
    return OriginAction(
      action: () => openReplica(row),
      builder: (onTap) => Container(
        margin: EdgeInsets.only(
          bottom: grouped
              ? 0
              : task
              ? 6
              : 9,
        ),
        decoration: BoxDecoration(
          color: pinned
              ? (m.dark ? const Color(0xff273b58) : const Color(0xffe0e9fc))
              : _surface(c),
          border: Border.all(color: _line(c)),
          borderRadius: radius,
          boxShadow: grouped
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: m.dark ? 0 : .015),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(
                  border: env || task && (off || active)
                      ? Border(
                          left: BorderSide(
                            width: 3,
                            color: env
                                ? (off
                                      ? const Color(0xffdc8866)
                                      : const Color(0xff4baf79))
                                : active
                                ? const Color(0xff428bba)
                                : const Color(0xffc6815e),
                          ),
                        )
                      : null,
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: file
                      ? 10
                      : task
                      ? 8
                      : 10,
                ),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String formatLast(dynamic value) {
  final n = num.tryParse(str(value));
  if (n == null) return str(value);
  final date = DateTime.fromMillisecondsSinceEpoch(
    (n * (n > 100000000000 ? 1 : 1000)).toInt(),
  );
  return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

Widget replicaMore(BuildContext c, HomeState h) {
  Widget section(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 3, 4, 8),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: .6,
        color: Theme.of(c).colorScheme.onSurfaceVariant,
      ),
    ),
  );
  Widget overview(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback action,
  ) => Expanded(
    child: OriginAction(
      action: action,
      builder: (onTap) => GlassCard(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 9, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: _primary(c), size: 21),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(c).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  Widget entry(
    String title,
    IconData icon,
    VoidCallback action, {
    String? subtitle,
  }) => OriginAction(
    action: action,
    builder: (onTap) => ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 29,
        height: 29,
        decoration: BoxDecoration(
          color: _primary(c).withValues(alpha: .10),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 18, color: _primary(c)),
      ),
      title: Text(title, style: const TextStyle(fontSize: 13)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: const TextStyle(fontSize: 10)),
      trailing: const Icon(Icons.chevron_right, size: 16),
      onTap: onTap,
    ),
  );
  void resource(String key, String title) => h.route(
    Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ResourcePage(host: h, resource: key, showTitle: false),
    ),
  );
  Widget group(List<Widget> entries) => GlassCard(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
    child: Column(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) Divider(height: 1, color: _line(c)),
          entries[i],
        ],
      ],
    ),
  );
  return ListView(
    padding: const EdgeInsets.fromLTRB(12, 6, 12, 96),
    children: [
      Row(
        children: [
          const Text(
            '我的',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Text(
            '面板管理',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(c).colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          _compactButton(
            c,
            '外观',
            h.m.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            () {
              h.m.dark = !h.m.dark;
              h.m.changed();
              unawaited(h.m.native.call('appearance', {'dark': h.m.dark}));
            },
          ),
        ],
      ),
      const SizedBox(height: 9),
      OriginAction(
        action: () => h.route(ServersPage(host: h)),
        builder: (onTap) => GestureDetector(
          onTap: onTap,
          child: GlassCard(
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Image.asset(
                    'assets/app-icon.png',
                    width: 46,
                    height: 46,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        h.m.demo ? '示例面板' : str(h.m.server?['name']),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        h.m.demo ? '本地演示 · 可体验全部界面' : str(h.m.server?['url']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(c).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 17),
              ],
            ),
          ),
        ),
      ),
      Row(
        children: [
          overview(
            '仪表盘',
            '任务与系统状态',
            Icons.space_dashboard_outlined,
            () => h.route(DashboardPage(host: h)),
          ),
          const SizedBox(width: 8),
          overview(
            '兼容检测',
            '版本与功能可用性',
            Icons.verified_user_outlined,
            () => h.route(CompatibilityPage(host: h)),
          ),
        ],
      ),
      section('常用功能'),
      GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
        child: Row(
          children: [
            for (final item in [
              ('订阅管理', Icons.rss_feed, () => resource('subscriptions', '订阅管理')),
              (
                '脚本管理',
                Icons.folder_outlined,
                () {
                  h.m.navigate('scripts');
                },
              ),
              (
                '依赖管理',
                Icons.inventory_2_outlined,
                () => resource('dependencies', '依赖管理'),
              ),
            ])
              Expanded(
                child: OriginAction(
                  action: item.$3,
                  builder: (onTap) => InkWell(
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          Icon(item.$2, size: 26, color: _primary(c)),
                          const SizedBox(height: 9),
                          Text(item.$1, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      section('管理工具'),
      group([
        entry(
          '京东 CK 助手',
          Icons.cookie_outlined,
          () => h.route(JdPage(host: h)),
        ),
        entry('配置文件', Icons.tune, () => resource('configs', '配置文件')),
        entry('历史日志', Icons.history, () => resource('logs', '历史日志')),
        entry(
          '应用管理',
          Icons.apps_outlined,
          () => resource('applications', '应用管理'),
        ),
      ]),
      section('账号与通知'),
      group([
        entry(
          '通知设置',
          Icons.notifications_outlined,
          () => h.notificationSettings(),
        ),
        entry('账号安全', Icons.security_outlined, () => h.accountSettings()),
      ]),
      section('偏好与维护'),
      group([
        entry('连接管理', Icons.dns_outlined, () => h.route(ServersPage(host: h))),
        entry('文字大小', Icons.text_fields, () => h.fontSettings()),
        entry('日志清理', Icons.auto_delete_outlined, () => h.logCleanup()),
        entry('下载与更新', Icons.download_outlined, () => h.route(const AppInfoPage())),
        entry('用户协议', Icons.description_outlined, () => h.route(const AppInfoPage(agreement: true))),
        entry(
          '关于',
          Icons.info_outline,
          () => h.overlay(() => showAboutDialogResult(c)),
          subtitle: '青龙掌控 ${h.m.appVersion} · Flutter',
        ),
      ]),
    ],
  );
}
