import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReceiveShare non-dialog help wiring', () {
    late String combinedReceiveShareText;
    late String receiveShareScreenText;

    setUpAll(() {
      final root = Directory.current.path;
      final screenFile = File('$root/lib/screens/receive_share_screen.dart');
      final widgetDir = Directory('$root/lib/screens/receive_share/widgets');
      final widgetFiles = widgetDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList();

      receiveShareScreenText = screenFile.readAsStringSync();
      combinedReceiveShareText = [
        receiveShareScreenText,
        ...widgetFiles.map((file) => file.readAsStringSync()),
      ].join('\n');
    });

    test(
        'all non-dialog help target ids are referenced in receive-share wiring',
        () {
      const nonDialogTargetIds = <String>[
        'helpButton',
        'privacyToggle',
        'privacyTooltip',
        'urlInputField',
        'urlClearButton',
        'urlPasteButton',
        'urlSubmitButton',
        'screenshotUploadButton',
        'scanButton',
        'mediaPreviewSection',
        'experienceCardsSection',
        'addAnotherExperienceButton',
        'cancelButton',
        'quickAddButton',
        'saveButton',
        'scrollFab',
        'cardHeader',
        'cardRemoveButton',
        'cardPrivacyToggle',
        'cardEventSelector',
        'cardSavedExperienceChooser',
        'cardLocationArea',
        'cardLocationToggle',
        'cardLocationPickerButton',
        'cardGoogleMapsButton',
        'cardYelpButton',
        'cardTitleField',
        'cardCategoryButton',
        'cardColorCategoryButton',
        'cardOtherCategoriesButton',
        'cardWebsiteField',
        'cardWebsitePasteButton',
        'cardNotesField',
        'previewRefreshButton',
        'previewOpenExternalButton',
        'previewExpandButton',
        'previewLinkRow',
      ];

      for (final id in nonDialogTargetIds) {
        final pattern = RegExp('ReceiveShareHelpTargetId\\s*\\.\\s*$id\\b');
        expect(
          pattern.hasMatch(combinedReceiveShareText),
          isTrue,
          reason: 'Expected help target to be wired: $id',
        );
      }
    });

    test('all preview constructors in receive_share_screen pass onHelpTap', () {
      const previewConstructors = <String>[
        'YelpPreviewWidget',
        'TicketmasterPreviewWidget',
        'MapsPreviewWidget',
        'InstagramPreviewWrapper',
        'TikTokPreviewWidget',
        'FacebookPreviewWidget',
        'YouTubePreviewWidget',
        'GoogleKnowledgeGraphPreviewWidget',
        'WebUrlPreviewWidget',
      ];

      for (final constructorName in previewConstructors) {
        final pattern = RegExp(
          '$constructorName\\([\\s\\S]*?onHelpTap\\s*:\\s*_tryHelpTap',
          multiLine: true,
        );
        expect(
          pattern.hasMatch(receiveShareScreenText),
          isTrue,
          reason:
              'Expected $constructorName constructor call to pass onHelpTap: _tryHelpTap',
        );
      }
    });
  });
}
