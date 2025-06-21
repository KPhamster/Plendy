import 'package:flutter/material.dart';
import 'package:plendy/screens/receive_share_screen.dart'; // For ExperienceCardData
import 'package:plendy/models/experience.dart'; // For Location
import 'package:plendy/config/app_constants.dart'; // ADDED: For unified keys
// TODO: Adjust these import paths if they are incorrect for your project structure
import '../models/user_category.dart';
import '../models/color_category.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ADDED
import 'package:collection/collection.dart'; // ADDED for firstWhereOrNull

class ReceiveShareProvider extends ChangeNotifier {
  final List<ExperienceCardData> _experienceCards = [];

  List<UserCategory> _userCategories = [];
  List<ColorCategory> _userColorCategories = [];
  SharedPreferences? _prefs; // ADDED: To store SharedPreferences instance

  List<ExperienceCardData> get experienceCards => _experienceCards;

  // MODIFIED: Constructor is now simpler. Dependencies are set via setDependencies.
  ReceiveShareProvider() {
    print("ReceiveShareProvider: Instance created. Waiting for dependencies.");
    // REMOVED: _loadPreferencesAndInitializeCards(); 
    // Initialization logic, including adding the first card,
    // will now be triggered after dependencies are set.
  }

  // ADDED: Method to set dependencies from ReceiveShareScreen
  Future<void> setDependencies({
    required SharedPreferences prefs,
    required List<UserCategory> userCategories,
    required List<ColorCategory> userColorCategories,
  }) async {
    _prefs = prefs;
    _userCategories = userCategories;
    _userColorCategories = userColorCategories;
    print("ReceiveShareProvider: Dependencies set. Prefs loaded. UserCategories: ${_userCategories.length}, ColorCategories: ${_userColorCategories.length}");

    // If no cards exist yet (e.g., initial setup), add the first one.
    // This ensures defaults are applied using the now-available categories and prefs.
    if (_experienceCards.isEmpty) {
      print("ReceiveShareProvider: No cards exist after setting dependencies, adding initial card.");
      addExperienceCard();
    } else {
      // If cards already exist (e.g., from a previous state before a hot reload that calls setDependencies again),
      // we might want to reconcile their defaults if the category lists have changed significantly.
      // For now, we'll assume cards are either empty or their state is managed.
      // Consider if _reconcileDefaultsForAllCards(); is needed here in some scenarios.
      print("ReceiveShareProvider: Cards already exist. Count: ${_experienceCards.length}. Not adding initial card from setDependencies.");
    }
    // notifyListeners(); // addExperienceCard will notify if it runs.
  }

  void updateUserCategories(List<UserCategory> newCategories) {
    _userCategories = newCategories;
    print("ReceiveShareProvider: updateUserCategories called with ${newCategories.length} categories.");
    // REMOVED: _reconcileDefaultsForAllCards(); // Defaults are set on creation.
    // If categories list changes, existing card selections are preserved unless user changes them.
    notifyListeners(); 
  }

  void updateUserColorCategories(List<ColorCategory> newColorCategories) {
    _userColorCategories = newColorCategories;
     print("ReceiveShareProvider: updateUserColorCategories called with ${newColorCategories.length} color categories.");
    // REMOVED: _reconcileDefaultsForAllCards(); 
    notifyListeners(); 
  }

