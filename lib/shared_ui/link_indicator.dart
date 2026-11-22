import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/discovery/discovery.dart' show NetworkKind;
import 'theme.dart';
import 'tokens.dart';

/// What the connection line shows.
enum LinkState { connected, looking, offline }

/// Network label for the chip. Never the network's name.
String? networkLabel(NetworkKind network) => switch (network) {
  NetworkKind.wifi => 'Wi-Fi',
  NetworkKind.phoneHotspot => 'Phone hotspot',
  NetworkKind.laptopHotspot => 'Laptop hotspot',
  NetworkKind.unknown => null,
};

/// The status sentence read out by screen readers. [peer] is the other
/// device from this app's point of view (the laptop in the phone app).
String linkStatusSentence({
  required LinkState state,
  required NetworkKind network,
  required AppDevice peer,
}) {
  final name = peer == AppDevice.laptop ? 'laptop' : 'phone';
  switch (state) {
    case LinkState.connected:
      final label = networkLabel(network);
      return label == null
          ? 'Connected to your $name'
          : 'Connected to your $name over ${label.toLowerCase()}';
    case LinkState.looking:
      return 'Looking for your $name';
    case LinkState.offline:
      return 'Your $name is not reachable';
  }
}

/// The signature element: the two device badges joined by a thick line that
/// is half phone orange and half laptop blue.
///
/// Connected is solid, looking is dashed (the dashes drift unless the system
/// has animations turned off), and not reachable is broken and grey. The phone
/// is always on the left and the laptop on the right.
class LinkIndicator extends StatefulWidget {
  const LinkIndicator({
    super.key,
    required this.state,
    required this.peer,
    this.network = NetworkKind.unknown,
    this.badgeSize = 64,
  });

  final LinkState state;
  final NetworkKind network;

  /// The other device: the laptop in the phone app, the phone in the laptop app.
  final AppDevice peer;

  /// 64 on the phone, 44 on the laptop.
  final double badgeSize;

  @override
  State<LinkIndicator> createState() => _LinkIndicatorState();
}

class _LinkIndicatorState extends State<LinkIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(LinkIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    final animate =
        widget.state == LinkState.looking &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate && !_drift.isAnimating) {
      _drift.repeat();
    } else if (!animate && _drift.isAnimating) {
      _drift.stop();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DeviceColors>()!;
    final scheme = Theme.of(context).colorScheme;
    final label = widget.state == LinkState.offline
        ? null
        : networkLabel(widget.network);

    return Semantics(
      container: true,
      label: linkStatusSentence(
        state: widget.state,
        network: widget.network,
        peer: widget.peer,
      ),
      child: ExcludeSemantics(
        child: Row(
          children: [
            _Badge(
              icon: Icons.smartphone,
              background: colors.phone,
              foreground: colors.onPhone,
              size: widget.badgeSize,
            ),
            Expanded(
              child: SizedBox(
                height: widget.badgeSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _drift,
                        builder: (context, _) => CustomPaint(
                          painter: _LinePainter(
                            state: widget.state,
                            left: colors.phone,
                            right: colors.laptop,
                            broken: scheme.onSurfaceVariant,
                            drift: _drift.value,
                          ),
                        ),
                      ),
                    ),
                    if (label != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: colors.line, width: 1.5),
                        ),
                        child: Text(
                          label,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            _Badge(
              icon: Icons.laptop,
              background: colors.laptop,
              foreground: colors.onLaptop,
              size: widget.badgeSize,
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.size,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(icon, color: foreground, size: size * 0.5),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.state,
    required this.left,
    required this.right,
    required this.broken,
    required this.drift,
  });

  final LinkState state;
  final Color left;
  final Color right;
  final Color broken;
  final double drift;

  static const _thickness = 4.0;
  static const _dash = 10.0;
  static const _gap = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final mid = size.width / 2;
    Paint paint(Color c) => Paint()
      ..color = c
      ..strokeWidth = _thickness
      ..strokeCap = StrokeCap.round;

    switch (state) {
      case LinkState.connected:
        canvas.drawLine(Offset(0, y), Offset(mid, y), paint(left));
        canvas.drawLine(Offset(mid, y), Offset(size.width, y), paint(right));
      case LinkState.looking:
        _dashed(canvas, 0, mid, y, paint(left));
        _dashed(canvas, mid, size.width, y, paint(right));
      case LinkState.offline:
        // Two short grey stubs with a gap in the middle: a broken line.
        final stub = size.width * 0.3;
        canvas.drawLine(Offset(0, y), Offset(stub, y), paint(broken));
        canvas.drawLine(
          Offset(size.width - stub, y),
          Offset(size.width, y),
          paint(broken),
        );
    }
  }

  void _dashed(Canvas canvas, double from, double to, double y, Paint p) {
    const period = _dash + _gap;
    // Drift the pattern to the right by one period per cycle.
    var x = from - period + drift * period;
    while (x < to) {
      final a = math.max(x, from);
      final b = math.min(x + _dash, to);
      if (b > a) canvas.drawLine(Offset(a, y), Offset(b, y), p);
      x += period;
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.state != state ||
      old.left != left ||
      old.right != right ||
      old.broken != broken ||
      old.drift != drift;
}
