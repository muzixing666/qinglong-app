import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef Json = Map<String, dynamic>;
String str(dynamic value) => value == null ? '' : '$value';
List<Json> rows(dynamic value) {
  if (value is Map) return rows(value['data']);
  return value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : [];
}

String idOf(Json row) => str(row['id'] ?? row['_id']);
DateTime? panelDate(dynamic value) {
  if (value == null || str(value).trim().isEmpty) return null;
  final number = num.tryParse(str(value));
  if (number != null) {
    if (number <= 0 || number > 8640000000000000) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      (number < 100000000000 ? number * 1000 : number).round(),
    ).toLocal();
  }
  return DateTime.tryParse(str(value))?.toLocal();
}

String dateLabel(dynamic value, {bool compact = false}) {
  final date = panelDate(value);
  if (date == null) return '面板未提供';
  String pad(int n) => '$n'.padLeft(2, '0');
  return '${compact ? '' : '${date.year}-'}${pad(date.month)}-${pad(date.day)} ${pad(date.hour)}:${pad(date.minute)}${compact ? '' : ':${pad(date.second)}'}';
}

dynamic createdTime(Json row) =>
    row['createdAt'] ?? row['created_at'] ?? row['create_time'];
dynamic updatedTime(Json row) =>
    row['updatedAt'] ?? row['updated_at'] ?? row['update_time'];
String durationLabel(Json row) {
  final seconds = num.tryParse(str(row['last_running_time']));
  if (seconds == null ||
      seconds < 0 ||
      panelDate(row['last_execution_time']) == null) {
    return '尚无记录';
  }
  return seconds < 60
      ? '${seconds.toStringAsFixed(seconds % 1 == 0 ? 0 : 1)} 秒'
      : '${seconds ~/ 60} 分 ${(seconds % 60).round()} 秒';
}

String digest(String text) => sha256.convert(utf8.encode(text)).toString();
bool flag(dynamic value) => value == true || value == 1 || value == '1';
const applicationScopes = {
  'crons': '定时任务',
  'envs': '环境变量',
  'subscriptions': '订阅管理',
  'configs': '配置文件',
  'scripts': '脚本管理',
  'logs': '日志管理',
  'dependencies': '依赖管理',
  'system': '系统信息',
  'dashboard': '仪表盘',
};
const dependencyTypes = {0: 'Node.js', 1: 'Python', 2: 'Linux'};
const taskSchedulePresets = {
  '每 5 分钟': '*/5 * * * *',
  '每 30 分钟': '*/30 * * * *',
  '每小时': '0 * * * *',
  '每天 00:00': '0 0 * * *',
  '每天 09:00': '0 9 * * *',
  '周一 09:00': '0 9 * * 1',
};
int dependencyType(Json row) {
  final value = str(row['type']).toLowerCase();
  return int.tryParse(value) ??
      switch (value) {
        'nodejs' || 'node.js' => 0,
        'python' || 'python3' => 1,
        'linux' => 2,
        _ => -1,
      };
}

int dependencyStatus(Json row) => int.tryParse(str(row['status'])) ?? -1;
String dependencyState(Json row) {
  const states = ['安装中', '已安装', '安装失败', '卸载中', '已卸载', '卸载失败', '排队中', '已取消'];
  final status = dependencyStatus(row);
  return status >= 0 && status < states.length ? states[status] : '未知状态';
}

// List.sort is unstable when ordinary rows compare equal. Partition instead so
// pinning cannot pull an unrelated row forward after a deletion or rebuild.
List<Json> pinnedTasksFirst(Iterable<Json> source) {
  final pinned = <Json>[], ordinary = <Json>[];
  for (final row in source) {
    (flag(row['isPinned']) ? pinned : ordinary).add(row);
  }
  return [...pinned, ...ordinary];
}

bool disabled(Json row) => row.containsKey('isDisabled')
    ? flag(row['isDisabled'])
    : row.containsKey('is_disabled')
    ? flag(row['is_disabled'])
    : row['status'] == 2;
bool running(Json row) => row['status'] == 0 || row['status'] == 3;
String taskState(Json row) => running(row)
    ? (row['status'] == 3 ? '排队中' : '运行中')
    : disabled(row)
    ? '已禁用'
    : '待运行';
String query(Map<String, dynamic> args) =>
    Uri(queryParameters: args.map((k, v) => MapEntry(k, str(v)))).query;
List<Json> flatten(List<Json> list, [String parent = '']) {
  final result = <Json>[];
  for (final entry in list) {
    final row = {...entry, 'parent': entry['parent'] ?? parent};
    result.add(row);
    result.addAll(
      flatten(
        rows(row['children']),
        [row['parent'], row['title']].where((e) => str(e).isNotEmpty).join('/'),
      ),
    );
  }
  return result;
}

String filePath(Json row) => [
  row['parent'],
  row['title'] ?? row['value'],
].where((e) => str(e).isNotEmpty).join('/');

// DOM textareas and CodeMirror normalize line endings on load.
String editorText(String value) =>
    value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

class ApiFailure implements Exception {
  final String message;
  final int status;
  ApiFailure(this.message, [this.status = 0]);
  @override
  String toString() => message;
}

