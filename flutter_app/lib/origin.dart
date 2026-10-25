part of 'main.dart';

final Object _routeOriginKey = Object();

class OriginAction extends StatefulWidget {
  final VoidCallback? action;
  final Widget Function(VoidCallback?) builder;
  const OriginAction({super.key, required this.action, required this.builder});
  @override
  State<OriginAction> createState() => _OriginActionState();
}

class _OriginActionState extends State<OriginAction> {
  final anchor = GlobalKey();
  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: anchor,
    child: widget.builder(
      widget.action == null
          ? null
          : () {
              runZoned(
                widget.action!,
                zoneValues: {_routeOriginKey: _RouteOrigin(anchor)},
              );
            },
    ),
  );
}

/// The source stays in place; only one live page participates in the route.
class _RouteOrigin {
  const _RouteOrigin(this.anchor);
  final GlobalKey anchor;

  Future<T?> open<T>(BuildContext context, Widget page) {
    final source = anchor.currentContext?.findRenderObject();
    final navigator = Navigator.of(context);
    final root = navigator.context.findRenderObject();
    Rect? origin;
    if (source is RenderBox && root is RenderBox && source.hasSize) {
      origin = MatrixUtils.transformRect(
        source.getTransformTo(root),
        Offset.zero & source.size,
      );
    }
    return navigator.push<T>(
      PageRouteBuilder<T>(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, _, _) => Material(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xff141416)
              : const Color(0xffefedf0),
          child: page,
        ),
        transitionsBuilder: (context, animation, _, child) => _AnchorTransition(
          animation: animation,
          origin: origin,
          child: RepaintBoundary(child: child),
        ),
      ),
    );
  }
}

/// The page lays out once at full size. Animation updates only its retained
/// clip, opacity and paint offset, rather than rebuilding a Positioned tree.
class _AnchorTransition extends SingleChildRenderObjectWidget {
  final Animation<double> animation;
  final Rect? origin;
  const _AnchorTransition({
    required this.animation,
    this.origin,
    required super.child,
  });
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAnchorTransition(animation, origin);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAnchorTransition renderObject,
  ) {
    renderObject
      ..animation = animation
      ..origin = origin;
  }
}

class _RenderAnchorTransition extends RenderProxyBox {
  _RenderAnchorTransition(this._animation, this._origin);
  Animation<double> _animation;
  Rect? _origin;
  final _clip = LayerHandle<ClipRRectLayer>();
  final _opacity = LayerHandle<OpacityLayer>();
  set animation(Animation<double> value) {
    if (identical(value, _animation)) return;
    if (attached) {
      _animation.removeListener(markNeedsPaint);
      _animation.removeStatusListener(_statusChanged);
    }
    _animation = value;
    if (attached) {
      _animation.addListener(markNeedsPaint);
      _animation.addStatusListener(_statusChanged);
    }
    markNeedsPaint();
  }

  set origin(Rect? value) {
    if (_origin != value) {
      _origin = value;
      markNeedsPaint();
    }
  }

  @override
  bool get alwaysNeedsCompositing => child != null;
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _animation.addListener(markNeedsPaint);
    _animation.addStatusListener(_statusChanged);
  }

  @override
  void detach() {
    _animation.removeListener(markNeedsPaint);
    _animation.removeStatusListener(_statusChanged);
    super.detach();
  }

  void _statusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed ||
        status == AnimationStatus.dismissed) {
      markNeedsSemanticsUpdate();
    }
  }

  bool get closing => _animation.status == AnimationStatus.reverse;
  double get progress =>
      (closing ? Curves.fastOutSlowIn.flipped : Curves.fastOutSlowIn).transform(
        _animation.value,
      );
  Rect get rect =>
      Rect.lerp(_origin ?? Offset.zero & size, Offset.zero & size, progress)!;
  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    final t = progress, bounds = rect;
    final alpha =
        (((_animation.value - (closing ? .6 : .2)) / .2).clamp(0.0, 1.0) * 255)
            .round();
    final rounded = RRect.fromRectAndRadius(
      bounds,
      Radius.circular(24 * (1 - t)),
    );
    _clip.layer = context.pushClipRRect(true, offset, bounds, rounded, (
      context,
      offset,
    ) {
      _opacity.layer = context.pushOpacity(
        offset,
        alpha,
        (context, offset) =>
            context.paintChild(child!, offset + bounds.topLeft),
        oldLayer: _opacity.layer,
      );
    }, oldLayer: _clip.layer);
  }

  @override
  bool hitTestSelf(Offset position) => true;
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      _animation.isCompleted &&
      super.hitTestChildren(result, position: position);
  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final shift = rect.topLeft;
    transform.translateByDouble(shift.dx, shift.dy, 0, 1);
  }

  @override
  void dispose() {
    _clip.layer = null;
    _opacity.layer = null;
    super.dispose();
  }
}
