import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:material_ui/material_ui.dart';

import '../shared_ui/tokens.dart';

/// What the drop zone looks like. Kept apart from [DropZone] so it can be
/// drawn and tested without a real drag.
class DropZoneView extends StatelessWidget {
  const DropZoneView({
    super.key,
    required this.dragging,
    required this.onChoose,
    this.busy = false,
  });

  /// True while files are being dragged over the window.
  final bool dragging;

  /// True while a batch is being sent.
  final bool busy;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<DeviceColors>()!;
    final text = theme.textTheme;

    return CustomPaint(
      foregroundPainter: _BorderPainter(
        color: colors.laptop,
        dashed: !dragging,
        radius: 14,
      ),
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 120),
        constraints: const BoxConstraints(minHeight: 220),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: dragging ? colors.laptopSoft : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: dragging ? _dragOver(context, colors) : _idle(context, text),
        ),
      ),
    );
  }

  Widget _idle(BuildContext context, TextTheme text) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Drop files here',
          style: text.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'They go straight to your phone.',
          style: text.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : onChoose,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
          child: const Text('Choose files…'),
        ),
        const SizedBox(height: 8),
        Text('Ctrl+O', style: text.bodySmall),
      ],
    );
  }

  Widget _dragOver(BuildContext context, DeviceColors colors) {
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: colors.phone,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.smartphone, color: colors.onPhone, size: 32),
        ),
        const SizedBox(height: 12),
        // The system does not tell us how many files are being dragged until
        // they are dropped, so no count is shown here.
        Text(
          'Drop to send',
          style: text.headlineMedium?.copyWith(color: colors.onLaptopSoft),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// The laptop's drop zone: files dropped on it are passed to [onFiles].
/// Still accepts drops when the phone is not reachable.
class DropZone extends StatefulWidget {
  const DropZone({
    super.key,
    required this.onFiles,
    required this.onChoose,
    this.busy = false,
  });

  /// Paths of the dropped files (folders are skipped).
  final void Function(List<String> paths) onFiles;
  final VoidCallback onChoose;
  final bool busy;

  @override
  State<DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<DropZone> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) {
        setState(() => _dragging = false);
        final paths = [
          for (final f in details.files)
            if (FileSystemEntity.isFileSync(f.path)) f.path,
        ];
        if (paths.isNotEmpty) widget.onFiles(paths);
      },
      child: DropZoneView(
        dragging: _dragging,
        busy: widget.busy,
        onChoose: widget.onChoose,
      ),
    );
  }
}

/// Dashed or solid rounded border, 3 px, as the design asks.
class _BorderPainter extends CustomPainter {
  _BorderPainter({
    required this.color,
    required this.dashed,
    required this.radius,
  });

  final Color color;
  final bool dashed;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final rect = Rect.fromLTWH(1.5, 1.5, size.width - 3, size.height - 3);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    if (!dashed) {
      canvas.drawPath(path, paint);
      return;
    }
    const dash = 12.0;
    const gap = 8.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = (d + dash).clamp(0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(d, end), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_BorderPainter old) =>
      old.color != color || old.dashed != dashed || old.radius != radius;
}
