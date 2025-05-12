import 'package:flutter/material.dart';
import 'package:plendy/screens/receive_share_screen.dart'; // For ExperienceCardData
import 'package:plendy/models/experience.dart'; // For Location
// TODO: Adjust these import paths if they are incorrect for your project structure
import '../models/user_category.dart';
import '../models/color_category.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ADDED

class ReceiveShareProvider extends ChangeNotifier {
  final List<ExperienceCardData> _experienceCards = [];

  List<UserCategory> _userCategories = [];
  List<ColorCategory> _userColorCategories = [];

  // SharedPreferences keys - should match ReceiveShareScreen
  static const String _lastUsedCategoryNameKey = 'last_used_category_name';
  static const String _lastUsedColorCategoryIdKey = 'last_used_color_category_id';

  // Preferences loaded from SharedPreferences
  String? _lastUsedCategoryNamePreference;
  String? _lastUsedColorCategoryIdPreference;

  List<ExperienceCardData> get experienceCards => _experienceCards;

  ReceiveShareProvider() {
    _loadPreferencesAndInitializeCards();
  }

  Future<void> _loadPreferencesAndInitializeCards() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastUsedCategoryNamePreference = prefs.getString(_lastUsedCategoryNameKey);
      _lastUsedColorCategoryIdPreference = prefs.getString(_lastUsedColorCategoryIdKey);
      print("ReceiveShareProvider: Loaded prefs - LastCategoryName: $_lastUsedCategoryNamePreference, LastColorCategoryID: $_lastUsedColorCategoryIdPreference");
    } catch (e) {
      print("ReceiveShareProvider: Error loading SharedPreferences: $e");
    }

    if (_experienceCards.isEmpty) {
      addExperienceCard(); // This will call _applyDefaultsToCard which now uses the loaded prefs
    }
    // notifyListeners(); // addExperienceCard will notify if it adds a card. If no card added, no immediate UI change needed from just loading prefs.
  }

  void updateUserCategories(List<UserCategory> newCategories) {
    _userCategories = newCategories;
    _reconcileDefaultsForAllCards();
    notifyListeners();
  }

  void updateUserColorCategories(List<ColorCategory> newColorCategories) {
    _userColorCategories = newColorCategories;
    _reconcileDefaultsForAllCards();
    notifyListeners();
  }

  void _applyDefaultsToCard(ExperienceCardData cardData) {
    if (cardData.existingExperienceId != null) {
      print("ReceiveShareProvider: Card ${cardData.id} has existingExperienceId, skipping default override.");
      return;
    }

    // --- Text Category Defaulting ---
    // cardData.selectedcategory is already "Restaurant" from its constructor.

    bool categorySetFromPref = false;
    if (_lastUsedCategoryNamePreference != null) {
      if (_userCategories.isEmpty) {
        // When category list is empty, trust the preference and apply it anyway
        cardData.selectedcategory = _lastUsedCategoryNamePreference;
        categorySetFromPref = true;
        print("ReceiveShareProvider: Card ${cardData.id} - Text category set from preference without validation (empty list): $_lastUsedCategoryNamePreference");
      } 
      else if (_userCategories.any((cat) => cat.name == _lastUsedCategoryNamePreference)) {
        cardData.selectedcategory = _lastUsedCategoryNamePreference;
        categorySetFromPref = true;
        print("ReceiveShareProvider: Card ${cardData.id} - Text category set from preference: $_lastUsedCategoryNamePreference");
      }
      else {
        print("ReceiveShareProvider: Card ${cardData.id} - Preference category '$_lastUsedCategoryNamePreference' not found in loaded categories list.");
      }
    }

    // If not set from preference, it remains "Restaurant".
    // Now, ensure "Restaurant" (or the preference) is valid. If not, pick the first available.
    if (!categorySetFromPref && !_userCategories.isEmpty) { // Only validate if user categories are available
        // If current (Restaurant or other) is not in the list, pick first available
        if (!_userCategories.any((cat) => cat.name == cardData.selectedcategory)) {
            if (_userCategories.isNotEmpty) {
                cardData.selectedcategory = _userCategories.first.name;
                print("ReceiveShareProvider: Card ${cardData.id} - Default text category '${cardData.selectedcategory}' (constructor) not in list. Set to first available: ${_userCategories.first.name}");
            } else {
                 print("ReceiveShareProvider: Card ${cardData.id} - No user categories available to validate/set text category.");
                 // Stays as "Restaurant" from constructor, though it's not in an empty list.
            }
        } else {
           print("ReceiveShareProvider: Card ${cardData.id} - Text category '${cardData.selectedcategory}' (from constructor) is valid or no pref available.");
        }
    }


    // --- Color Category Defaulting ---
    // cardData.selectedColorCategoryId is null from its constructor.

    bool colorCategorySetFromPref = false;
    if (_lastUsedColorCategoryIdPreference != null) {
      if (_userColorCategories.isEmpty) {
        // When color category list is empty, trust the preference and apply it anyway
        cardData.selectedColorCategoryId = _lastUsedColorCategoryIdPreference;
        colorCategorySetFromPref = true;
        print("ReceiveShareProvider: Card ${cardData.id} - Color category set from preference without validation (empty list): $_lastUsedColorCategoryIdPreference");
      }
      else if (_userColorCategories.any((cat) => cat.id == _lastUsedColorCategoryIdPreference)) {
        cardData.selectedColorCategoryId = _lastUsedColorCategoryIdPreference;
        colorCategorySetFromPref = true;
        print("ReceiveShareProvider: Card ${cardData.id} - Color category set from preference: $_lastUsedColorCategoryIdPreference");
      }
      else {
        print("ReceiveShareProvider: Card ${cardData.id} - Preference color category ID '$_lastUsedColorCategoryIdPreference' not found in loaded color categories list.");
      }
    }

    if (!colorCategorySetFromPref && !_userColorCategories.isEmpty) { // Only proceed with "Want to go" logic if not already set
      // Try "Want to go"
      try {
        final wantToGoCategory = _userColorCategories.firstWhere(
            (cat) => cat.name.toLowerCase() == "want to go");
        cardData.selectedColorCategoryId = wantToGoCategory.id;
        print("ReceiveShareProvider: Card ${cardData.id} - Color category set to 'Want to go': ${wantToGoCategory.id}");
      } catch (e) {
        // "Want to go" not found, try the first available color category
        if (_userColorCategories.isNotEmpty) {
          cardData.selectedColorCategoryId = _userColorCategories.first.id;
          print("ReceiveShareProvider: Card ${cardData.id} - Color category 'Want to go' not found. Set to first available: ${_userColorCategories.first.id}");
        } else {
          cardData.selectedColorCategoryId = null; // Explicitly null if no categories
          print("ReceiveShareProvider: Card ${cardData.id} - No color categories available to set default.");
        }
      }
    }
    print("ReceiveShareProvider: Card ${cardData.id} final defaults - Text: ${cardData.selectedcategory}, ColorID: ${cardData.selectedColorCategoryId}");
  }

  void _reconcileDefaultsForAllCards() {
    // bool didChangeAnything = false; // Not strictly needed now as _applyDefaultsToCard prints changes
    for (var cardData in _experienceCards) {
      // String? originalSelectedCategory = cardData.selectedcategory; // For debugging
      // String? originalSelectedColorCategoryId = cardData.selectedColorCategoryId; // For debugging
      
      _applyDefaultsToCard(cardData);

      // if (cardData.selectedcategory != originalSelectedCategory ||
      //     cardData.selectedColorCategoryId != originalSelectedColorCategoryId) {
      //   didChangeAnything = true;
      // }
    }
    // if (didChangeAnything) {
    //    notifyListeners(); // Will be called by the public updateUserCategories/ColorCategories
    // }
  }

  void addExperienceCard() {
    final newCard = ExperienceCardData();
    // Preferences should be loaded by now via _loadPreferencesAndInitializeCards.
    // _applyDefaultsToCard will use these loaded preferences or fallbacks.
    _applyDefaultsToCard(newCard);
    _experienceCards.add(newCard);
    print("ReceiveShareProvider: addExperienceCard. Cards count: ${_experienceCards.length}. New card ID: ${newCard.id.substring(newCard.id.length - 4)}. BEFORE notifyListeners.");
    notifyListeners();
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