  void _applyDefaultsToCard(ExperienceCardData cardData, {required bool isFirstCard}) {
    if (_prefs == null) {
      print("Provider WARN (_applyDefaultsToCard): SharedPreferences not available. Cannot apply preference-based defaults.");
      // Fallback to basic defaults if prefs aren't loaded (should not happen if setDependencies is called correctly)
      if (_userCategories.isNotEmpty) {
        final restaurantCategory = _userCategories.firstWhereOrNull((cat) => cat.name.toLowerCase() == "restaurant");
        cardData.selectedCategoryId = restaurantCategory?.id ?? _userCategories.first.id;
      } else {
        cardData.selectedCategoryId = null;
      }
      if (_userColorCategories.isNotEmpty) {
        final wantToGoCategory = _userColorCategories.firstWhereOrNull((cat) => cat.name.toLowerCase() == "want to go");
        cardData.selectedColorCategoryId = wantToGoCategory?.id ?? _userColorCategories.first.id;
      } else {
        cardData.selectedColorCategoryId = null;
      }
      print("Provider (_applyDefaultsToCard): Applied basic defaults due to missing prefs. Card ID: ${cardData.id.substring(cardData.id.length-4)}");
      return;
    }
    
    String? lastUsedCategoryId = _prefs!.getString(AppConstants.lastUsedCategoryKey);
    String? lastUsedColorCategoryId = _prefs!.getString(AppConstants.lastUsedColorCategoryKey);
    List<String>? lastUsedOtherCategoryIds = _prefs!.getStringList(AppConstants.lastUsedOtherCategoriesKey);

    // --- Text Category Defaulting ---
    if (isFirstCard) {
      // For the very first card: Use preference, then "Restaurant", then first available, then null.
      if (lastUsedCategoryId != null && _userCategories.any((cat) => cat.id == lastUsedCategoryId)) {
        cardData.selectedCategoryId = lastUsedCategoryId;
        print("Provider (First Card): Applied PREFERRED category ID: $lastUsedCategoryId to card ${cardData.id.substring(cardData.id.length-4)}");
      } else {
        final restaurantCategory = _userCategories.firstWhereOrNull((cat) => cat.name.toLowerCase() == "restaurant");
        if (restaurantCategory != null) {
          cardData.selectedCategoryId = restaurantCategory.id;
          print("Provider (First Card): Applied 'Restaurant' category ID: ${restaurantCategory.id} to card ${cardData.id.substring(cardData.id.length-4)}");
        } else if (_userCategories.isNotEmpty) {
          cardData.selectedCategoryId = _userCategories.first.id;
          print("Provider (First Card): Applied FIRST AVAILABLE category ID: ${_userCategories.first.id} to card ${cardData.id.substring(cardData.id.length-4)}");
        } else {
          cardData.selectedCategoryId = null;
          print("Provider (First Card): No categories available for card ${cardData.id.substring(cardData.id.length-4)}");
        }
      }
    } else {
      // For subsequent cards: Copy from the previous card.
      if (_experienceCards.isNotEmpty) { // Should always be true if !isFirstCard
        cardData.selectedCategoryId = _experienceCards.last.selectedCategoryId;
        print("Provider (Subsequent Card): Copied category ID '${cardData.selectedCategoryId}' from previous card to card ${cardData.id.substring(cardData.id.length-4)}");
      } else {
         // This case should ideally not be reached if logic is correct.
         // Fallback to first card logic if somehow it's not the first card but list is empty.
         _applyDefaultsToCard(cardData, isFirstCard: true);
         print("Provider (Subsequent Card - UNEXPECTED FALLBACK): Fallback to first card logic for card ${cardData.id.substring(cardData.id.length-4)}");
         return; // Avoid double printing for color category in this specific fallback
      }
    }

    // --- Color Category Defaulting ---
    if (isFirstCard) {
      // For the very first card: Use preference, then "Want to go", then first available, then null.
      if (lastUsedColorCategoryId != null && _userColorCategories.any((cat) => cat.id == lastUsedColorCategoryId)) {
        cardData.selectedColorCategoryId = lastUsedColorCategoryId;
        print("Provider (First Card): Applied PREFERRED color category ID: $lastUsedColorCategoryId to card ${cardData.id.substring(cardData.id.length-4)}");
      } else {
        final wantToGoCategory = _userColorCategories.firstWhereOrNull((cat) => cat.name.toLowerCase() == "want to go");
        if (wantToGoCategory != null) {
          cardData.selectedColorCategoryId = wantToGoCategory.id;
          print("Provider (First Card): Applied 'Want to go' color category ID: ${wantToGoCategory.id} to card ${cardData.id.substring(cardData.id.length-4)}");
        } else if (_userColorCategories.isNotEmpty) {
          cardData.selectedColorCategoryId = _userColorCategories.first.id;
          print("Provider (First Card): Applied FIRST AVAILABLE color category ID: ${_userColorCategories.first.id} to card ${cardData.id.substring(cardData.id.length-4)}");
        } else {
          cardData.selectedColorCategoryId = null;
          print("Provider (First Card): No color categories available for card ${cardData.id.substring(cardData.id.length-4)}");
        }
      }
    } else {
      // For subsequent cards: Copy from the previous card.
      if (_experienceCards.isNotEmpty) { // Should always be true if !isFirstCard
        cardData.selectedColorCategoryId = _experienceCards.last.selectedColorCategoryId;
        print("Provider (Subsequent Card): Copied color category ID '${cardData.selectedColorCategoryId}' from previous card to card ${cardData.id.substring(cardData.id.length-4)}");
        
        // ADDED: Copy 'Other Categories' as well
        cardData.selectedOtherCategoryIds = List<String>.from(_experienceCards.last.selectedOtherCategoryIds);
        print("Provider (Subsequent Card): Copied other category IDs from previous card to card ${cardData.id.substring(cardData.id.length-4)}");
      } 
      // No else needed here as the text category fallback above would have handled the unexpected case.
    }

    // --- Other Categories Defaulting (for first card) ---
    if (isFirstCard) {
      if (lastUsedOtherCategoryIds != null) {
        final validOtherIds = lastUsedOtherCategoryIds
            .where((id) => _userCategories.any((cat) => cat.id == id))
            .toList();
        cardData.selectedOtherCategoryIds = validOtherIds;
        print("Provider (First Card): Applied PREFERRED other category IDs: $validOtherIds to card ${cardData.id.substring(cardData.id.length - 4)}");
      }
    }
  }

  void addExperienceCard() {
    final newCard = ExperienceCardData();
    final bool isFirstCardBeingAdded = _experienceCards.isEmpty;
    
    // Apply defaults based on whether it's the first card or a subsequent one.
    _applyDefaultsToCard(newCard, isFirstCard: isFirstCardBeingAdded);
    
    _experienceCards.add(newCard);
    print("ReceiveShareProvider: addExperienceCard. Cards count: ${_experienceCards.length}. New card ID: ${newCard.id.substring(newCard.id.length - 4)}. IsFirstCard: $isFirstCardBeingAdded. BEFORE notifyListeners.");
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
      targetCard.selectedCategoryId = selectedExperience.categoryId;
      targetCard.selectedColorCategoryId = selectedExperience.colorCategoryId;
      targetCard.selectedOtherCategoryIds = List<String>.from(selectedExperience.otherCategories);
      targetCard.yelpUrlController.text = selectedExperience.yelpUrl ?? '';
      targetCard.websiteController.text = selectedExperience.website ?? '';
      targetCard.notesController.text =
          selectedExperience.additionalNotes ?? '';
      // Clear search text as location is now set
      targetCard.searchController.clear();
      // Ensure location is enabled
      targetCard.locationEnabled.value = true;
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
  void updateCardTextCategory(String cardId, String? newTextCategoryId) {
    // Allow null to clear
    final index = _experienceCards.indexWhere((card) => card.id == cardId);
    if (index != -1) {
      if (_experienceCards[index].selectedCategoryId != newTextCategoryId) {
        _experienceCards[index].selectedCategoryId = newTextCategoryId;
        print(
            "Provider: Updated text category for card $cardId to $newTextCategoryId");
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