class Native {
  static const channel = MethodChannel('qinglong/native');
  Future<dynamic> call(String action, [Json payload = const {}]) async {
    final raw = await channel
        .invokeMethod<String>(
          'call',
          jsonEncode({'action': action, 'payload': payload}),
        )
        .timeout(
          Duration(
            seconds: action == 'jdLogin'
                ? 600
                : action == 'pickScript' || action == 'exportText'
                ? 150
                : 65,
          ),
        );
    final packet = jsonDecode(raw!);
    if (packet['ok'] != true) {
      throw ApiFailure(
        str(packet['error']),
        int.tryParse(str(packet['errorInfo']?['httpStatus'])) ?? 0,
      );
    }
    if (action == 'copyText') {
      unawaited(channel.invokeMethod<void>('toast', '已复制').catchError((_) {}));
    }
    return packet['data'];
  }

  Future<String> editorGet([int? viewId]) async =>
      await channel
          .invokeMethod<String>('editorGet', viewId)
          .timeout(const Duration(seconds: 3)) ??
      '';
  Future<void> editorAction(String action, [int? viewId]) =>
      channel.invokeMethod(
        'editorAction',
        viewId == null ? action : {'viewId': viewId, 'action': action},
      );
}

class PanelModel extends ChangeNotifier {
  @override
  void dispose() {
    epoch++;
    forecastGeneration++;
    super.dispose();
  }

  void changed() => notifyListeners();
  final Native native;
  PanelModel({Native? native}) : native = native ?? Native();
  List<Json> servers = [];
  String activeId = '', page = 'tasks';
  String appVersion = '0.22.0';
  final Map<String, Json> forecasts = {};
  Json? systemInfo;
  Future<Json>? _systemLoad;
  int forecastGeneration = 0;
  Future<Json> readSystemInfo({bool force = false}) async {
    if (!force && systemInfo != null) return systemInfo!;
    if (_systemLoad != null) return _systemLoad!;
    final scope = epoch;
    final future = () async {
      final data = await api('GET', '/system/config');
      final info = data is Map && data['info'] is Map
          ? Map<String, dynamic>.from(data['info'])
          : <String, dynamic>{};
      if (scope != epoch) throw ApiFailure('面板已切换');
      systemInfo = info;
      return info;
    }();
    _systemLoad = future;
    try {
      return await future;
    } finally {
      if (scope == epoch) _systemLoad = null;
    }
  }

  Future<void> forecastTasks() async {
    final scope = epoch, generation = ++forecastGeneration;
    final tasks = (cache['tasks'] ?? [])
        .where((r) => !disabled(r))
        .map(
          (r) => {
            'id': idOf(r),
            'schedule': r['schedule'],
            'extra_schedules': r['extra_schedules'],
          },
        )
        .toList();
    try {
      Json info = {};
      try {
        info = await readSystemInfo();
      } catch (_) {}
      if (scope != epoch || generation != forecastGeneration) return;
      final data = await native.call('forecastTasks', {
        'timezone': str(info['timezone']),
        'tasks': tasks,
      });
      if (scope != epoch || generation != forecastGeneration || data is! Map) {
        return;
      }
      forecasts.clear();
      for (final row in rows(data['rows'])) {
        forecasts[idOf(row)] = {
          ...row,
          'source': data['source'],
          'zone': data['zone'],
        };
      }
      notifyListeners();
    } catch (_) {
      /* Forecasts are optional and must not block task access. */
    }
  }

  String nextTaskTime(Json row, {bool compact = false}) {
    if (disabled(row)) return '已禁用';
    final direct = row['nextRunTime'] ?? row['next_run_time'];
    if (panelDate(direct) != null) return dateLabel(direct, compact: compact);
    final forecast = forecasts[idOf(row)];
    if (forecast == null) return '待计算';
    if (forecast['next'] == null) return '规则或时区暂不支持';
    return '${dateLabel(forecast['next'], compact: compact)} · 估算';
  }

  bool demo = false, dark = false, nativeDock = false, initialized = false;
  double textScale = 1;
  String? startupError;
  int epoch = 0, dockRequest = 0, taskSyncedAt = 0;
  final Map<String, List<Json>> cache = {};
  final Map<String, String> errors = {};
  final Set<String> loading = {};
  final Map<String, Future<void>> _loads = {};
  final Map<String, Object> views = {};
  final DemoPanel demoPanel = DemoPanel();
  Json? get server => servers.where((s) => s['id'] == activeId).firstOrNull;
  static const endpoints = {
    'tasks': '/crons',
    'envs': '/envs',
    'subscriptions': '/subscriptions',
    'scripts': '/scripts',
    'configs': '/configs/files',
    'logs': '/logs',
    'dependencies': '/dependencies',
    'applications': '/apps',
  };
  Future<void> initialize() async {
    try {
      final data = Map<String, dynamic>.from(await native.call('bootstrap'));
      servers = rows(data['servers']);
      activeId = str(data['activeId']);
      final initialPage = str(data['shortcutPage']);
      if (['tasks', 'envs', 'scripts', 'more'].contains(initialPage)) {
        page = initialPage;
      }
      if (str(data['version']).isNotEmpty) appVersion = str(data['version']);
      dark = data['dark'] == true;
      textScale = (num.tryParse(str(data['textScale'])) ?? 1).toDouble().clamp(
        .9,
        1.3,
      );
      nativeDock = data['nativeDock'] == true;
      if (const bool.fromEnvironment('QL_DEMO_ONLY')) {
        demo = true;
      } else if (servers.isEmpty) {
        demo = true;
      }
    } catch (e) {
      startupError = '$e';
    }
    initialized = true;
    notifyListeners();
    if (startupError == null) {
      unawaited(
        load(['tasks', 'envs', 'scripts'].contains(page) ? page : 'tasks'),
      );
    }
  }

