import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/discovery/discovery.dart' show NetworkKind;
import '../core/history/history_store.dart';
import '../shared_ui/activity_row.dart';
import '../shared_ui/link_indicator.dart';
import '../shared_ui/theme.dart';
import '../shared_ui/tokens.dart';

/// Progress of the batch being sent right now.
class SendingProgress {
  const SendingProgress({required this.label, required this.fraction});

  /// For example "Sending 2 of 4 · 18.4 of 41.0 MB".
  final String label;

  /// 0 to 1.
  final double fraction;
}

/// The phone's Home screen: orange band, connection card, Stay ready row,
/// today's activity and the send buttons. It only draws what it is given.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.paired,
    required this.link,
    required this.network,
    required this.peerName,
    required this.today,
    required this.onSendMedia,
    required this.onSendFiles,
    required this.onTryAgain,
    required this.onPair,
    this.sending,
  });

  /// False until the phone is paired with a laptop.
  final bool paired;
  final LinkState link;
  final NetworkKind network;

  /// The laptop's name, for example "Laptop".
  final String peerName;

  /// Items from today, newest first.
  final List<HistoryItem> today;
  final SendingProgress? sending;
  final VoidCallback onSendMedia;
  final VoidCallback onSendFiles;
  final VoidCallback onTryAgain;
  final VoidCallback onPair;

  bool get _canSend => paired && link == LinkState.connected && sending == null;

  String get _heading {
    if (!paired) return 'Not paired';
    return switch (link) {
      LinkState.connected => 'Connected',
      LinkState.looking => 'Looking for your laptop',
      LinkState.offline => 'Not reachable',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<DeviceColors>()!;
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final topInset = MediaQuery.paddingOf(context).top;
    const bandBelowTitle = 120.0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  Stack(
                    children: [
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: topInset + 64 + bandBelowTitle,
                        child: ColoredBox(color: colors.phoneBand),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(16, topInset + 12, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PersonalSender',
                              style: archivoStyle(
                                22,
                                28,
                              ).copyWith(color: colors.onBand),
                            ),
                            const SizedBox(height: 24),
                            _ConnectionCard(
                              paired: paired,
                              link: link,
                              network: network,
                              peerName: peerName,
                              heading: _heading,
                              sending: sending,
                              onTryAgain: onTryAgain,
                              onPair: onPair,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        // Stay ready arrives in Task 20; until then the
                        // switch is off and cannot be changed.
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: false,
                          onChanged: null,
                          title: const Text('Stay ready'),
                          subtitle: const Text(
                            'Lets the laptop send while the app is closed. '
                            'Coming soon.',
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text('Today', style: text.titleLarge),
                        const SizedBox(height: 8),
                        if (today.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              'Nothing sent or received today yet.',
                              style: text.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        else
                          for (final item in today)
                            ActivityRow(
                              key: ValueKey(item.id),
                              item: item,
                              thisDevice: AppDevice.phone,
                            ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _SendBar(
              enabled: _canSend,
              onSendMedia: onSendMedia,
              onSendFiles: onSendFiles,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.paired,
    required this.link,
    required this.network,
    required this.peerName,
    required this.heading,
    required this.sending,
    required this.onTryAgain,
    required this.onPair,
  });

  final bool paired;
  final LinkState link;
  final NetworkKind network;
  final String peerName;
  final String heading;
  final SendingProgress? sending;
  final VoidCallback onTryAgain;
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;

    final String explanation;
    if (!paired) {
      explanation = 'Pair this phone with your laptop to start sending.';
    } else {
      explanation = switch (link) {
        LinkState.connected => 'Ready to send to $peerName.',
        LinkState.looking =>
          'Open PersonalSender on the laptop and join the same Wi-Fi or '
              'hotspot.',
        LinkState.offline =>
          'Not reachable. Open PersonalSender on the laptop and join the '
              'same Wi-Fi or hotspot.',
      };
    }

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(heading, style: text.headlineMedium),
            const SizedBox(height: 16),
            if (paired) ...[
              LinkIndicator(
                state: link,
                network: network,
                peer: AppDevice.laptop,
              ),
              const SizedBox(height: 16),
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
              const SizedBox(height: 16),
              FilledButton(onPressed: onPair, child: const Text('Pair')),
            ] else if (link == LinkState.offline && sending == null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onTryAgain,
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SendBar extends StatelessWidget {
  const _SendBar({
    required this.enabled,
    required this.onSendMedia,
    required this.onSendFiles,
  });

  final bool enabled;
  final VoidCallback onSendMedia;
  final VoidCallback onSendFiles;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                onPressed: enabled ? onSendMedia : null,
                child: const Text('Send photos & videos'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: enabled ? onSendFiles : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text('Send files'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
