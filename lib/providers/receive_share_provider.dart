import 'package:flutter/material.dart';
import 'package:plendy/screens/receive_share_screen.dart'; // For ExperienceCardData
import 'package:plendy/models/experience.dart'; // For Location
// TODO: Adjust these import paths if they are incorrect for your project structure
import '../models/user_category.dart';
import '../models/color_category.dart';

class ReceiveShareProvider extends ChangeNotifier {
  final List<ExperienceCardData> _experienceCards = [];

  List<UserCategory> _userCategories = []; // ADDED
  List<ColorCategory> _userColorCategories = []; // ADDED

  List<ExperienceCardData> get experienceCards => _experienceCards;

  ReceiveShareProvider() {
    // Initialize with one card if the list is empty
    if (_experienceCards.isEmpty) {
      addExperienceCard();
    }
  }

  // ADDED: Method to update user categories (call this from ReceiveShareScreen after fetching)
  void updateUserCategories(List<UserCategory> newCategories) {
    _userCategories = newCategories;
    _reconcileDefaultsForAllCards(); // Apply defaults to existing cards if needed
    notifyListeners();
  }

  // ADDED: Method to update user color categories (call this from ReceiveShareScreen after fetching)
  void updateUserColorCategories(List<ColorCategory> newColorCategories) {
    _userColorCategories = newColorCategories;
    _reconcileDefaultsForAllCards(); // Apply defaults to existing cards if needed
    notifyListeners();
  }

  // ADDED: Helper method to apply default categories to a single card
  void _applyDefaultsToCard(ExperienceCardData cardData) {
    // Don't apply to cards already linked to an existing experience
    if (cardData.existingExperienceId != null) {
      return;
    }

    // Text Category Defaulting (uses _userCategories from the provider)
    if (_userCategories.isNotEmpty &&
        (cardData.selectedcategory == null ||
        !_userCategories.any((cat) => cat.name == cardData.selectedcategory) ||
        cardData.selectedcategory == (UserCategory.defaultCategories.keys.isNotEmpty ? UserCategory.defaultCategories.keys.first : 'Other')))
    {
      UserCategory? defaultTextCategory;
      // Sort by lastUsedTimestamp descending (most recent first)
      List<UserCategory> sortedTextCategories = List.from(_userCategories)
        ..sort((a, b) {
          if (a.lastUsedTimestamp == null && b.lastUsedTimestamp == null) return 0;
          if (a.lastUsedTimestamp == null) return 1; // b is more recent or both null
          if (b.lastUsedTimestamp == null) return -1; // a is more recent
          return b.lastUsedTimestamp!.compareTo(a.lastUsedTimestamp!);
        });

      if (sortedTextCategories.isNotEmpty && sortedTextCategories.first.lastUsedTimestamp != null) {
        defaultTextCategory = sortedTextCategories.first; // Most recently used
      } else {
        // Fallback: try "Restaurant", then first in list
        try {
          defaultTextCategory = _userCategories.firstWhere((cat) => cat.name.toLowerCase() == "restaurant");
        } catch (e) {
          if (_userCategories.isNotEmpty) {
            defaultTextCategory = _userCategories.first;
          }
        }
      }
      cardData.selectedcategory = defaultTextCategory?.name ??
                                 (UserCategory.defaultCategories.keys.isNotEmpty ? UserCategory.defaultCategories.keys.first : 'Other');
    }

    // Color Category Defaulting (uses _userColorCategories from the provider)
    // Apply only if a color category isn't already set for the card
    if (_userColorCategories.isNotEmpty && cardData.selectedColorCategoryId == null) {
      ColorCategory? defaultColorCategory;
      // Sort by lastUsedTimestamp descending
      List<ColorCategory> sortedColorCategories = List.from(_userColorCategories)
        ..sort((a, b) {
          if (a.lastUsedTimestamp == null && b.lastUsedTimestamp == null) return 0;
          if (a.lastUsedTimestamp == null) return 1;
          if (b.lastUsedTimestamp == null) return -1;
          return b.lastUsedTimestamp!.compareTo(a.lastUsedTimestamp!);
        });

      if (sortedColorCategories.isNotEmpty && sortedColorCategories.first.lastUsedTimestamp != null) {
        defaultColorCategory = sortedColorCategories.first; // Most recently used
      } else {
        // Fallback: try "Want to Go", then first in list
        try {
          defaultColorCategory = _userColorCategories.firstWhere((cat) => cat.name.toLowerCase() == "want to go");
        } catch (e) {
          if (_userColorCategories.isNotEmpty) {
            defaultColorCategory = _userColorCategories.first;
          }
        }
      }
      cardData.selectedColorCategoryId = defaultColorCategory?.id;
    }
  }