  Future<dynamic> api(String method, String path, [dynamic body]) async {
    if (demo) return demoPanel.request(method, path, body);
    if (activeId.isEmpty) throw ApiFailure('请先添加面板连接');
    final result = await native.call('request', {
      'serverId': activeId,
      'method': method,
      'path': path,
      'body': body,
    });
    return result is Map ? result['data'] : result;
  }

  Future<void> load(String key, {bool force = false}) {
    if (_loads.containsKey(key)) return _loads[key]!;
    if (!force && cache.containsKey(key)) return Future.value();
    final token = epoch;
    loading.add(key);
    errors.remove(key);
    notifyListeners();
    final future = () async {
      try {
        final data = await api('GET', endpoints[key]!);
        if (data is! List && !(data is Map && data['data'] is List)) {
          throw ApiFailure('面板返回的列表格式不受支持');
        }
        if (token == epoch) {
          cache[key] = rows(data);
          if (key == 'tasks') {
            taskSyncedAt = DateTime.now().millisecondsSinceEpoch;
            unawaited(forecastTasks());
          }
        }
      } catch (e) {
        if (token == epoch) errors[key] = '$e';
      } finally {
        if (token == epoch) {
          loading.remove(key);
          _loads.remove(key);
          notifyListeners();
        }
      }
    }();
    _loads[key] = future;
    return future;
  }

  Future<void> changePanel({String? id, bool demonstration = false}) async {
    if (id != null) {
      final data = await native.call('selectServer', {'id': id});
      servers = rows(data['servers']);
      activeId = str(data['activeId']);
    }
    epoch++;
    forecastGeneration++;
    forecasts.clear();
    systemInfo = null;
    _systemLoad = null;
    demo = demonstration;
    cache.clear();
    taskSyncedAt = 0;
    loading.clear();
    _loads.clear();
    errors.clear();
    views.clear();
    notifyListeners();
    unawaited(load('tasks'));
  }

  Future<void> updateProfiles(String action, Json payload) async {
    final previousId = activeId;
    final state = await native.call(action, payload);
    if (state['requiresTwoFactor'] == true) {
      throw ApiFailure('需要两步验证码，请填写验证码后再次登录');
    }
    servers = rows(state['servers']);
    activeId = str(state['activeId']);
    if (action == 'reorderServers' ||
        action == 'deleteServer' && activeId == previousId) {
      notifyListeners();
      return;
    }
    await changePanel(demonstration: servers.isEmpty);
  }

  void navigate(String target) {
    page = target;
    notifyListeners();
    if (endpoints.containsKey(target)) unawaited(load(target));
  }

  Future<void> action(String key, String operation, List<Json> items) async {
    final scope = epoch, ids = items.map((e) => e['id'] ?? e['_id']).toList();
    await api(
      operation == 'delete' ? 'DELETE' : 'PUT',
      '${endpoints[key]}${operation == 'delete' ? '' : '/$operation'}',
      ids,
    );
    if (scope != epoch) return;
    if (key == 'dependencies') {
      // Removal can queue an uninstall rather than immediately delete the row.
      await load(key, force: true);
      return;
    }
    if (operation == 'delete') {
      cache[key]?.removeWhere((r) => ids.contains(r['id'] ?? r['_id']));
    } else {
      for (final row in cache[key] ?? <Json>[]) {
        if (!ids.contains(row['id'] ?? row['_id'])) continue;
        if (operation == 'run') row['status'] = 0;
        if (operation == 'stop') row['status'] = 1;
        if (operation == 'enable' || operation == 'disable') {
          final value = operation == 'disable' ? 1 : 0;
          if (key == 'envs') {
            row['status'] = value;
          } else {
            row['isDisabled'] = value;
            row['is_disabled'] = value;
          }
        }
        if (operation == 'pin' || operation == 'unpin') {
          row['isPinned'] = operation == 'pin' ? 1 : 0;
        }
      }
    }
    notifyListeners();
  }
}

class TaskScriptPlan {
  final Map<String, Json> files;
  final Map<String, int> shared;
  final int unresolvedTasks;
  const TaskScriptPlan(this.files, this.shared, this.unresolvedTasks);
}

Json taskEditableValues(Json task) => {
  for (final key in [
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
  ])
    if (task.containsKey(key)) key: jsonDecode(jsonEncode(task[key])),
};

Json taskCopyValues(Json task) => {
  ...taskEditableValues(task),
  'name': '${str(task['name']).isEmpty ? '任务' : task['name']} 副本',
};

