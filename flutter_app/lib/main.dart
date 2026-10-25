import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show LicenseRegistry, LicenseEntryWithLineBreaks, setEquals;
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core.dart';
import 'reference_ui/navigation_dock.dart' as fc;
import 'reference_ui/liquid_glass.dart' as fcg;
import 'reference_ui/icons/icons.dart' as fci;
import 'reference_ui/tab_pages.dart' as fct;
part 'pages.dart';
part 'editor.dart';
part 'advanced.dart';
part 'replica.dart';
part 'details.dart';
part 'origin.dart';
part 'task_delete.dart';
part 'app_info.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final name in [
      'editor-LICENSE.txt',
      'qinglong-LICENSE.txt',
      'THIRD-PARTY-NOTICES.txt',
      'flclash-LICENSE.txt',
    ]) {
      yield LicenseEntryWithLineBreaks([
        '青龙掌控 · 组件许可',
      ], await rootBundle.loadString('assets/$name'));
    }
  });
  runApp(QinglongApp(model: PanelModel()));
}

const accent = Color(0xff007aff),
    ink = Color(0xff1c2028),
    warm = Color(0xffad4938);

class QinglongApp extends StatefulWidget {
  final PanelModel model;
  const QinglongApp({super.key, required this.model});
  @override
  State<QinglongApp> createState() => _QinglongAppState();
}

class _QinglongAppState extends State<QinglongApp> {
  late final ValueNotifier<(bool, double)> appearance;
  void appearanceChanged() =>
      appearance.value = (widget.model.dark, widget.model.textScale);
  @override
  void initState() {
    super.initState();
    appearance = ValueNotifier((widget.model.dark, widget.model.textScale));
    widget.model.addListener(appearanceChanged);
    unawaited(widget.model.initialize());
  }