  // ADDED: Reconciliation logic for existing cards
  void _reconcileDefaultsForAllCards() {
    bool didChangeAnything = false;
    for (var cardData in _experienceCards) {
      String? originalSelectedCategory = cardData.selectedcategory;
      String? originalSelectedColorCategoryId = cardData.selectedColorCategoryId;

      _applyDefaultsToCard(cardData);

      if (cardData.selectedcategory != originalSelectedCategory ||
          cardData.selectedColorCategoryId != originalSelectedColorCategoryId) {
        didChangeAnything = true;
      }
    }
    // NotifyListeners will be called by the public updateUserCategories/updateUserColorCategories
    // but if this method is called from elsewhere and changes things, it should notify.
    // For now, assuming it's only called by the public updaters.
    // If direct calls to _reconcileDefaultsForAllCards (that modify data) are added,
    // uncomment the line below or ensure the caller notifies.
    // if (didChangeAnything) notifyListeners();
  }

  // Add a new experience card
  void addExperienceCard() {
    final newCard = ExperienceCardData(); // MODIFIED
    _applyDefaultsToCard(newCard); // ADDED: Apply defaults when a new card is added
    _experienceCards.add(newCard);
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
      // print("PROVIDER_DEBUG (updateCardData ENTRY): Updating card ${targetCard.id}"); // Keep commented for now

      // --- Keep Logs & Preservation ---
      final String? originalExistingId = targetCard.existingExperienceId;
      print(
          "PROVIDER_DEBUG (updateCardData): BEFORE update. Existing ID: $originalExistingId");
      // --- End Logs & Preservation ---

      // Update Location and related fields
      if (location != null) {
        // print("PROVIDER_DEBUG: Received location: ${location.displayName} (${location.latitude}, ${location.longitude})");
        // print("PROVIDER_DEBUG: Location website: ${location.website}");
        // print("PROVIDER_DEBUG: Current websiteController text: '${targetCard.websiteController.text}'");

        targetCard.selectedLocation = location;
        // Update search query only if it's empty or location address is different
        if (targetCard.searchController.text.isEmpty ||
            targetCard.searchController.text != (location.address ?? '')) {
          // print("PROVIDER_DEBUG: Updating searchController text to: '${location.address ?? ''}'");
          targetCard.searchController.text = location.address ?? '';
        }
        // Update title only if it's empty or location display name is different
        if (targetCard.titleController.text.isEmpty ||
            targetCard.titleController.text != location.getPlaceName()) {
          // print("PROVIDER_DEBUG: Updating titleController text to: '${location.getPlaceName()}'");
          targetCard.titleController.text =
              location.getPlaceName(); // <-- Updates title
        }
        // Update website only if it's empty or location website is different
        if (targetCard.websiteController.text.isEmpty ||
            targetCard.websiteController.text != (location.website ?? '')) {
          // print("PROVIDER_DEBUG: Updating websiteController text to: '${location.website ?? ''}'");
          targetCard.websiteController.text =
              location.website ?? ''; // <-- Updates website
        }
      } // else {
      // print("PROVIDER_DEBUG: No location object provided for update.");
      // }

      // Update Title (Explicitly passed)
      if (title != null) {
        // print("PROVIDER_DEBUG: Explicitly updating titleController text to: '$title'");
        targetCard.titleController.text = title;
      }

      // Update Website (Explicitly passed)
      if (website != null) {
        // print("PROVIDER_DEBUG: Explicitly updating websiteController text to: '$website'");
        targetCard.websiteController.text = website;
      }

      // Update Search Query (Explicitly passed)
      if (searchQuery != null) {
        // print("PROVIDER_DEBUG: Explicitly updating searchController text to: '$searchQuery'");
        targetCard.searchController.text = searchQuery;
      }

      // Update Place ID for Preview
      if (placeIdForPreview != null) {
        // print("PROVIDER_DEBUG: Updating placeIdForPreview to: '$placeIdForPreview'");
        targetCard.placeIdForPreview = placeIdForPreview;
      }

      // --- Keep Logs & Restoration ---
      print(
          "PROVIDER_DEBUG (updateCardData): AFTER update. Current Existing ID: ${targetCard.existingExperienceId}");
      // Just in case, ensure the original ID wasn't overwritten if it existed
      if (originalExistingId != null &&
          targetCard.existingExperienceId == null) {
        print(
            "PROVIDER_DEBUG (updateCardData): WARNING! Existing ID was lost during update. Restoring.");
        targetCard.existingExperienceId = originalExistingId;
      }
      print(
          "PROVIDER_DEBUG (updateCardData): FINAL Existing ID for card ${targetCard.id}: ${targetCard.existingExperienceId}");
      // --- END LOGS & RESTORATION ---

      // print("PROVIDER_DEBUG: --- Update Check ---");
      // print("PROVIDER_DEBUG: Final card.selectedLocation: ${targetCard.selectedLocation?.displayName}");
      // print("PROVIDER_DEBUG: Final titleController: '${targetCard.titleController.text}'");
      // print("PROVIDER_DEBUG: Final websiteController: '${targetCard.websiteController.text}'");
      // print("PROVIDER_DEBUG: --- End Update Check ---");

      notifyListeners(); // Notify that card data has changed
    } // else {
    // print("PROVIDER_DEBUG: Card with ID ${card.id} not found for update.");
    // }
  }

  // Update a card's data based on a selected existing Experience
  void updateCardWithExistingExperience(
      String cardId, Experience selectedExperience) {
    int index = _experienceCards.indexWhere((c) => c.id == cardId);
    if (index != -1) {
      final targetCard = _experienceCards[index];

      // --- Keep Log ---
      print(
          "PROVIDER_DEBUG (updateCardWithExisting): Setting existingExperienceId to '${selectedExperience.id}' for card ${targetCard.id}");
      // --- END Log ---

      // Update the fields in the ExperienceCardData
      targetCard.existingExperienceId = selectedExperience.id;
      targetCard.titleController.text = selectedExperience.name;
      targetCard.selectedLocation =
          selectedExperience.location; // Assign the whole Location object
      targetCard.selectedcategory = selectedExperience.category;
      targetCard.yelpUrlController.text = selectedExperience.yelpUrl ?? '';
      targetCard.websiteController.text = selectedExperience.website ?? '';
      targetCard.notesController.text =
          selectedExperience.additionalNotes ?? '';
      // Clear search text as location is now set
      targetCard.searchController.clear();
      // Ensure location is enabled
      targetCard.locationEnabled = true;
      // Optionally update placeIdForPreview if the location has one
      targetCard.placeIdForPreview = selectedExperience.location.placeId;

      // print('PROVIDER_DEBUG: Updated card $cardId with existing experience ${selectedExperience.id} (${selectedExperience.name})');
      notifyListeners();
    } // else {
    // print('PROVIDER_DEBUG: Card with ID $cardId not found for update with existing experience.');
    // }
  }

  /// Updates the selected color category for a specific experience card.
  void updateCardColorCategory(String cardId, String? newColorCategoryId) {
    // Allow null to clear
    final index = _experienceCards.indexWhere((card) => card.id == cardId);
    if (index != -1) {
      if (_experienceCards[index].selectedColorCategoryId !=
          newColorCategoryId) {
        _experienceCards[index].selectedColorCategoryId = newColorCategoryId;
        print(
            "Provider: Updated color category for card $cardId to $newColorCategoryId");
        notifyListeners(); // Notify listeners about the change
      }
    } else {
      print(
          "Provider ERROR: Card with ID $cardId not found for color category update.");
    }
  }

  /// Updates the selected text category for a specific experience card.
  void updateCardTextCategory(String cardId, String? newTextCategoryName) {
    // Allow null to clear
    final index = _experienceCards.indexWhere((card) => card.id == cardId);
    if (index != -1) {
      if (_experienceCards[index].selectedcategory != newTextCategoryName) {
        _experienceCards[index].selectedcategory = newTextCategoryName;
        print(
            "Provider: Updated text category for card $cardId to $newTextCategoryName");
        notifyListeners(); // Notify listeners about the change
      }
    } else {
      print(
          "Provider ERROR: Card with ID $cardId not found for text category update.");
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

  // --- ADDED METHOD ---
  void updateCardFromShareDetails({
    required String cardId,
    required Location location,
    required String title, // This will be the businessName or placeName
    String? yelpUrl,      // Nullable, used if the source was Yelp
    String? mapsUrl,      // Nullable, used if the source was Maps
    String? website,
    required String? placeIdForPreview, // The key for the preview Future
    String? searchQueryText, // Text for the card's search/location display field
  }) {
    final cardIndex = _experienceCards.indexWhere((c) => c.id == cardId);
    if (cardIndex != -1) {
      final card = _experienceCards[cardIndex];

      // Update controllers and properties directly on the card object
      card.titleController.text = title;
      card.selectedLocation = location; // This is your Location model instance

      if (yelpUrl != null) {
        card.yelpUrlController.text = yelpUrl;
      }
      if (website != null) {
        card.websiteController.text = website;
      }
      // Update the text field that shows the location/address in the card form
      if (searchQueryText != null) {
        card.searchController.text = searchQueryText;
      } else {
        card.searchController.text = location.address ?? 'Address not found';
      }

      card.placeIdForPreview = placeIdForPreview; // Crucial for preview widget keying

      // If you track originalShareType on the card, you might set it here too
      // e.g., if (yelpUrl != null) card.originalShareType = ShareType.yelp;
      // else if (mapsUrl != null) card.originalShareType = ShareType.maps;

      print("PROVIDER: updateCardFromShareDetails for card ${card.id}, new title: $title, new placeIdForPreview: $placeIdForPreview");
      notifyListeners(); // This will trigger rebuilds in widgets listening to the provider
    } else {
      print("PROVIDER ERROR: updateCardFromShareDetails - Card not found with ID: $cardId");
    }
  }
  // --- END ADDED METHOD ---

  @override
  void dispose() {
    // Dispose all controllers when the provider itself is disposed
    for (var card in _experienceCards) {
      card.dispose();
    }
    super.dispose();
  }
}
