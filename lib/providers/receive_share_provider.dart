import 'package:flutter/material.dart';
import 'package:plendy/screens/receive_share_screen.dart'; // For ExperienceCardData
import 'package:plendy/models/experience.dart'; // For Location

class ReceiveShareProvider extends ChangeNotifier {
  final List<ExperienceCardData> _experienceCards = [];

  List<ExperienceCardData> get experienceCards => _experienceCards;

  ReceiveShareProvider() {
    // Initialize with one card if the list is empty
    if (_experienceCards.isEmpty) {
      addExperienceCard();
    }
  }

  // Add a new experience card
  void addExperienceCard() {
    _experienceCards.add(ExperienceCardData());
    notifyListeners(); // Notify listeners about the change
  }

  // Remove an experience card
  void removeExperienceCard(ExperienceCardData card) {
    // Dispose the card's resources before removing
    card.dispose();
    _experienceCards.remove(card);

    // If all cards are removed, add a new one back
    if (_experienceCards.isEmpty) {
      addExperienceCard(); // This will also call notifyListeners
    } else {
      notifyListeners(); // Notify listeners about the removal
    }
  }

  // Method to update card data (e.g., after location selection)
  // This might be needed if ExperienceCardForm doesn't directly modify the data
  void updateCardData(
    ExperienceCardData card, {
    Location? location,
    String? title,
    String? website,
    String? searchQuery,
    String? placeIdForPreview,
  }) {
    // Find the card and update its properties
    int index = _experienceCards.indexWhere((c) => c.id == card.id);
    if (index != -1) {
      final targetCard = _experienceCards[index]; // Easier reference
      print("PROVIDER_DEBUG: Updating card ${targetCard.id}"); // Log card ID

      // Update Location and related fields
      if (location != null) {
        print(
            "PROVIDER_DEBUG: Received location: ${location.displayName} (${location.latitude}, ${location.longitude})");
        print("PROVIDER_DEBUG: Location website: ${location.website}");
        print(
            "PROVIDER_DEBUG: Current websiteController text: '${targetCard.websiteController.text}'");

        targetCard.selectedLocation = location;
        // Update search query only if it's empty or location address is different
        if (targetCard.searchController.text.isEmpty ||
            targetCard.searchController.text != (location.address ?? '')) {
          print(
              "PROVIDER_DEBUG: Updating searchController text to: '${location.address ?? ''}'");
          targetCard.searchController.text = location.address ?? '';
        }
        // Update title only if it's empty or location display name is different
        if (targetCard.titleController.text.isEmpty ||
            targetCard.titleController.text != location.getPlaceName()) {
          print(
              "PROVIDER_DEBUG: Updating titleController text to: '${location.getPlaceName()}'");
          targetCard.titleController.text =
              location.getPlaceName(); // <-- Updates title
        }
        // Update website only if it's empty or location website is different
        if (targetCard.websiteController.text.isEmpty ||
            targetCard.websiteController.text != (location.website ?? '')) {
          print(
              "PROVIDER_DEBUG: Updating websiteController text to: '${location.website ?? ''}'");
          targetCard.websiteController.text =
              location.website ?? ''; // <-- Updates website
        }
      } else {
        print("PROVIDER_DEBUG: No location object provided for update.");
      }

      // Update Title (Explicitly passed)
      if (title != null) {
        print(
            "PROVIDER_DEBUG: Explicitly updating titleController text to: '$title'");
        targetCard.titleController.text = title;
      }

      // Update Website (Explicitly passed)
      if (website != null) {
        print(
            "PROVIDER_DEBUG: Explicitly updating websiteController text to: '$website'");
        targetCard.websiteController.text = website;
      }

      // Update Search Query (Explicitly passed)
      if (searchQuery != null) {
        print(
            "PROVIDER_DEBUG: Explicitly updating searchController text to: '$searchQuery'");
        targetCard.searchController.text = searchQuery;
      }

      // Update Place ID for Preview
      if (placeIdForPreview != null) {
        print(
            "PROVIDER_DEBUG: Updating placeIdForPreview to: '$placeIdForPreview'");
        targetCard.placeIdForPreview = placeIdForPreview;
      }

      print("PROVIDER_DEBUG: --- Update Check ---");
      print(
          "PROVIDER_DEBUG: Final card.selectedLocation: ${targetCard.selectedLocation?.displayName}");
      print(
          "PROVIDER_DEBUG: Final titleController: '${targetCard.titleController.text}'");
      print(
          "PROVIDER_DEBUG: Final websiteController: '${targetCard.websiteController.text}'");
      print("PROVIDER_DEBUG: --- End Update Check ---");

      notifyListeners(); // Notify that card data has changed
    } else {
      print("PROVIDER_DEBUG: Card with ID ${card.id} not found for update.");
    }
  }

  // Notify listeners that a specific card's data might have changed externally
  void notifyCardChanged(ExperienceCardData card) {
    // We don't strictly need the card object here, but it mirrors the pattern
    // The main goal is just to trigger a rebuild for consumers
    int index = _experienceCards.indexWhere((c) => c.id == card.id);
    if (index != -1) {
      notifyListeners();
    }
  }

  // Clear all cards and add a fresh one (e.g., when new content is received)
  void resetExperienceCards() {
    // Dispose all existing cards first
    for (var card in _experienceCards) {
      card.dispose();
    }
    _experienceCards.clear();
    addExperienceCard(); // Adds one card and notifies listeners
  }

  @override
  void dispose() {
    // Dispose all controllers when the provider itself is disposed
    for (var card in _experienceCards) {
      card.dispose();
    }
    super.dispose();
  }
}