  @override
  void didUpdateWidget(covariant QinglongApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model) {
      oldWidget.model.removeListener(appearanceChanged);
      widget.model.addListener(appearanceChanged);
      appearanceChanged();
      unawaited(widget.model.initialize());
    }
  }

  @override
  void dispose() {
    widget.model.removeListener(appearanceChanged);
    appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: appearance,
    builder: (context, _) {
      final dark = widget.model.dark;
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: '青龙掌控',
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? [const Color(0xff141416), const Color(0xff141416)]
                  : [const Color(0xffefedf0), const Color(0xffefedf0)],
            ),
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(
                (MediaQuery.textScalerOf(context).scale(1) *
                        widget.model.textScale)
                    .clamp(.9, 1.6),
              ),
            ),
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value:
                  (dark
                          ? SystemUiOverlayStyle.light
                          : SystemUiOverlayStyle.dark)
                      .copyWith(
                        statusBarColor: Colors.transparent,
                        systemNavigationBarColor: dark
                            ? const Color(0xff141416)
                            : const Color(0xffefedf0),
                      ),
              child: fcg.LiquidGlassScope(
                enabled: true,
                child: fcg.LiquidGlassHost(enabled: true, child: child!),
              ),
            ),
          ),
        ),
        theme: ThemeData(
          useMaterial3: true,
          brightness: dark ? Brightness.dark : Brightness.light,
          colorScheme:
              ColorScheme.fromSeed(
                seedColor: accent,
                brightness: dark ? Brightness.dark : Brightness.light,
              ).copyWith(
                primary: dark ? const Color(0xff74b4ff) : accent,
                onPrimary: dark ? const Color(0xff082b52) : Colors.white,
                surface: dark
                    ? const Color(0xff141416)
                    : const Color(0xfffcf9fb),
                surfaceContainer: dark
                    ? const Color(0xff252527)
                    : const Color(0xffefedf0),
                surfaceContainerHigh: dark
                    ? const Color(0xff303034)
                    : const Color(0xffe9e7ec),
                surfaceContainerLow: dark
                    ? const Color(0xff1d1d20)
                    : const Color(0xfff4f2f5),
                surfaceBright: dark
                    ? const Color(0xff3b3b40)
                    : const Color(0xfffcf9fb),
                surfaceContainerHighest: dark
                    ? const Color(0xff38383c)
                    : const Color(0xffe4e2e6),
                onSurface: dark ? const Color(0xfff2f1f5) : ink,
                onSurfaceVariant: dark
                    ? const Color(0xffbfc1cb)
                    : const Color(0xff626673),
              ),
          scaffoldBackgroundColor: Colors.transparent,
          appBarTheme: AppBarTheme(
            systemOverlayStyle:
                (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
                    .copyWith(
                      statusBarColor: Colors.transparent,
                      systemNavigationBarColor: dark
                          ? const Color(0xff141416)
                          : const Color(0xffefedf0),
                    ),
            backgroundColor: Colors.transparent,
            scrolledUnderElevation: 0,
            elevation: 0,
            toolbarHeight: 52,
            centerTitle: false,
            titleTextStyle: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: dark ? const Color(0xfff2f1f5) : ink,
            ),
          ),
          textTheme: const TextTheme(
            titleMedium: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
            bodyMedium: TextStyle(fontSize: 14, height: 1.45),
            bodySmall: TextStyle(fontSize: 12, height: 1.4),
          ),
          inputDecorationTheme: InputDecorationTheme(
            isDense: true,
            filled: true,
            fillColor: dark ? const Color(0xff333337) : const Color(0xffe9e7ec),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 13,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size(44, 42),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(44, 40),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              minimumSize: const Size(40, 36),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          bottomSheetTheme: BottomSheetThemeData(
            backgroundColor: dark
                ? const Color(0xff252527)
                : const Color(0xfffcf9fb),
            modalBackgroundColor: dark
                ? const Color(0xff252527)
                : const Color(0xfffcf9fb),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            clipBehavior: Clip.antiAlias,
            dragHandleColor: dark
                ? const Color(0xff666873)
                : const Color(0xffc3c3cd),
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: dark
                ? const Color(0xff252527)
                : const Color(0xfffcf9fb),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
          dividerTheme: DividerThemeData(
            color: dark ? const Color(0xff3b3b43) : const Color(0xffe2dfe5),
            thickness: .6,
          ),
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
            },
          ),
        ),
        home: Home(key: ObjectKey(widget.model), model: widget.model),
      );
    },
  );
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final bool pinned;
  final EdgeInsets padding;
  const GlassCard({
    super.key,
    required this.child,
    this.pinned = false,
    this.padding = const EdgeInsets.all(13),
  });
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: padding,
      decoration: BoxDecoration(
        color: pinned
            ? (dark ? const Color(0xff273b58) : const Color(0xffe0e9fc))
            : (dark ? const Color(0xff252527) : const Color(0xfffcf9fb)),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: .025)
              : const Color(0xff454954).withValues(alpha: .035),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0 : .018),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Material(color: Colors.transparent, child: child),
    );
  }
}

class StateBadge extends StatefulWidget {
  final String text;
  final Color color;
  final bool animate;
  const StateBadge(
    this.text, {
    super.key,
    this.color = accent,
    this.animate = false,
  });
  @override
  State<StateBadge> createState() => _StateBadgeState();
}

class _StateBadgeState extends State<StateBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotion();
  }

  @override
  void didUpdateWidget(StateBadge old) {
    super.didUpdateWidget(old);
    syncMotion();
  }

  void syncMotion() {
    final enabled =
        widget.animate &&
        TickerMode.valuesOf(context).enabled &&
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    if (enabled && !controller.isAnimating) controller.repeat();
    if (!enabled) controller.stop();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).brightness == Brightness.dark
        ? Color.lerp(widget.color, Colors.white, .40)!
        : widget.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.animate)
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: RepaintBoundary(
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CustomPaint(painter: _RunningBars(controller, color)),
                ),
              ),
            ),
          if (!widget.animate)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                widget.text.contains('禁用') || widget.text.contains('取消')
                    ? Icons.block
                    : widget.text.contains('失败')
                    ? Icons.error_outline
                    : widget.text.contains('排队') || widget.text.contains('等待')
                    ? Icons.schedule
                    : Icons.check,
                size: 12,
                color: color,
              ),
            ),
          Text(
            widget.text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _RunningBars extends CustomPainter {
  final Animation<double> phase;
  final Color color;
  _RunningBars(this.phase, this.color) : super(repaint: phase);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var i = 0; i < 3; i++) {
      final height = 7 + 4 * math.sin(phase.value * math.pi * 2 - i * 1.05);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * 4.5, (size.height - height) / 2, 2.2, height),
          const Radius.circular(1.1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RunningBars old) =>
      old.color != color || old.phase != phase;
}

