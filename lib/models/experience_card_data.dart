import 'package:flutter/material.dart';

import '../config/colors.dart';
import '../models/experience.dart';

/// Enum to track the source of the shared content for an experience card.
enum ShareType {
  none,
  yelp,
  maps,
  instagram,
  genericUrl,
  image,
  video,
  file,
}

/// Data class to hold the state of each experience card when composing saves.
class ExperienceCardData {
  /// Form controllers
  final TextEditingController titleController = TextEditingController();
  final TextEditingController yelpUrlController = TextEditingController();
  final TextEditingController websiteController = TextEditingController();
  final TextEditingController searchController = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  final TextEditingController notesController = TextEditingController();

  /// Form key
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  /// Focus nodes
  final FocusNode titleFocusNode = FocusNode();

  /// Category selection
  String? selectedCategoryId;

  /// Rating placeholder for potential integrations.
  double rating = 0.0;

  /// Location selection
  Location? selectedLocation;
  Location? location;
  bool isSelectingLocation = false;
  ValueNotifier<bool> locationEnabled = ValueNotifier<bool>(true);
  List<Map<String, dynamic>> searchResults = [];

  /// State variable for card expansion UI
  bool isExpanded = true;

  /// Unique identifier for this card
  final String id = DateTime.now().millisecondsSinceEpoch.toString();

  /// State for preview rebuilding
  String? placeIdForPreview;

  /// Track the original source of the shared content
  ShareType originalShareType = ShareType.none;

  /// ID of the existing experience if this card represents one
  String? existingExperienceId;

  /// Selected Color Category ID
  String? selectedColorCategoryId;
  /// Whether this experience should remain private (default public)
  bool isPrivate = false;
  /// Background color for the card UI.
  final Color backgroundColor = AppColors.backgroundColor;

  /// Selected IDs for "other" categories
  List<String> selectedOtherCategoryIds = [];
  /// Selected IDs for "other" color categories
  List<String> selectedOtherColorCategoryIds = [];

  ExperienceCardData();

  /// Dispose resources tied to the card instance.
  void dispose() {
    titleController.dispose();
    yelpUrlController.dispose();
    websiteController.dispose();
    searchController.dispose();
    locationController.dispose();
    notesController.dispose();
    titleFocusNode.dispose();
    locationEnabled.dispose();
  }
}
