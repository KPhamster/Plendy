import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/color_category.dart';
import '../models/experience.dart';
import '../models/experience_card_data.dart';
import '../models/shared_media_item.dart';
import '../models/user_category.dart';
import '../services/category_ordering_service.dart';
import '../services/experience_service.dart';
import '../services/google_maps_service.dart';
import '../widgets/select_saved_experience_modal_content.dart';
import '../screens/location_picker_screen.dart';
import '../screens/receive_share/widgets/experience_card_form.dart';

class SaveToExperiencesModal extends StatefulWidget {
  const SaveToExperiencesModal({
    super.key,
    required this.initialExperience,
    required this.mediaUrl,
  });

  final Experience initialExperience;
  final String mediaUrl;

  @override
  State<SaveToExperiencesModal> createState() => _SaveToExperiencesModalState();
}

class _SaveToExperiencesModalState extends State<SaveToExperiencesModal> {
  final ExperienceService _experienceService = ExperienceService();
  final CategoryOrderingService _categoryOrderingService =
      CategoryOrderingService();
  final GoogleMapsService _mapsService = GoogleMapsService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final ValueNotifier<List<UserCategory>> _userCategoriesNotifier =
      ValueNotifier<List<UserCategory>>([]);
  final ValueNotifier<List<ColorCategory>> _userColorCategoriesNotifier =
      ValueNotifier<List<ColorCategory>>([]);

  final List<ExperienceCardData> _experienceCards = [];