Widget actionButton(
  String text,
  IconData icon,
  VoidCallback? onTap, {
  bool primary = false,
}) => primary
    ? FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
      )
    : OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
      );
void showError(BuildContext context, Object error) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$error'), behavior: SnackBarBehavior.floating),
    );
  }
}

Future<T?> guard<T>(BuildContext context, Future<T> Function() action) async {
  if (!context.mounted) return null;
  try {
    return await action();
  } catch (e) {
    showError(context, e);
    return null;
  }
}

Future<bool> confirm(BuildContext context, String title, String text) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('确认'),
          ),
        ],
      ),
    ) ??
    false;
Future<String?> choose(
  BuildContext context,
  String title,
  Map<String, String> options,
) => showModalBottomSheet<String>(
  context: context,
  backgroundColor: Colors.transparent,
  isScrollControlled: true,
  showDragHandle: false,
  builder: (c) => SafeArea(
    child: Container(
      margin: const EdgeInsets.all(10),
      padding: const EdgeInsets.all(10),
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .74),
      decoration: BoxDecoration(
        color: _surface(c),
        border: Border.all(color: _line(c)),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .15),
            blurRadius: 40,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 4,
            margin: const EdgeInsets.only(top: 2, bottom: 6),
            decoration: BoxDecoration(
              color: Theme.of(c).colorScheme.onSurfaceVariant
                  .withValues(alpha: .3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.pop(c),
                icon: const Icon(Icons.close, size: 19),
              ),
            ],
          ),
          Divider(height: 1, color: _line(c)),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: options.entries.where((e) => e.key != 'delete').map((
                e,
              ) {
                final danger = e.key == 'delete' || e.key == 'logout';
                final color = danger ? const Color(0xffb44d46) : _primary(c);
                final icon = switch (e.key) {
                  'edit' => Icons.edit_outlined,
                  'local' => Icons.phone_android_outlined,
                  'remote' => Icons.link,
                  'clipboard' => Icons.content_paste,
                  'delete' => Icons.delete_outline,
                  'log' => Icons.description_outlined,
                  'pin' => Icons.push_pin_outlined,
                  'toggle' => Icons.power_settings_new,
                  'copy' => Icons.copy_outlined,
                  'copy-task' => Icons.copy_all_outlined,
                  'copy-id' => Icons.badge_outlined,
                  'details' => Icons.info_outline_rounded,
                  'move' => Icons.swap_vert,
                  'export' => Icons.file_download_outlined,
                  'import' => Icons.file_upload_outlined,
                  'sync' => Icons.sync,
                  'jd' => Icons.cookie_outlined,
                  'history' => Icons.history,
                  'rename' => Icons.drive_file_rename_outline,
                  'reset' => Icons.restart_alt,
                  'password' => Icons.password,
                  'logout' => Icons.logout,
                  'task' => Icons.add_task,
                  'folder' => Icons.create_new_folder_outlined,
                  'script' => Icons.code,
                  _ => Icons.radio_button_unchecked,
                };
                return Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 9),
                    minTileHeight: 48,
                    leading: Container(
                      width: 31,
                      height: 31,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(icon, size: 18, color: color),
                    ),
                    title: Text(
                      e.value,
                      style: TextStyle(
                        fontSize: 13,
                        color: danger ? color : null,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      size: 15,
                      color: Theme.of(c).colorScheme.onSurfaceVariant,
                    ),
                    onTap: () => Navigator.pop(c, e.key),
                  ),
                );
              }).toList(),
            ),
          ),
          if (options.containsKey('delete')) ...[
            Divider(height: 1, color: _line(c)),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(c).colorScheme.error,
                  minimumSize: const Size(44, 42),
                ),
                onPressed: () => Navigator.pop(c, 'delete'),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(
                  options['delete']!,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('取消', style: TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    ),
  ),
);

