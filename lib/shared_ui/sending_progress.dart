/// Progress of the batch being sent right now.
class SendingProgress {
  const SendingProgress({required this.label, required this.fraction});

  /// For example "Sending 2 of 4 · 18.4 of 41.0 MB".
  final String label;

  /// 0 to 1.
  final double fraction;
}
