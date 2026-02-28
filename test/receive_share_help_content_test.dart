import 'package:flutter_test/flutter_test.dart';
import 'package:plendy/models/receive_share_help_target.dart';
import 'package:plendy/config/receive_share_help_content.dart';

void main() {
  group('ReceiveShareHelpContent completeness', () {
    test('every ReceiveShareHelpTargetId has a non-null content entry', () {
      for (final id in ReceiveShareHelpTargetId.values) {
        final spec = receiveShareHelpContent[id];
        expect(spec, isNotNull,
            reason: 'Missing content for $id');
      }
    });

    test('every content entry has at least one step', () {
      for (final entry in receiveShareHelpContent.entries) {
        expect(entry.value.steps, isNotEmpty,
            reason: '${entry.key} has empty steps list');
      }
    });

    test('every first step has non-empty text', () {
      for (final entry in receiveShareHelpContent.entries) {
        final firstStep = entry.value.steps.first;
        expect(firstStep.text.isNotEmpty, isTrue,
            reason: '${entry.key} first step has empty text');
      }
    });

    test('content spec id matches its map key', () {
      for (final entry in receiveShareHelpContent.entries) {
        expect(entry.value.id, entry.key,
            reason:
                'Spec id ${entry.value.id} does not match map key ${entry.key}');
      }
    });

    test('no content entry has duplicate id within steps', () {
      for (final entry in receiveShareHelpContent.entries) {
        final texts = entry.value.steps.map((s) => s.text).toList();
        final unique = texts.toSet();
        expect(texts.length, unique.length,
            reason: '${entry.key} has duplicate step text');
      }
    });
  });
}
