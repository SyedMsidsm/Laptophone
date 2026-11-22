import 'package:material_ui/material_ui.dart';

import '../core/discovery/discovery.dart' show NetworkKind;
import '../core/history/history_store.dart';
import '../shared_ui/activity_row.dart';
import '../shared_ui/link_indicator.dart';
import '../shared_ui/sending_progress.dart';
import '../shared_ui/theme.dart';
import '../shared_ui/tokens.dart';
import 'drop_zone.dart';
import 'shortcuts.dart';

/// Below this width the Activity list stacks under the drop zone.
const double mainWindowWideBreakpoint = 760;

/// The laptop's main window: blue header, connection card, drop zone and the
/// Activity list. It only draws what it is given.
class MainWindow extends StatelessWidget {
  const MainWindow({
    super.key,
    required this.paired,
    required this.link,
    required this.network,
    required this.peerName,
    required this.activity,
    required this.onFiles,
    required this.onChoose,
    required this.onPair,
    required this.onOpenFolder,
    required this.onTryAgain,
    this.sending,
  });

  final bool paired;
  final LinkState link;
  final NetworkKind network;

  /// The phone's name.
  final String peerName;

  /// Recent items, newest first.
  final List<HistoryItem> activity;
  final SendingProgress? sending;

  /// Files were dropped or chosen.
  final void Function(List<String> paths) onFiles;
  final VoidCallback onChoose;
  final VoidCallback onPair;
  final VoidCallback onOpenFolder;
  final VoidCallback onTryAgain;

  String get _heading {
    if (!paired) return 'Not paired';
    return switch (link) {
      LinkState.connected => 'Connected',
      LinkState.looking => 'Looking for your phone',
      LinkState.offline => 'Not reachable',
    };
  }

  String get _explanation {
    if (!paired) return 'Pair your phone with this laptop to start sending.';
    return switch (link) {
      LinkState.connected => 'Ready to send to $peerName.',
      LinkState.looking =>
        'Open PersonalSender on the phone and join the same Wi-Fi or hotspot.',
      LinkState.offline =>
        'Not reachable. Open PersonalSender on the phone and join the same '
            'Wi-Fi or hotspot.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<DeviceColors>()!;
    return Shortcuts(
      shortcuts: mainWindowShortcuts,
      child: Actions(
        actions: {
          ChooseFilesIntent: CallbackAction<ChooseFilesIntent>(
            onInvoke: (_) {
              if (sending == null) onChoose();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Column(
              children: [
                _Header(
                  band: colors.laptopBand,
                  onBand: colors.onBand,
                  onPair: onPair,
                  onOpenFolder: onOpenFolder,
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final left = _LeftColumn(
                        heading: _heading,
                        explanation: _explanation,
                        paired: paired,
                        link: link,
                        network: network,
                        sending: sending,
                        onFiles: onFiles,
                        onChoose: onChoose,
                        onPair: onPair,
                        onTryAgain: onTryAgain,
                      );
                      final activityList = _ActivityList(items: activity);
                      if (box.maxWidth >= mainWindowWideBreakpoint) {
                        return Padding(
                          padding: const EdgeInsets.all(24),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 5,
                                child: SingleChildScrollView(child: left),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                flex: 4,
                                child: SingleChildScrollView(
                                  child: activityList,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          left,
                          const SizedBox(height: 24),
                          activityList,
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.band,
    required this.onBand,
    required this.onPair,
    required this.onOpenFolder,
  });

  final Color band;
  final Color onBand;
  final VoidCallback onPair;
  final VoidCallback onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      foregroundColor: onBand,
      minimumSize: const Size(0, 32),
    );
    return Container(
      color: band,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Text(
            'PersonalSender',
            style: archivoStyle(15, 20).copyWith(color: onBand),
          ),
          const SizedBox(width: 16),
          TextButton(
            onPressed: onPair,
            style: style,
            child: const Text('Pair phone'),
          ),
          TextButton(
            onPressed: onOpenFolder,
            style: style,
            child: const Text('Open received folder'),
          ),
        ],
      ),
    );
  }
}

class _LeftColumn extends StatelessWidget {
  const _LeftColumn({
    required this.heading,
    required this.explanation,
    required this.paired,
    required this.link,
    required this.network,
    required this.sending,
    required this.onFiles,
    required this.onChoose,
    required this.onPair,
    required this.onTryAgain,
  });

  final String heading;
  final String explanation;
  final bool paired;
  final LinkState link;
  final NetworkKind network;
  final SendingProgress? sending;
  final void Function(List<String>) onFiles;
  final VoidCallback onChoose;
  final VoidCallback onPair;
  final VoidCallback onTryAgain;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(heading, style: text.headlineMedium),
                const SizedBox(height: 12),
                if (paired) ...[
                  LinkIndicator(
                    state: link,
                    network: network,
                    peer: AppDevice.phone,
                    badgeSize: 44,
                  ),
                  const SizedBox(height: 12),
                ],
                if (sending != null) ...[
                  Text(sending!.label, style: text.bodyMedium),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: sending!.fraction,
                      minHeight: 12,
                    ),
                  ),
                ] else
                  Text(explanation, style: text.bodyMedium),
                if (!paired) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: onPair,
                    child: const Text('Pair phone'),
                  ),
                ] else if (link == LinkState.offline && sending == null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: onTryAgain,
                    child: const Text('Try again'),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        DropZone(onFiles: onFiles, onChoose: onChoose, busy: sending != null),
      ],
    );
  }
}

class _ActivityList extends StatelessWidget {
  const _ActivityList({required this.items});

  final List<HistoryItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Activity', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Nothing sent or received yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final item in items)
            ActivityRow(
              key: ValueKey(item.id),
              item: item,
              thisDevice: AppDevice.laptop,
            ),
      ],
    );
  }
}