class Field {
  final String key, label, help;
  final bool required, secret, multiline, toggle, readOnly, multiple;
  final Map<String, String>? options, presets;
  final bool Function(Json)? visible;
  final void Function(Json)? changed;
  const Field(
    this.key,
    this.label, {
    this.help = '',
    this.required = false,
    this.secret = false,
    this.multiline = false,
    this.toggle = false,
    this.readOnly = false,
    this.multiple = false,
    this.options,
    this.presets,
    this.visible,
    this.changed,
  });
}

class FormPage extends StatefulWidget {
  final String title, submit;
  final Json initial;
  final List<Field> fields;
  final Future<void> Function(Json) save;
  const FormPage({
    super.key,
    required this.title,
    required this.fields,
    required this.save,
    this.initial = const {},
    this.submit = '保存',
  });
  @override
  State<FormPage> createState() => _FormPageState();
}

class _FormPageState extends State<FormPage> {
  final form = GlobalKey<FormState>();
  late Json values = {...widget.initial};
  late final Json original = {
    for (final field in widget.fields)
      field.key: _initialFieldValue(field, widget.initial[field.key]),
  };
  late final controllers = {
    for (final f in widget.fields)
      if (!f.toggle && !f.multiple)
        f.key: TextEditingController(text: str(values[f.key])),
  };
  bool busy = false;
  String? error;

  dynamic _initialFieldValue(Field field, dynamic value) {
    if (field.toggle) return flag(value);
    if (field.multiple) {
      return (value as List? ?? const []).map(str).toSet();
    }
    return str(value);
  }

  dynamic _currentFieldValue(Field field) =>
      _initialFieldValue(field, values[field.key]);