TaskScriptPlan taskScriptPlan(
  List<Json> selected,
  List<Json> allTasks,
  List<Json> scripts,
) {
  final files = {
    for (final file in flatten(scripts))
      if (file['type'] != 'directory' &&
          validFilename(str(file['title'])) &&
          validDirectory(str(file['parent'])))
        filePath(file): file,
  };
  Set<String> resolve(Json task) {
    final result = <String>{};
    final command = str(task['command']);
    final directory = str(task['work_dir']).trim();
    final candidates = scriptCandidates(command);
    if (RegExp(r'[;&|<>]').hasMatch(command) ||
        candidates.length != 1 ||
        directory.isNotEmpty &&
            !['/ql/scripts', '/ql/data/scripts'].contains(directory)) {
      return result;
    }
    for (final candidate in candidates) {
      if (files.containsKey(candidate)) {
        result.add(candidate);
      } else if (!candidate.contains('/')) {
        final matches = files.keys
            .where((path) => path.split('/').last == candidate)
            .toList();
        if (matches.length == 1) result.add(matches.single);
      }
    }
    return result;
  }

  final chosen = <String>{};
  var unresolved = 0;
  for (final task in selected) {
    final found = resolve(task);
    if (found.isEmpty) unresolved++;
    chosen.addAll(found);
  }
  final ids = selected.map(idOf).toSet(), shared = <String, int>{};
  for (final task in allTasks.where((task) => !ids.contains(idOf(task)))) {
    final candidates = scriptCandidates(str(task['command']));
    for (final path in chosen) {
      // A bare ambiguous filename could still refer to this file: retain it.
      if (candidates.any(
        (name) =>
            name == path || !name.contains('/') && name == path.split('/').last,
      )) {
        shared[path] = (shared[path] ?? 0) + 1;
      }
    }
  }
  return TaskScriptPlan(
    {for (final path in chosen) path: files[path]!},
    shared,
    unresolved,
  );
}

class TaskDeleteResult {
  final List<String> removedScripts, retainedScripts;
  final Map<String, String> failedScripts;
  const TaskDeleteResult(
    this.removedScripts,
    this.retainedScripts,
    this.failedScripts,
  );
}

extension TaskDeletion on PanelModel {
  Future<TaskScriptPlan> prepareTaskDeletion(List<Json> selected) async {
    final scope = epoch;
    final data = await Future.wait([
      api('GET', '/crons'),
      api('GET', '/scripts'),
    ]);
    if (scope != epoch) throw ApiFailure('面板已切换，请重新选择任务');
    final ids = selected.map(idOf).toSet();
    final tasks = rows(data[0]);
    return taskScriptPlan(
      tasks.where((task) => ids.contains(idOf(task))).toList(),
      tasks,
      rows(data[1]),
    );
  }

  Future<TaskDeleteResult> deleteTasksAndScripts(
    List<Json> selected,
    Set<String> scriptPaths,
  ) async {
    final scope = epoch;
    void check() {
      if (scope != epoch) throw ApiFailure('面板已切换，已停止后续删除');
    }

    final plan = scriptPaths.isEmpty
        ? null
        : await prepareTaskDeletion(selected);
    check();
    await action('tasks', 'delete', selected);
    check();
    final removed = <String>[],
        retained = <String>[],
        failed = <String, String>{};
    if (plan != null) {
      List<Json> remaining;
      try {
        remaining = rows(await api('GET', '/crons'));
        check();
      } catch (_) {
        return TaskDeleteResult(removed, scriptPaths.toList(), {
          '脚本检查': '任务已删除，但无法确认剩余引用，脚本已保留',
        });
      }
      for (final path in scriptPaths) {
        check();
        final file = plan.files[path];
        final referenced = remaining.any(
          (task) => scriptCandidates(str(task['command'])).any(
            (name) =>
                name == path ||
                !name.contains('/') && name == path.split('/').last,
          ),
        );
        if (file == null || plan.shared.containsKey(path) || referenced) {
          retained.add(path);
          continue;
        }
        try {
          await api('DELETE', '/scripts', {
            'filename': file['title'],
            'path': str(file['parent']),
            'type': 'file',
          });
          check();
          removed.add(path);
        } catch (error) {
          check();
          failed[path] = '$error';
        }
      }
      if (removed.isNotEmpty) unawaited(load('scripts', force: true));
    }
    return TaskDeleteResult(removed, retained, failed);
  }
}

/// Keep successful file writes across task-creation retries. Never blindly
/// repeat a mutation whose network result is unknown.
class ScriptUploadSession {
  final PanelModel model;
  final int scope;
  final String content;
  String? uploadedSignature;
  bool uncertainTask = false;
  ScriptUploadSession(this.model, this.content) : scope = model.epoch;
  void checkScope() {
    if (model.epoch != scope) throw ApiFailure('面板已切换，请重新上传');
  }

  Future<void> submit(Json values) async {
    checkScope();
    final filename = str(values['filename']).trim(),
        path = str(values['path']).trim();
    if (!validFilename(filename) || !validDirectory(path)) {
      throw ApiFailure('文件名或目录无效');
    }
    final create = flag(values['createTask']);
    final task = {
      'name': str(values['name']).trim(),
      'command': str(values['command']).trim(),
      'schedule': str(values['schedule']).trim(),
    };
    if (create &&
        (task['name']!.isEmpty ||
            task['command']!.isEmpty ||
            !validCron(task['schedule']!))) {
      throw ApiFailure('请先填写任务名称、命令和有效的定时规则');
    }
    final signature = digest('$path/$filename\n$content');
    if (uploadedSignature != null && uploadedSignature != signature) {
      throw ApiFailure('脚本已上传；请保留文件名和目录后重试任务，或返回重新上传');
    }
    if (uncertainTask) throw ApiFailure('任务创建结果尚未确认。脚本已保留，请返回任务列表核对，避免重复创建。');
    if (uploadedSignature == null) {
      await model.load('scripts', force: true);
      checkScope();
      if (model.errors['scripts'] != null) {
        throw ApiFailure(model.errors['scripts']!);
      }
      final exists = flatten(model.cache['scripts'] ?? [])
          .any((r) => str(r['title']) == filename && str(r['parent']) == path);
      if (exists && !flag(values['overwrite'])) {
        throw ApiFailure('文件已存在，请更名或勾选允许覆盖');
      }
      await model.api(exists ? 'PUT' : 'POST', '/scripts', {
        'filename': filename,
        'path': path,
        'content': content,
      });
      checkScope();
      uploadedSignature = signature;
      unawaited(model.load('scripts', force: true));
    }
    if (!create) return;
    try {
      checkScope();
      await model.api('POST', '/crons', task);
      checkScope();
    } catch (e) {
      uncertainTask =
          e is! ApiFailure ||
          e.status == 0 ||
          e.status >= 500 ||
          e.status == 408;
      throw ApiFailure(
        uncertainTask
            ? '脚本已上传，任务创建结果未确认。请返回任务列表核对，避免重复创建。'
            : '脚本已上传，任务创建失败：$e。修正后可直接重试任务。',
      );
    }
    await model.load('tasks', force: true);
  }
}

