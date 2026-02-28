import '../models/help_target.dart';
import '../models/location_picker_help_target.dart';

const Map<LocationPickerHelpTargetId, HelpSpec<LocationPickerHelpTargetId>>
    locationPickerHelpContent = {
  LocationPickerHelpTargetId.helpButton: HelpSpec(
    id: LocationPickerHelpTargetId.helpButton,
    steps: [
      HelpStep(
        text:
            'Let\'s pick a location! Tap around and I\'ll show you how it works.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  LocationPickerHelpTargetId.searchBar: HelpSpec(
    id: LocationPickerHelpTargetId.searchBar,
    steps: [
      HelpStep(
        text: 'Search for a place by name or address!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  LocationPickerHelpTargetId.mapArea: HelpSpec(
    id: LocationPickerHelpTargetId.mapArea,
    steps: [
      HelpStep(
        text:
            'Tap and drag around the map to find your spot! Move the pin to exactly where you want.',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
  LocationPickerHelpTargetId.confirmButton: HelpSpec(
    id: LocationPickerHelpTargetId.confirmButton,
    steps: [
      HelpStep(
        text: 'Found the right spot? Tap here to confirm your pick!',
        instruction: 'Tap anywhere to dismiss',
      ),
    ],
  ),
};
