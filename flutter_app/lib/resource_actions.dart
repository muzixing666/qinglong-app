part of 'main.dart';

extension _ResourceActions on _ResourcePageState {
  Future<void> fileLongPress(Json row) async {
    final epoch = m.epoch;
    final resource = key;
    final choice = await h.overlay(
      () => choose(context, '文件操作', {
        'delete': row['type'] == 'directory' ? '删除文件夹' : '删除文件',
      }),
    );
    if (choice != 'delete' || !mounted) return;
    final path = filePath(row), folder = row['type'] == 'directory';
    if (!await h.overlay(
      () => confirm(
        context,
        folder ? '确认删除文件夹？' : '确认删除文件？',
        '$path\n${folder ? '文件夹及其中所有文件会一并删除。' : '文件会从面板删除。'}此操作不可撤销。',
      ),
    )) {
      return;
    }
    if (!mounted) return;
    await guard(context, () async {
      if (!validFilename(str(row['title'])) ||
          !validDirectory(str(row['parent']))) {
        throw ApiFailure('文件路径无效');
      }
      if (epoch != m.epoch) throw ApiFailure('面板已切换');
      await m.api('DELETE', resource == 'logs' ? '/logs' : '/scripts', {
        'filename': row['title'],
        'path': str(row['parent']),
        'type': folder ? 'directory' : 'file',
      });
      if (epoch == m.epoch) {
        await m.load(resource, force: true);
        showAppToast('已删除');
      }
    });
  }

  Future<void> reorderEnvironment(
    List<Json> visibleRows,
    int from,
    int to,
  ) async {
    if (editing || from == to || (envReordering && envOrderScope != m.epoch)) {
      return;
    }
    final source = visibleRows[from], rest = [...visibleRows]..removeAt(from);
    final after = to >= rest.length;
    final target = rest[after ? rest.length - 1 : to];
    final scope = m.epoch, previous = [...?m.cache['envs']];
    final fromGlobal = previous.indexWhere((r) => idOf(r) == idOf(source));
    final targetIndex = previous.indexWhere((r) => idOf(r) == idOf(target));
    if (fromGlobal < 0 || targetIndex < 0) return;
    var destination = targetIndex + (after ? 1 : 0);
    if (fromGlobal < destination) destination--;
    if (destination == fromGlobal) return;
    envCommitted ??= [...previous];
    final reordered = [...previous];
    reordered.insert(destination, reordered.removeAt(fromGlobal));
    envMoves.add((
      source: idOf(source),
      target: idOf(target),
      after: after,
      scope: scope,
    ));
    m.cache['envs'] = reordered;
    m.changed();
    if (envReordering) return;
    envReordering = true;
    envOrderScope = scope;
    try {
      while (envMoves.isNotEmpty && scope == m.epoch) {
        final move = envMoves.removeAt(0), committed = envCommitted!;
        if (move.scope != scope) break;
        final old = committed.indexWhere((r) => idOf(r) == move.source);
        final target = committed.indexWhere((r) => idOf(r) == move.target);
        if (old < 0 || target < 0) throw ApiFailure('变量列表已变化，请刷新后再排序');
        var next = target + (move.after ? 1 : 0);
        if (old < next) next--;
        if (old == next) continue;
        await m.api('PUT', '/envs/${move.source}/move', {
          'fromIndex': old,
          'toIndex': next,
        });
        if (scope != m.epoch) break;
        committed.insert(next, committed.removeAt(old));
      }
    } catch (e) {
      envOrderScope = -1;
      envMoves.clear();
      if (scope == m.epoch) {
        m.cache['envs'] = [...envCommitted!];
        m.changed();
        await m.load('envs', force: true);
      }
      if (mounted) showError(context, e);
    } finally {
      envMoves.clear();
      envCommitted = null;
      envReordering = false;
    }
  }

  Widget environmentList(List<Json> rows) {
    final positions = <String, int>{
      for (final (i, row) in (m.cache['envs'] ?? <Json>[]).indexed)
        idOf(row): i + 1,
    };
    final counts = <String, int>{};
    for (final row in rows) {
      counts.update(str(row['name']), (n) => n + 1, ifAbsent: () => 1);
    }
    final entries = <({String group, Json? row})>[];
    if (groupEnvs) {
      final groups = <String, List<Json>>{};
      for (final row in rows) {
        groups.putIfAbsent(str(row['name']), () => []).add(row);
      }
      final namedGroups = groups.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      for (final group in namedGroups) {
        entries.add((group: group.key, row: null));
        if (!collapsedEnvNames.contains(group.key)) {
          entries.addAll(
            group.value.map((row) => (group: group.key, row: row)),
          );
        }
      }
    } else {
      entries.addAll(rows.map((row) => (group: str(row['name']), row: row)));
    }
    return ReorderableListView.builder(
      key: const PageStorageKey('env-order'),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 94),
      physics: const AlwaysScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      autoScrollerVelocityScalar: 24,
      onReorderItem: (from, to) {
        final source = entries[from];
        if (source.row == null || editing) return;
        final remaining = [...entries]..removeAt(from);
        final next = to < remaining.length ? remaining[to] : null;
        final previous = to > 0 ? remaining[to - 1] : null;
        final before =
            next?.row != null && (!groupEnvs || next!.group == source.group);
        final after =
            previous?.row != null &&
            (!groupEnvs || previous!.group == source.group);
        if (!before && !after) return;
        final target = before ? next!.row! : previous!.row!;
        final visible = rows
            .where((row) => !groupEnvs || str(row['name']) == source.group)
            .toList();
        final old = visible.indexWhere((row) => idOf(row) == idOf(source.row!));
        final without = [...visible]..removeAt(old);
        final insertion =
            without.indexWhere((row) => idOf(row) == idOf(target)) +
            (before ? 0 : 1);
        unawaited(reorderEnvironment(visible, old, insertion));
      },
      proxyDecorator: (child, index, animation) => RepaintBoundary(
        child: Material(type: MaterialType.transparency, child: child),
      ),
      itemCount: entries.length,
      itemBuilder: (c, i) {
        final entry = entries[i], row = entry.row;
        if (row != null) {
          return RepaintBoundary(
            key: ValueKey('env-${idOf(row)}'),
            child: replicaItem(
              c,
              row,
              i,
              entries.length,
              draggable: !editing,
              dragEnabled: true,
              position: positions[idOf(row)],
            ),
          );
        }
        final collapsed = collapsedEnvNames.contains(entry.group);
        return InkWell(
          key: ValueKey('env-group-${entry.group}'),
          borderRadius: BorderRadius.circular(10),
          onTap: () => update(() {
            if (collapsed) {
              collapsedEnvNames.remove(entry.group);
            } else {
              collapsedEnvNames.add(entry.group);
            }
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: collapsed ? 0 : .25,
                  duration: const Duration(milliseconds: 160),
                  child: const Icon(Icons.chevron_right, size: 19),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    entry.group.isEmpty ? '未命名' : entry.group,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${counts[entry.group]}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(c).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
