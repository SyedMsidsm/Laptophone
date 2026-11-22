import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Ctrl+O: choose files to send.
class ChooseFilesIntent extends Intent {
  const ChooseFilesIntent();
}

/// Keyboard shortcuts for the laptop's main window. (Ctrl+V for the
/// clipboard arrives with Task 18.)
final Map<ShortcutActivator, Intent> mainWindowShortcuts = {
  const SingleActivator(LogicalKeyboardKey.keyO, control: true):
      const ChooseFilesIntent(),
};