  bool get hasChanges => widget.fields.any((field) {
    final current = _currentFieldValue(field);
    final initial = original[field.key];
    return current is Set && initial is Set
        ? !setEquals(current, initial)
        : current != initial;
  });
  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.save({...values});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy && !hasChanges,
    onPopInvokedWithResult: (didPop, result) async {
      if (!didPop &&
          !busy &&
          hasChanges &&
          await confirm(context, '放弃修改？', '尚未保存的内容将丢失。') &&
          context.mounted) {
        Navigator.pop(context);
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
      ),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (error != null)
              GlassCard(
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
            ...widget.fields.where((f) => f.visible?.call(values) ?? true).map((
              f,
            ) {
              void changed(dynamic value) {
                setState(() {
                  values[f.key] = value;
                  f.changed?.call(values);
                  if (f.changed != null &&
                      controllers.containsKey(f.key) &&
                      controllers[f.key]!.text != str(values[f.key])) {
                    controllers[f.key]!.text = str(values[f.key]);
                  }
                  for (final e in controllers.entries) {
                    if (e.key != f.key && e.value.text != str(values[e.key])) {
                      e.value.text = str(values[e.key]);
                    }
                  }
                });
              }

              if (f.toggle) {
                return SwitchListTile.adaptive(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 3),
                  title: Text(f.label),
                  subtitle: f.help.isEmpty ? null : Text(f.help),
                  value: flag(values[f.key]),
                  onChanged: busy ? null : changed,
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 17),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${f.required ? '* ' : ''}${f.label}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 7),
                    if (f.multiple)
                      FormField<List<String>>(
                        initialValue: List<String>.from(
                          values[f.key] as List? ?? [],
                        ),
                        validator: (value) =>
                            f.required && (value?.isEmpty ?? true)
                            ? '请至少勾选一项${f.label}'
                            : null,
                        builder: (field) {
                          final chosen = field.value ?? <String>[];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Material(
                                color: _surface(context),
                                clipBehavior: Clip.antiAlias,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: field.hasError
                                        ? Theme.of(context).colorScheme.error
                                        : _line(context),
                                  ),
                                ),
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final columns =
                                        constraints.maxWidth >= 300 &&
                                            MediaQuery.textScalerOf(context)
                                                    .scale(13) <=
                                                16
                                        ? 2
                                        : 1;
                                    return Wrap(
                                      children: [
                                        for (final entry in f.options!.entries)
                                          SizedBox(
                                            width:
                                                constraints.maxWidth / columns,
                                            child: CheckboxListTile(
                                              key: ValueKey(
                                                'scope-${entry.key}',
                                              ),
                                              value: chosen.contains(entry.key),
                                              controlAffinity:
                                                  ListTileControlAffinity
                                                      .leading,
                                              dense: true,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                  ),
                                              title: Text(
                                                entry.value,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                ),
                                              ),
                                              onChanged: busy
                                                  ? null
                                                  : (checked) {
                                                      FocusScope.of(context)
                                                          .unfocus();
                                                      final next = [
                                                        ...?field.value,
                                                      ];
                                                      if (checked == true) {
                                                        next.add(entry.key);
                                                      } else {
                                                        next.remove(entry.key);
                                                      }
                                                      field.didChange(next);
                                                      changed(next);
                                                    },
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                field.errorText ?? '已选择 ${chosen.length} 项权限',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: field.hasError
                                      ? Theme.of(context).colorScheme.error
                                      : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                ),
                              ),
                            ],
                          );
                        },
                      )
                    else if (f.options != null)
                      DropdownButtonFormField<String>(
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        dropdownColor: _surface(context),
                        initialValue: f.options!.containsKey(str(values[f.key]))
                            ? str(values[f.key])
                            : null,
                        isExpanded: true,
                        items: f.options!.entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ),
                            )
                            .toList(),
                        onChanged: busy ? null : changed,
                        validator: (v) => f.required && (v ?? '').isEmpty
                            ? '请选择${f.label}'
                            : null,
                      )
                    else
                      TextFormField(
                        style: const TextStyle(fontSize: 13),
                        controller: controllers[f.key],
                        obscureText: f.secret,
                        readOnly: f.readOnly,
                        enabled: !busy,
                        maxLines: f.secret
                            ? 1
                            : f.multiline
                            ? 6
                            : 1,
                        minLines: f.multiline ? 2 : 1,
                        onChanged: changed,
                        autocorrect: false,
                        enableSuggestions: !f.secret,
                        validator: (v) => f.required && (v ?? '').trim().isEmpty
                            ? '请填写${f.label}'
                            : null,
                      ),
                    if (f.help.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          f.help,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    if (f.presets != null) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          for (final entry in f.presets!.entries)
                            ChoiceChip(
                              key: ValueKey('preset-${f.key}-${entry.value}'),
                              label: Text(
                                entry.key,
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected:
                                  str(values[f.key]).trim() == entry.value,
                              tooltip: entry.value,
                              visualDensity: VisualDensity.compact,
                              onSelected: busy || f.readOnly
                                  ? null
                                  : (_) {
                                      FocusScope.of(context).unfocus();
                                      controllers[f.key]!.value =
                                          TextEditingValue(
                                            text: entry.value,
                                            selection: TextSelection.collapsed(
                                              offset: entry.value.length,
                                            ),
                                          );
                                      changed(entry.value);
                                    },
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: _surface(context),
            border: Border(top: BorderSide(color: _line(context))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _compactButton(
                context,
                '取消',
                Icons.close,
                busy ? null : () => Navigator.maybePop(context),
              ),
              const SizedBox(width: 8),
              _compactButton(
                context,
                busy ? '处理中…' : widget.submit,
                Icons.check,
                busy ? null : submit,
                primary: true,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class Home extends StatefulWidget {
  final PanelModel model;
  const Home({super.key, required this.model});
  @override
  State<Home> createState() => HomeState();
}

class HomeState extends State<Home> with WidgetsBindingObserver {
  int? bodyEpoch;
  List<Widget> retainedPages = [];
  Object? homeSnapshot;
  void modelChanged() {
    final next = (
      m.initialized,
      m.startupError,
      m.page,
      m.epoch,
      m.demo,
      m.nativeDock,
      m.dark,
      m.textScale,
      m.activeId,
      m.dockRequest,
    );
    if (next != homeSnapshot) {
      homeSnapshot = next;
      if (mounted) setState(() {});
      syncDock();
    } else {
      sampleDock();
    }
  }

  PanelModel get m => widget.model;
  final pages = ['tasks', 'envs', 'scripts', 'more'];
  int depth = 0;
  bool keyboard = false;
  bool showDemoNotice = true;
  Timer? poll, sample;
  int dockFrame = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    m.addListener(modelChanged);
    Native.channel.setMethodCallHandler((call) async {
      if (call.method == 'dockNavigate') {
        m.dockRequest = (call.arguments['request'] as num).toInt();
        m.navigate(str(call.arguments['page']));
      }
    });
    poll = Timer.periodic(const Duration(seconds: 4), (_) => pollTasks());
  }

  @override
  void dispose() {
    m.removeListener(modelChanged);
    WidgetsBinding.instance.removeObserver(this);
    poll?.cancel();
    sample?.cancel();
    Native.channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      syncDock();
      pollTasks();
    }
  }

  bool polling = false;
  Future<void> pollTasks() async {
    if (polling ||
        !m.initialized ||
        m.startupError != null ||
        m.page != 'tasks' ||
        depth > 0 ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    polling = true;
    final scope = m.epoch;
    try {
      final fresh = rows(await m.api('GET', '/crons'));
      if (scope == m.epoch) {
        final old = m.cache['tasks'];
        if (old != null) {
          final indexed = {for (final r in fresh) idOf(r): r};
          for (final row in old) {
            final next = indexed[idOf(row)];
            if (next != null) {
              for (final key in [
                'status',
                'isDisabled',
                'isPinned',
                'last_execution_time',
                'last_running_time',
              ]) {
                if (next.containsKey(key)) row[key] = next[key];
              }
            }
          }
          m.changed();
          final now = DateTime.now().millisecondsSinceEpoch;
          if (old.any(
            (row) =>
                !disabled(row) &&
                (!m.forecasts.containsKey(idOf(row)) ||
                    (num.tryParse(str(m.forecasts[idOf(row)]?['next'])) ??
                            double.infinity) <=
                        now),
          )) {
            unawaited(m.forecastTasks());
          }
        }
      }
    } catch (_) {
    } finally {
      polling = false;
    }
  }

  void syncDock() {
    if (!mounted) return;
    if (!m.nativeDock || !m.initialized) return;
    unawaited(
      m.native
          .call('dockState', {
            'document': 'flutter-${identityHashCode(this)}',
            'page': m.page,
            'visible': false,
            'dark': m.dark,
            'request': m.dockRequest,
            'reduced': MediaQuery.maybeOf(context)?.disableAnimations ?? false,
          })
          .catchError((_) => null),
    );
  }

  void sampleDock() {} // Flutter glass captures the current composited frame.

  Future<T?> route<T>(Widget page) async {
    if (!mounted) return null;
    depth++;
    syncDock();
    try {
      final origin = Zone.current[_routeOriginKey];
      if (origin is _RouteOrigin && !MediaQuery.disableAnimationsOf(context)) {
        return await origin.open<T>(context, page);
      }
      return await Navigator.push<T>(
        context,
        MaterialPageRoute(builder: (_) => page),
      );
    } finally {
      depth--;
      syncDock();
      sampleDock();
    }
  }

  Future<T> overlay<T>(Future<T> Function() action) async {
    if (!mounted) throw ApiFailure('页面已关闭');
    depth++;
    syncDock();
    try {
      return await action();
    } finally {
      depth--;
      syncDock();
      sampleDock();
    }
  }

  Future<bool?> form(
    String title,
    List<Field> fields,
    Json initial,
    Future<void> Function(Json) save, {
    String submit = '保存',
  }) => route<bool>(
    FormPage(
      title: title,
      fields: fields,
      initial: initial,
      save: save,
      submit: submit,
    ),
  );
  Future<void> newRow(String key, [Json? row]) async {
    if (key == 'tasks') {
      await taskForm(row);
    }
    if (key == 'envs') {
      await envForm(row);
    }
    if (key == 'subscriptions') {
      await subscriptionForm(row);
    }
    if (key == 'dependencies') {
      await dependencyForm();
    }
    if (key == 'applications') {
      await applicationForm(row);
    }
    if (['scripts', 'configs'].contains(key)) {
      final selected = key == 'scripts'
          ? await overlay(
              () => choose(context, '新建', {'script': '脚本文件', 'folder': '文件夹'}),
            )
          : 'script';
      if (selected == null) return;
      await form(
        selected == 'folder' ? '新建文件夹' : '新建${key == 'configs' ? '配置' : '脚本'}',
        [
          const Field('filename', '文件名', required: true),
          if (key == 'scripts') const Field('path', '目标目录（留空为根目录）'),
        ],
        {'path': m.views['scriptsDir'] ?? ''},
        (v) async {
          if (!validFilename(v['filename'])) throw ApiFailure('文件名无效');
          if (!validDirectory(str(v['path']))) throw ApiFailure('目标目录无效');
          if (selected == 'folder') {
            await m.api('POST', '/scripts', {
              'filename': v['filename'],
              'directory': v['filename'],
              'path': v['path'],
              'content': '',
            });
          } else {
            await m.api(
              'POST',
              key == 'scripts' ? '/scripts' : '/configs/save',
              key == 'scripts'
                  ? {
                      'filename': v['filename'],
                      'path': v['path'],
                      'content': '',
                    }
                  : {'name': v['filename'], 'content': ''},
            );
          }
          await m.load(key, force: true);
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final nextKeyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (keyboard != nextKeyboard) {
      keyboard = nextKeyboard;
      WidgetsBinding.instance.addPostFrameCallback((_) => syncDock());
    }
    if (!m.initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (m.startupError != null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(m.startupError!),
                const SizedBox(height: 16),
                actionButton('重试', Icons.refresh, () => m.initialize()),
              ],
            ),
          ),
        ),
      );
    }
    final index = pages.indexOf(m.page).clamp(0, 3);
    if (bodyEpoch != m.epoch) {
      bodyEpoch = m.epoch;
      retainedPages = [
        for (final resource in ['tasks', 'envs', 'scripts'])
          ResourcePage(
            key: ValueKey('$resource-${m.epoch}'),
            host: this,
            resource: resource,
          ),
        MorePage(host: this),
      ];
    }
    return Scaffold(
      extendBody: true,
      appBar: null,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: m.dark
                      ? [
                          const Color(0xff141416),
                          const Color(0xff141416),
                          const Color(0xff141416),
                        ]
                      : [
                          const Color(0xffefedf0),
                          const Color(0xffefedf0),
                          const Color(0xffefedf0),
                        ],
                ),
              ),
              child: NotificationListener<ScrollNotification>(
                onNotification: (_) {
                  sampleDock();
                  return false;
                },
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      if (m.demo && showDemoNotice)
                        Container(
                          margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: .09),
                            border: Border.all(
                              color: accent.withValues(alpha: .18),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                size: 15,
                                color: accent,
                              ),
                              const SizedBox(width: 7),
                              const Expanded(
                                child: Text(
                                  '演示模式 · 操作仅影响本地示例',
                                  style: TextStyle(fontSize: 10, color: accent),
                                ),
                              ),
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  onPressed: () =>
                                      setState(() => showDemoNotice = false),
                                  icon: const Icon(
                                    Icons.close,
                                    size: 16,
                                    color: accent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: fct.FlClashTabPages(
                          key: ValueKey(m.epoch),
                          index: index,
                          children: [
                            TickerMode(
                              enabled: index == 0,
                              child: retainedPages[0],
                            ),
                            TickerMode(
                              enabled: index == 1,
                              child: retainedPages[1],
                            ),
                            TickerMode(
                              enabled: index == 2,
                              child: retainedPages[2],
                            ),
                            retainedPages[3],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (!keyboard)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: fc.NavigationDock(
                selectedIndex: index,
                onSelected: (i) => m.navigate(pages[i]),
                destinations: const [
                  fc.NavigationDockDestination(
                    glyph: fci.AppGlyphs.clock,
                    label: '任务',
                  ),
                  fc.NavigationDockDestination(
                    glyph: fci.AppGlyphs.code,
                    label: '变量',
                  ),
                  fc.NavigationDockDestination(
                    glyph: fci.AppGlyphs.profiles,
                    label: '文件',
                  ),
                  fc.NavigationDockDestination(
                    glyph: fci.AppGlyphs.tools,
                    label: '我的',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
