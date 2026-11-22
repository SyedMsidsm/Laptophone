import 'package:flutter_test/flutter_test.dart';
import 'package:personal_sender/main.dart';

void main() {
  testWidgets('shows the PersonalSender placeholder', (tester) async {
    await tester.pumpWidget(const PersonalSenderApp());
    expect(find.text('PersonalSender'), findsOneWidget);
  });
}