class JdCookie {
  final String type, identity, cookie;
  const JdCookie(this.type, this.identity, this.cookie);
  static JdCookie parse(String input) {
    if (utf8.encode(input).length > 32768) throw ApiFailure('CK 文本超过 32 KiB');
    var text = input.trim().replaceFirst(
      RegExp(r'^Cookie\s*:\s*', caseSensitive: false),
      '',
    );
    final exported = RegExp(
      r'''^(?:export\s+)?JD_COOKIE\s*=\s*(['"])([\s\S]*)\1\s*;?$''',
    ).firstMatch(text);
    if (exported != null) text = exported[2]!;
    if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(text)) {
      throw ApiFailure('请一次粘贴一个账号的完整 Cookie');
    }
    final fields = <String, String>{};
    for (final part in text.split(';')) {
      final position = part.indexOf('=');
      if (position < 1) continue;
      final key = part.substring(0, position).trim(),
          value = part.substring(position + 1).trim();
      if (!['pt_key', 'pt_pin', 'pin', 'wskey'].contains(key)) continue;
      if (fields.containsKey(key) && fields[key] != value) {
        throw ApiFailure('检测到多个账号或冲突字段');
      }
      if (value.isEmpty || RegExp(r'''[\s'";&]''').hasMatch(value)) {
        throw ApiFailure('Cookie 字段格式不正确');
      }
      fields[key] = value;
    }
    String identity(String value) {
      try {
        return Uri.decodeComponent(value);
      } catch (_) {
        throw ApiFailure('账号编码无效');
      }
    }

    if (fields.containsKey('pt_key') &&
        fields.containsKey('pt_pin') &&
        !fields.containsKey('wskey')) {
      return JdCookie(
        '网页 CK · 来源未判定',
        identity(fields['pt_pin']!),
        'pt_key=${fields['pt_key']};pt_pin=${fields['pt_pin']};',
      );
    }
    if (fields.containsKey('wskey') &&
        fields.containsKey('pin') &&
        !fields.containsKey('pt_key')) {
      return JdCookie(
        'WSKEY',
        identity(fields['pin']!),
        'pin=${fields['pin']};wskey=${fields['wskey']};',
      );
    }
    throw ApiFailure('没有识别到完整的 pt_key + pt_pin 或 pin + wskey');
  }
}

List<String> commandWords(String source, {bool rejectOperators = false}) {
  final words = <String>[];
  var word = '', quote = '', escaped = false, started = false;
  for (final ch in source.split('')) {
    if (escaped) {
      word += ch;
      escaped = false;
      started = true;
      continue;
    }
    if (ch == r'\' && quote != "'") {
      escaped = true;
      started = true;
      continue;
    }
    if (quote.isNotEmpty) {
      if (ch == quote) {
        quote = '';
      } else {
        word += ch;
      }
      continue;
    }
    if (ch == '"' || ch == "'") {
      quote = ch;
      started = true;
      continue;
    }
    if (rejectOperators && RegExp(r'[;&|`<>\r\n()]').hasMatch(ch)) {
      throw ApiFailure('只支持单条 ql repo / raw 命令');
    }
    if (RegExp(r'\s').hasMatch(ch)) {
      if (started) {
        words.add(word);
        word = '';
        started = false;
      }
    } else {
      word += ch;
      started = true;
    }
  }
  if (quote.isNotEmpty || escaped) throw ApiFailure('命令引号不完整');
  if (started) words.add(word);
  return words;
}

Json? subscriptionCommand(String text) {
  if (!RegExp(r'^ql\s+(repo|raw)\b').hasMatch(text.trim())) return null;
  final words = commandWords(text.trim(), rejectOperators: true);
  if (words.length < 3 || words.length > (words[1] == 'raw' ? 3 : 8)) {
    throw ApiFailure('订阅命令参数不完整或过多');
  }
  final url = words[2];
  return {
    'type': words[1] == 'raw'
        ? 'file'
        : RegExp(r'^https?://').hasMatch(url)
        ? 'public-repo'
        : 'private-repo',
    'url': url,
    'name': (Uri.tryParse(url)?.pathSegments.lastOrNull ?? '订阅').replaceFirst(
      RegExp(r'\.git$'),
      '',
    ),
    for (var i = 3; i < words.length; i++)
      ['whitelist', 'blacklist', 'dependences', 'branch', 'extensions'][i - 3]:
          words[i],
  };
}