  List<UserCategory> _userCategories = [];
  List<ColorCategory> _userColorCategories = [];

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await Future.wait([
        _loadUserCategories(),
        _loadUserColorCategories(),
      ]);
      _addExperienceCard(fromExperience: widget.initialExperience);
    } catch (e) {
      _showSnackBar('Unable to load categories: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    for (final card in _experienceCards) {
      card.dispose();
    }
    _userCategoriesNotifier.dispose();
    _userColorCategoriesNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadUserCategories() async {
    try {
      final result = await _experienceService.getUserCategoriesWithMeta(
        includeSharedEditable: true,
      );
      final ordered = await _categoryOrderingService.orderUserCategories(
        result.categories,
        sharedPermissions: result.sharedPermissions,
      );
      _userCategories = ordered;
      _userCategoriesNotifier.value = ordered;
    } catch (_) {
      _userCategories = [];
      _userCategoriesNotifier.value = [];
    }
  }

  Future<void> _loadUserColorCategories() async {
    try {
      final categories =
          await _experienceService.getUserColorCategories(includeSharedEditable: true);
      final ordered =
          await _categoryOrderingService.orderColorCategories(categories);
      _userColorCategories = ordered;
      _userColorCategoriesNotifier.value = ordered;
    } catch (_) {
      _userColorCategories = [];
      _userColorCategoriesNotifier.value = [];
    }
  }

  void _addExperienceCard({Experience? fromExperience}) {
    final card = ExperienceCardData();

    if (fromExperience != null) {
      _applyExperienceToCard(card, fromExperience);
    } else if (_experienceCards.isNotEmpty) {
      _copyDefaultsFromPreviousCard(card, _experienceCards.last);
    } else {
      _applyCategoryDefaults(card);
    }

    setState(() {
      _experienceCards.add(card);
    });
  }

  void _copyDefaultsFromPreviousCard(
      ExperienceCardData card, ExperienceCardData previous) {
    card.selectedCategoryId = previous.selectedCategoryId;
    card.selectedColorCategoryId = previous.selectedColorCategoryId;
    card.selectedOtherCategoryIds =
        List<String>.from(previous.selectedOtherCategoryIds);
    card.locationEnabled.value = previous.locationEnabled.value;
    _applyCategoryDefaults(card);
  }

  void _applyCategoryDefaults(ExperienceCardData card) {
    if (card.selectedCategoryId == null && _userCategories.isNotEmpty) {
      card.selectedCategoryId = _userCategories.first.id;
    }
    if (card.selectedColorCategoryId == null &&
        _userColorCategories.isNotEmpty) {
      card.selectedColorCategoryId = _userColorCategories.first.id;
    }
  }

  void _applyExperienceToCard(ExperienceCardData card, Experience experience) {
    card.titleController.text = experience.name;
    card.notesController.text = experience.additionalNotes ?? '';
    card.websiteController.text = experience.website ?? '';
    card.yelpUrlController.text = experience.yelpUrl ?? '';
    card.selectedLocation = experience.location;
    card.locationEnabled.value = true;
    card.selectedOtherCategoryIds =
        List<String>.from(experience.otherCategories);

    if (experience.categoryId?.isNotEmpty ?? false) {
      card.selectedCategoryId = experience.categoryId;
    }

    if (experience.colorCategoryId?.isNotEmpty ?? false) {
      card.selectedColorCategoryId = experience.colorCategoryId;
    }

    _applyCategoryDefaults(card);
  }

  void _removeExperienceCard(ExperienceCardData card) {
    if (_experienceCards.length == 1) return;
    setState(() {
      _experienceCards.remove(card);
    });
    card.dispose();
  }

  Future<void> _showLocationPicker(ExperienceCardData card) async {
    FocusScope.of(context).unfocus();
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialLocation: card.selectedLocation,
          onLocationSelected: (_) {},
          businessNameHint: card.titleController.text.isNotEmpty
              ? card.titleController.text
              : null,
        ),
      ),
    );

    if (result == null) return;

    final Location selectedLocation =
        result is Map ? result['location'] as Location : result as Location;

    setState(() {
      card.selectedLocation = selectedLocation;
      card.searchController.text = selectedLocation.address ?? '';
      if (card.titleController.text.trim().isEmpty) {
        card.titleController.text = selectedLocation.getPlaceName();
      }
      if ((selectedLocation.website ?? '').isNotEmpty &&
          card.websiteController.text.trim().isEmpty) {
        card.websiteController.text = selectedLocation.website!;
      }
    });
  }

  Future<void> _selectSavedExperienceForCard(ExperienceCardData card) async {
    FocusScope.of(context).unfocus();

    final selectedExperience = await showModalBottomSheet<Experience>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, controller) {
            return SelectSavedExperienceModalContent(
              scrollController: controller,
            );
          },
        );
      },
    );

    if (selectedExperience == null) return;

    setState(() {
      card.existingExperienceId = selectedExperience.id;
      card.titleController.text = selectedExperience.name;
      card.notesController.text = selectedExperience.additionalNotes ?? '';
      card.websiteController.text = selectedExperience.website ?? '';
      card.yelpUrlController.text = selectedExperience.yelpUrl ?? '';
      card.selectedCategoryId = selectedExperience.categoryId ??
          card.selectedCategoryId ??
          (_userCategories.isNotEmpty ? _userCategories.first.id : null);
      card.selectedColorCategoryId = selectedExperience.colorCategoryId ??
          card.selectedColorCategoryId ??
          (_userColorCategories.isNotEmpty ? _userColorCategories.first.id : null);
      card.selectedOtherCategoryIds =
          List<String>.from(selectedExperience.otherCategories);
      card.selectedLocation = selectedExperience.location;
      card.locationEnabled.value = true;
    });
  }

  Future<void> _handleExperienceCardFormUpdate({
    required String cardId,
    bool refreshCategories = false,
    String? newCategoryName,
    String? selectedColorCategoryId,
    String? newTitleFromCard, // currently unused but preserved for parity
  }) async {
    final card =
        _experienceCards.firstWhereOrNull((element) => element.id == cardId);
    if (card == null) return;

    if (selectedColorCategoryId != null) {
      setState(() {
        card.selectedColorCategoryId = selectedColorCategoryId;
      });
      return;
    }

    if (refreshCategories) {
      await Future.wait([
        _loadUserCategories(),
        _loadUserColorCategories(),
      ]);
      if (newCategoryName != null) {
        final match = _userCategories.firstWhereOrNull(
          (cat) => cat.name.toLowerCase() == newCategoryName.toLowerCase(),
        );
        if (match != null) {
          setState(() {
            card.selectedCategoryId = match.id;
          });
        }
      }
      return;
    }

    // Reserved for future duplicate detection using newTitleFromCard.
    newTitleFromCard;
  }

  Future<void> _saveExperiences() async {
    if (_isSaving) return;

    if (_experienceCards.isEmpty) {
      _showSnackBar('Add at least one experience to save.');
      return;
    }

    for (final card in _experienceCards) {
      if (!card.formKey.currentState!.validate()) {
        _showSnackBar('Please fix validation errors before saving.');
        return;
      }
      if (card.selectedCategoryId == null || card.selectedCategoryId!.isEmpty) {
        _showSnackBar('Select a category for "${card.titleController.text}".');
        return;
      }
      if (card.locationEnabled.value && card.selectedLocation == null) {
        _showSnackBar(
            'Select a location for "${card.titleController.text}".');
        return;
      }
    }

    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      _showSnackBar('Please sign in to save experiences.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final trimmedMediaUrl = widget.mediaUrl.trim();
      final mediaItemId =
          await _ensureSharedMediaItem(trimmedMediaUrl, ownerUserId: userId);

      int createdCount = 0;
      int updatedCount = 0;
      final List<String> linkedExperienceIds = [];
      final DateTime now = DateTime.now();

      for (final card in _experienceCards) {
        final bool isUpdate =
            card.existingExperienceId != null && card.existingExperienceId!.isNotEmpty;
        final String title = card.titleController.text.trim();
        final String notes = card.notesController.text.trim();
        final String yelpUrl = card.yelpUrlController.text.trim();
        final String website = card.websiteController.text.trim();
        final Location location = (card.locationEnabled.value &&
                card.selectedLocation != null)
            ? card.selectedLocation!
            : const Location(
                latitude: 0,
                longitude: 0,
                address: 'No location specified',
              );

        if (isUpdate) {
          final existing =
              await _experienceService.getExperience(card.existingExperienceId!);
          if (existing == null) {
            _showSnackBar('Could not find "${card.titleController.text}".');
            continue;
          }

          final List<String> updatedMediaIds =
              List<String>.from(existing.sharedMediaItemIds);
          if (mediaItemId != null && !updatedMediaIds.contains(mediaItemId)) {
            updatedMediaIds.add(mediaItemId);
          }

          final Experience updatedExperience = existing.copyWith(
            name: title,
            description:
                notes.isNotEmpty ? notes : existing.description,
            location: location,
            categoryId: card.selectedCategoryId,
            yelpUrl: yelpUrl.isNotEmpty ? yelpUrl : null,
            website: website.isNotEmpty ? website : null,
            additionalNotes:
                notes.isNotEmpty ? notes : existing.additionalNotes,
            sharedMediaItemIds: updatedMediaIds,
            colorCategoryId: card.selectedColorCategoryId,
            otherCategories: card.selectedOtherCategoryIds,
            editorUserIds: existing.editorUserIds.contains(userId)
                ? existing.editorUserIds
                : [...existing.editorUserIds, userId],
          );

          await _experienceService.updateExperience(updatedExperience);
          updatedCount++;
          linkedExperienceIds.add(updatedExperience.id);
        } else {
          final Experience newExperience = Experience(
            id: '',
            name: title,
            description:
                notes.isNotEmpty ? notes : 'Saved from Discovery',
            location: location,
            categoryId: card.selectedCategoryId,
            yelpUrl: yelpUrl.isNotEmpty ? yelpUrl : null,
            yelpRating: 0,
            yelpReviewCount: 0,
            googleUrl: null,
            googleRating: 0,
            googleReviewCount: 0,
            plendyRating: 0,
            plendyReviewCount: 0,
            imageUrls: const [],
            reelIds: const [],
            followerIds: const [],
            rating: 0,
            createdAt: now,
            updatedAt: now,
            website: website.isNotEmpty ? website : null,
            phoneNumber: null,
            openingHours: null,
            tags: const [],
            priceRange: null,
            sharedMediaItemIds:
                mediaItemId != null ? <String>[mediaItemId] : const [],
            sharedMediaType: 'discovery',
            additionalNotes: notes.isNotEmpty ? notes : null,
            editorUserIds: [userId],
            colorCategoryId: card.selectedColorCategoryId,
            otherCategories: card.selectedOtherCategoryIds,
            categoryIconDenorm: null,
            colorHexDenorm: null,
            createdBy: userId,
          );

          final String newId =
              await _experienceService.createExperience(newExperience);
          createdCount++;
          linkedExperienceIds.add(newId);
        }
      }

      if (mediaItemId != null) {
        for (final experienceId in linkedExperienceIds) {
          await _experienceService.addExperienceLinkToMediaItem(
              mediaItemId, experienceId);
        }
      }

      final resultMessage =
          _buildResultMessage(createdCount, updatedCount);

      if (!mounted) return;

      Navigator.of(context).pop(resultMessage);
    } catch (e) {
      _showSnackBar('Failed to save experiences: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<String?> _ensureSharedMediaItem(
      String url, {
        required String ownerUserId,
      }) async {
    if (url.isEmpty) return null;

    final existing =
        await _experienceService.findSharedMediaItemByPath(url);
    if (existing != null) {
      return existing.id;
    }

    final SharedMediaItem newItem = SharedMediaItem(
      id: '',
      path: url,
      createdAt: DateTime.now(),
      ownerUserId: ownerUserId,
      experienceIds: const [],
      isTiktokPhoto: null,
    );
    return _experienceService.createSharedMediaItem(newItem);
  }

  String _buildResultMessage(int created, int updated) {
    if (created == 0 && updated == 0) {
      return 'No changes saved.';
    }
    final List<String> segments = [];
    if (created > 0) {
      segments.add('$created experience(s) created');
    }
    if (updated > 0) {
      segments.add('$updated updated');
    }
    return segments.join(', ') + '.';
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.95,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Material(
          color: Colors.white,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      'Save to Experience(s)',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildExperienceCardsSection(),
              ),
              _buildBottomBar(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExperienceCardsSection() {
    if (_experienceCards.isEmpty) {
      return const Center(
        child: Text('No experience cards available.'),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _experienceCards.length,
            itemBuilder: (context, index) {
              final card = _experienceCards[index];
              return ExperienceCardForm(
                key: ValueKey(card.id),
                cardData: card,
                isFirstCard: index == 0,
                canRemove: _experienceCards.length > 1,
                userCategoriesNotifier: _userCategoriesNotifier,
                userColorCategoriesNotifier: _userColorCategoriesNotifier,
                onRemove: _removeExperienceCard,
                onLocationSelect: _showLocationPicker,
                onSelectSavedExperience: _selectSavedExperienceForCard,
                onUpdate: ({
                  bool refreshCategories = false,
                  String? newCategoryName,
                  String? selectedColorCategoryId,
                  String? newTitleFromCard,
                }) {
                  _handleExperienceCardFormUpdate(
                    cardId: card.id,
                    refreshCategories: refreshCategories,
                    newCategoryName: newCategoryName,
                    selectedColorCategoryId: selectedColorCategoryId,
                    newTitleFromCard: newTitleFromCard,
                  );
                },
                formKey: card.formKey,
              );
            },
          ),
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton.icon(
              onPressed: () => _addExperienceCard(),
              icon: const Icon(Icons.add),
              label: const Text('Add Another Experience'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveExperiences,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(_isSaving ? 'Saving...' : 'Save'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
