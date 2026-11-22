import 'package:material_ui/material_ui.dart';

void main() {
  runApp(const PersonalSenderApp());
}

class PersonalSenderApp extends StatelessWidget {
  const PersonalSenderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'PersonalSender',
      home: Scaffold(body: Center(child: Text('PersonalSender'))),
    );
  }
}
