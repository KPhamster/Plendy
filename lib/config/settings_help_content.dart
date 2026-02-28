import '../models/help_target.dart';
import '../models/settings_help_target.dart';

const Map<SettingsHelpTargetId, HelpSpec<SettingsHelpTargetId>>
    settingsHelpContent = {
  SettingsHelpTargetId.helpButton: HelpSpec(
    id: SettingsHelpTargetId.helpButton,
    steps: [
      HelpStep(
        text:
            'Here are your settings! Tap on any section and I\'ll explain what it does.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  SettingsHelpTargetId.settingsList: HelpSpec(
    id: SettingsHelpTargetId.settingsList,
    steps: [
      HelpStep(
        text:
            'This is where you can tweak your app preferences and AI parsing settings to make Plendy work just how you like!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  SettingsHelpTargetId.deleteAccountButton: HelpSpec(
    id: SettingsHelpTargetId.deleteAccountButton,
    steps: [
      HelpStep(
        text:
            'Careful with this one! It starts the permanent account deletion process. There\'s no going back.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
};
