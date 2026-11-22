import 'package:material_ui/material_ui.dart';

import '../core/history/history_store.dart';
import 'format.dart';
import 'theme.dart';
import 'tokens.dart';

/// One line of activity. The tile is coloured by the device the item came
/// from (orange for the phone, blue for the laptop). Direction, waiting and
/// failure are also shown with an icon and words, never by colour alone.
class ActivityRow extends StatelessWidget {
  const ActivityRow({
    super.key,
    required this.item,
    required this.thisDevice,
    this.onRetry,
  });

  final HistoryItem item;

  /// The app this row is shown in. Sent items came from this device.
  final AppDevice thisDevice;

  /// Shown on failed items when set.
  final VoidCallback? onRetry;

  IconData get _icon => switch (item.kind) {
    HistoryKind.photo => Icons.image_outlined,
    HistoryKind.video => Icons.videocam_outlined,
    HistoryKind.file => Icons.insert_drive_file_outlined,
    HistoryKind.text => Icons.notes_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<DeviceColors>()!;
    final scheme = theme.colorScheme;
    final text = theme.textTheme;

    final fromPhone =
        (item.direction == HistoryDirection.sent) ==
        (thisDevice == AppDevice.phone);
    final failed = item.status == HistoryStatus.failed;

    final tileColor = failed
        ? colors.dangerSoft
        : fromPhone
        ? colors.phoneSoft
        : colors.laptopSoft;
    final iconColor = failed
        ? scheme.error
        : fromPhone
        ? colors.phone
        : colors.laptop;

    final to = item.direction == HistoryDirection.sent;
    final directionWord = to ? 'To ${item.peerName}' : 'From ${item.peerName}';
    final time = TimeOfDay.fromDateTime(item.time).format(context);
    final size = formatBytes(item.totalBytes);

    final IconData statusIcon;
    final String statusText;
    final Color statusColor;
    switch (item.status) {
      case HistoryStatus.failed:
        statusIcon = Icons.error_outline;
        statusText = item.failureReason == null
            ? 'Not sent'
            : 'Not sent · ${item.failureReason}';
        statusColor = scheme.error;
      case HistoryStatus.waiting:
        statusIcon = Icons.schedule;
        statusText = 'Waiting · $directionWord';
        statusColor = scheme.onSurfaceVariant;
      case HistoryStatus.done:
        statusIcon = to ? Icons.arrow_upward : Icons.arrow_downward;
        statusText = '$directionWord · $size · $time';
        statusColor = scheme.onSurfaceVariant;
    }

    final spoken = switch (item.status) {
      HistoryStatus.failed =>
        'Not sent: ${item.title} to ${item.peerName}. '
            '${item.failureReason ?? ''}',
      HistoryStatus.waiting => 'Waiting: ${item.title} to ${item.peerName}',
      HistoryStatus.done =>
        '${to ? 'Sent' : 'Received'} ${item.title} '
            '${to ? 'to' : 'from'} ${item.peerName}, $size, $time',
    };

    return Semantics(
      container: true,
      label: spoken,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: tileColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(_icon, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2, right: 4),
                          child: Icon(statusIcon, size: 14, color: statusColor),
                        ),
                        Expanded(
                          child: Text(
                            statusText,
                            style: text.bodySmall?.copyWith(color: statusColor),
                          ),
                        ),
                      ],
                    ),
                    if (failed && onRetry != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: onRetry,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            padding: EdgeInsets.zero,
                            foregroundColor: scheme.error,
                          ),
                          child: const Text('Retry'),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