List<String> scriptCandidates(String command) {
  if (RegExp(r'[`\n\r]|\$\(').hasMatch(command)) return [];
  final List<String> tokens;
  try {
    tokens = commandWords(command);
  } catch (_) {
    return [];
  }
  final result = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    if (['-e', '-c', '-m', '--eval'].contains(tokens[i])) {
      i++;
      continue;
    }
    var value = tokens[i]
        .replaceFirst(RegExp(r'^/ql/(?:data/)?scripts/'), '')
        .replaceFirst(RegExp(r'^\./'), '');
    if (RegExp(
          r'\.(?:js|mjs|cjs|py|sh|ts|rb|go|lua)$',
          caseSensitive: false,
        ).hasMatch(value) &&
        !value.contains('..') &&
        !value.contains(r'$')) {
      result.add(value);
    }
  }
  return result.toSet().toList();
}

Json scriptMetadata(String filename, String content) {
  final first = content.split('\n').take(100).join('\n');
  final named = RegExp(r'new\s+Env\s*\(\s*[\x27\x22]([^\x27\x22]+)')
      .firstMatch(first);
  final schedule = RegExp(
    r'(?:cron|定时)\s*[:=：]\s*[\x27\x22]?([\d*/?,\-]+(?:[ \t]+[\d*/?,\-]+){4,5})',
    caseSensitive: false,
  ).firstMatch(first);
  return {
    'name': named?[1] ?? filename,
    'schedule': schedule?[1] ?? '',
    'command': scriptCommand(filename),
  };
}

bool validDirectory(String path) =>
    !path.startsWith('/') &&
    !RegExp(r'[\\\x00-\x1f\x7f]').hasMatch(path) &&
    !path.split('/').any((s) => s == '..' || s == '.');
String scriptCommand(String filename, [String path = '']) {
  if (!validFilename(filename) || !validDirectory(path)) {
    throw ApiFailure('脚本路径无效');
  }
  final full = [path, filename].where((s) => s.isNotEmpty).join('/');
  return 'task ${RegExp(r'^[a-zA-Z0-9_./-]+$').hasMatch(full) ? full : "'${full.replaceAll("'", "'\\''")}'"}';
}

bool validFilename(String name) =>
    name.trim().isNotEmpty &&
    name.length <= 200 &&
    name != '.' &&
    name != '..' &&
    !RegExp(r'[\\/\x00-\x1f\x7f]').hasMatch(name);
bool validCron(String value) {
  final parts = value.trim().split(RegExp(r'\s+'));
  if (parts.length != 5 && parts.length != 6) return false;
  final bounds = parts.length == 6
      ? [59, 59, 23, 31, 12, 7]
      : [59, 23, 31, 12, 7];
  for (var i = 0; i < parts.length; i++) {
    var field = parts[i].toUpperCase();
    final position = i + (parts.length == 5 ? 1 : 0);
    final names = position == 4
        ? [
            'JAN',
            'FEB',
            'MAR',
            'APR',
            'MAY',
            'JUN',
            'JUL',
            'AUG',
            'SEP',
            'OCT',
            'NOV',
            'DEC',
          ]
        : position == 5
        ? ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT']
        : <String>[];
    for (var j = 0; j < names.length; j++) {
      field = field.replaceAll(names[j], '${j + (position == 4 ? 1 : 0)}');
    }
    for (final item in field.split(',')) {
      final step = item.split('/');
      if (step.length > 2 ||
          (step.length == 2 && (int.tryParse(step[1]) ?? 0) <= 0)) {
        return false;
      }
      final base = step[0], minimum = position == 3 || position == 4 ? 1 : 0;
      if (base == '*') continue;
      if (base == '?' && (position == 3 || position == 5)) continue;
      if ((base == 'L' || base == 'LW') && position == 3 && step.length == 1) {
        continue;
      }
      if (RegExp(r'^\d+W$').hasMatch(base) &&
          position == 3 &&
          step.length == 1) {
        final n = int.parse(base.substring(0, base.length - 1));
        if (n < 1 || n > 31) return false;
        continue;
      }
      if (RegExp(r'^\d+L$').hasMatch(base) &&
          position == 5 &&
          step.length == 1) {
        if (int.parse(base.substring(0, base.length - 1)) > 7) return false;
        continue;
      }
      if (RegExp(r'^\d+#[1-5]$').hasMatch(base) &&
          position == 5 &&
          step.length == 1) {
        if (int.parse(base.split('#').first) > 7) return false;
        continue;
      }
      if (!RegExp(r'^\d+(?:-\d+)?$').hasMatch(base)) return false;
      final range = base.split('-').map(int.parse).toList();
      if (range.any((n) => n < minimum || n > bounds[i]) ||
          range.length == 2 && range[0] > range[1]) {
        return false;
      }
    }
  }
  return true;
}

class DemoPanel {
  DemoPanel() {
    // Keep fixture lists writable with the same JSON types as HTTP responses.
    for (final key in data.keys.toList()) {
      if (data[key] is List) data[key] = rows(data[key]);
    }
  }
  int next = 100;
  final Json data = {
    'crons': List.generate(
      24,
      (i) => {
        'id': i + 1,
        'name': ['每日数据备份', '服务健康检查', '消息通知汇总', '清理过期日志'][i % 4],
        'command':
            'task "${['backup.py', 'health.js', 'notice.py', 'cleanup.sh'][i % 4]}"',
        'schedule': '0 ${i % 24} * * *',
        'status': i == 1 ? 0 : 1,
        'isDisabled': i % 7 == 3 ? 1 : 0,
        'isPinned': i == 0 ? 1 : 0,
      },
    ),
    'envs': [
      {
        'id': 31,
        'name': 'JD_COOKIE',
        'value': 'pt_key=demo-only;pt_pin=example;',
        'remarks': '演示账号',
        'status': 0,
      },
      {
        'id': 32,
        'name': 'BACKUP_KEEP_DAYS',
        'value': '7',
        'remarks': '备份保留天数',
        'status': 0,
      },
      {
        'id': 33,
        'name': 'NOTIFY_TOKEN',
        'value': 'demo-token',
        'remarks': '通知令牌',
        'status': 1,
      },
    ],
    'subscriptions': [
      {
        'id': 41,
        'name': '维护脚本',
        'type': 'public-repo',
        'url': 'https://github.com/example/scripts.git',
        'alias': 'example_scripts',
        'schedule_type': 'crontab',
        'schedule': '0 1 * * *',
        'status': 1,
        'autoAddCron': true,
        'autoDelCron': true,
      },
    ],
    'scripts': [
      {'title': 'backup.py', 'parent': '', 'type': 'file'},
      {'title': 'health.js', 'parent': '', 'type': 'file'},
      {'title': 'notice.py', 'parent': '', 'type': 'file'},
      {'title': 'cleanup.sh', 'parent': '', 'type': 'file'},
    ],
    'configs': [
      {'title': 'config.sh', 'value': 'config.sh'},
    ],
    'logs': [
      {'title': 'demo.log', 'parent': '', 'type': 'file'},
    ],
    'dependencies': [
      {
        'id': 51,
        'name': 'requests',
        'type': 1,
        'status': 1,
        'remark': 'HTTP 请求',
      },
      {'id': 52, 'name': 'axios', 'type': 0, 'status': 1},
    ],
    'apps': [
      {
        'id': 61,
        'name': '示例应用',
        'client_id': 'demo-client',
        'client_secret': 'demo-only',
        'scopes': ['crons', 'envs'],
      },
    ],
  };
  final Map<String, String> content = {
    'backup.py': '# cron: 0 2 * * *\nfrom datetime import datetime\n\nprint("Backup started", datetime.now())\n',
    'health.js':
        '// cron: */15 * * * *\nconsole.log("All systems operational");\n',
    'config.sh': 'export BACKUP_KEEP_DAYS=7\n',
  };
  String log = '[10:00:00] 开始执行任务\n[10:00:01] 加载配置\n[10:00:02] 正在处理数据…\n';
  Json notification = {'type': ''};
  final Json systemConfig = {
    'timezone': 'Asia/Shanghai',
    'dependenceProxy': '',
    'nodeMirror': '',
    'pythonMirror': '',
    'linuxMirror': '',
    'logRemoveFrequency': 7,
  };
  Future<dynamic> request(String method, String path, dynamic body) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final uri = Uri.parse('https://demo.local$path'),
        parts = Uri.parse(path).pathSegments;
    final resource = parts.first, operation = parts.length > 1 ? parts[1] : '';
    if (resource == 'system') {
      if (operation == 'config' && method == 'PUT') {
        if (parts.last == 'dependence-clean') {
          final type = body['type'] == 'node'
              ? 0
              : body['type'] == 'python3'
              ? 1
              : -1;
          if (type < 0) throw ApiFailure('不支持该缓存类型', 400);
          for (final row in data['dependencies'] as List) {
            if (dependencyType(Map<String, dynamic>.from(row)) == type &&
                row['status'] == 1) {
              row['status'] = 2;
            }
          }
        } else {
          systemConfig.addAll(Map<String, dynamic>.from(body));
        }
        return null;
      }
      return operation == 'config'
          ? {
              'info': {...systemConfig},
            }
          : {'version': '2.23.0', 'branch': 'master'};
    }
    if (resource == 'dashboard') {
      return operation == 'overview'
          ? {
              'todayRuns': 48,
              'todaySuccess': 45,
              'todayFail': 3,
              'successRate': 93.8,
              'avgTime': 18300,
            }
          : operation == 'system'
          ? {
              'platform': 'linux',
              'cpus': 2,
              'uptime': 221700,
              'memUsagePercent': 40,
              'loadAvg': [.15, .21, .18],
            }
          : List.generate(
              7,
              (i) => {
                'date': '10-${16 + i}',
                'success': 24 + i * 3,
                'fail': i % 3,
              },
            );
    }
    if (resource == 'user') {
      if (operation == 'login-log') {
        return [
          {
            'timestamp': DateTime.utc(
              2026,
              10,
              26,
              7,
              0,
            ).millisecondsSinceEpoch,
            'status': 0,
            'ip': '192.0.2.10',
            'address': '示例位置',
            'platform': 'desktop',
          },
          {
            'timestamp': DateTime.utc(
              2026,
              10,
              26,
              6,
              30,
            ).millisecondsSinceEpoch,
            'status': 1,
            'ip': '198.51.100.8',
            'address': '示例位置',
            'platform': 'mobile',
          },
        ];
      }
      if (operation == 'notification') {
        if (method != 'GET') notification = Map<String, dynamic>.from(body);
        return notification;
      }
      return [];
    }
    if (resource == 'scripts' && operation == 'history') {
      final filename = uri.queryParameters['filename'] ?? '',
          current = content[filename] ?? '';
      const historical = '# 历史版本\nprint("previous version")\n';
      if (parts.length == 2) {
        return {
          'currentHash': digest(current),
          'versions': [
            {
              'id': '00000000-0000-4000-8000-000000000001',
              'hash': digest(historical),
              'createdAt': '2026-10-20T12:00:00Z',
              'size': utf8.encode(historical).length,
            },
          ],
        };
      }
      if (parts.last == 'detail') {
        return {
          'current': current,
          'currentHash': digest(current),
          'version': {
            'id': '00000000-0000-4000-8000-000000000001',
            'content': historical,
            'hash': digest(historical),
          },
        };
      }
      if (body['expectedHash'] != digest(content[body['filename']] ?? '')) {
        throw ApiFailure('文件已变化', 409);
      }
      content[body['filename']] = historical;
      return null;
    }
    if (operation == 'detail') {
      if (resource == 'logs') {
        log += '[10:00:${log.split('\n').length}] 演示日志更新\n';
        return log;
      }
      return content[[
            uri.queryParameters['path'],
            uri.queryParameters['file'],
          ].where((v) => v != null && v.isNotEmpty).join('/')] ??
          content[uri.queryParameters['path']] ??
          '';
    }
    if (parts.last == 'log') {
      log += '运行中的演示输出\n';
      return log;
    }
    if (resource == 'crons' && parts.last == 'logs') {
      return [
        {
          'filename': '2026-10-23-070000.log',
          'directory': 'demo-task',
          'time': 1792710000000,
        },
        {
          'filename': '2026-10-22-070000.log',
          'directory': 'demo-task',
          'time': 1792623600000,
        },
      ];
    }
    if (resource == 'envs' && parts.last == 'move') {
      final list = data['envs'] as List;
      final index = list.indexWhere((r) => str(r['id']) == operation);
      if (index >= 0) list.insert(body['toIndex'], list.removeAt(index));
      return null;
    }
    final list = data[resource] as List?;
    if (list == null) throw ApiFailure('演示未提供该接口', 404);
    if (method == 'GET') {
      if (resource == 'dependencies' && operation.isNotEmpty) {
        return {
          'log': ['示例安装成功'],
        };
      }
      final result = rows(jsonDecode(jsonEncode(list)));
      if (['crons', 'envs'].contains(resource)) {
        for (final row in result) {
          row.putIfAbsent('createdAt', () => '2026-10-20T00:00:00Z');
          row.putIfAbsent('updatedAt', () => '2026-10-23T02:30:00Z');
        }
      }
      return result;
    }
    if (resource == 'scripts' || resource == 'configs' || resource == 'logs') {
      final name = body['filename'] ?? body['name'] ?? '',
          key = [
            body['path'],
            name,
          ].where((v) => v != null && v.isNotEmpty).join('/');
      if (method == 'DELETE') {
        list.removeWhere(
          (r) => r['title'] == name && str(r['parent']) == str(body['path']),
        );
        if (body['type'] == 'directory') {
          content.removeWhere(
            (name, _) => name == key || name.startsWith('$key/'),
          );
        } else {
          content.remove(key);
        }
        return null;
      }
      if (operation == 'rename') {
        for (final r in list) {
          if (r['title'] == name) r['title'] = body['newFilename'];
        }
        content[body['newFilename']] = content.remove(key) ?? '';
        return null;
      }
      if (method == 'POST' &&
          resource == 'scripts' &&
          list.any((r) => filePath(Map<String, dynamic>.from(r)) == key)) {
        throw ApiFailure('文件已存在');
      }
      content[key] = str(body['content']);
      if (!list.any((r) => r['title'] == name)) {
        list.add({
          'title': name,
          'parent': body['path'] ?? '',
          'type': body['directory'] != null ? 'directory' : 'file',
          'value': name,
        });
      }
      return null;
    }
    if (parts.last == 'reset-secret') {
      for (final r in list) {
        if (str(r['id']) == operation) {
          r['client_secret'] = 'demo-reset-${next++}';
        }
      }
      return null;
    }
    if (body is List && (method == 'DELETE' || operation.isNotEmpty)) {
      final ids = body.map(str).toSet();
      if (method == 'DELETE') {
        list.removeWhere((r) => ids.contains(str(r['id'])));
      } else {
        for (final r in list) {
          if (!ids.contains(str(r['id']))) continue;
          if (operation == 'run') r['status'] = 0;
          if (operation == 'stop') r['status'] = 1;
          if (resource == 'dependencies' &&
              ['reinstall', 'cancel'].contains(operation)) {
            r['status'] = operation == 'reinstall' ? 6 : 7;
          }
          if (['enable', 'disable'].contains(operation)) {
            if (resource == 'envs') {
              r['status'] = operation == 'disable' ? 1 : 0;
            } else {
              r['isDisabled'] = operation == 'disable' ? 1 : 0;
            }
          }
          if (['pin', 'unpin'].contains(operation)) {
            r['isPinned'] = operation == 'pin' ? 1 : 0;
          }
        }
      }
      return null;
    }
    for (final value in body is List ? body : [body]) {
      final row = Map<String, dynamic>.from(value);
      if (method == 'PUT') {
        final index = list.indexWhere((r) => str(r['id']) == idOf(row));
        if (index >= 0) {
          list[index] = <String, dynamic>{
            ...Map<String, dynamic>.from(list[index]),
            ...row,
          };
        }
      } else {
        row['id'] = next++;
        row.putIfAbsent('status', () => 1);
        list.add(row);
      }
    }
    return null;
  }
}
