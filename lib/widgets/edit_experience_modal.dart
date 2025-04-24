import 'package:flutter/material.dart';
import 'package:plendy/models/experience.dart';
import 'package:plendy/models/user_category.dart';
import 'package:plendy/screens/receive_share_screen.dart'
    show ExperienceCardData; // Re-use data structure
import 'package:plendy/screens/receive_share/widgets/experience_card_form.dart'; // For field structure reference (or reuse fields)
import 'package:font_awesome_flutter/font_awesome_flutter.dart'; // For icons
import 'package:plendy/services/google_maps_service.dart'; // For location picker interaction

class EditExperienceModal extends StatefulWidget {
  final Experience experience;
  final List<UserCategory> userCategories;

  const EditExperienceModal({
    super.key,
    required this.experience,
    required this.userCategories,
  });

  @override
  State<EditExperienceModal> createState() => _EditExperienceModalState();
}

class _EditExperienceModalState extends State<EditExperienceModal> {
  // Use ExperienceCardData to manage form state internally
  late ExperienceCardData _cardData;
  final _formKey = GlobalKey<FormState>();
  final GoogleMapsService _mapsService =
      GoogleMapsService(); // If needed for picker

  @override
  void initState() {
    super.initState();
    // Initialize cardData with values from the existing experience
    _cardData = ExperienceCardData(); // Create a new instance
    _cardData.existingExperienceId =
        widget.experience.id; // Keep track of original ID
    _cardData.titleController.text = widget.experience.name;
    _cardData.yelpUrlController.text = widget.experience.yelpUrl ?? '';
    _cardData.websiteController.text = widget.experience.website ?? '';
    _cardData.notesController.text = widget.experience.additionalNotes ?? '';
    _cardData.selectedcategory = widget.experience.category;
    _cardData.selectedLocation = widget.experience.location;
    _cardData.locationEnabled = widget.experience.location.latitude != 0.0 ||
        widget.experience.location.longitude !=
            0.0; // Check if location is default

    // If location exists, pre-fill searchController for display consistency (optional)
    if (_cardData.selectedLocation?.address != null) {
      _cardData.searchController.text = _cardData.selectedLocation!.address!;
    }
  }

  @override
  void dispose() {
    // Dispose controllers managed by _cardData
    _cardData.dispose();
    super.dispose();
  }

  // Helper method moved from ReceiveShareScreen's form widget
  bool _isValidUrl(String text) {
    final uri = Uri.tryParse(text);
    return uri != null && (uri.isScheme('http') || uri.isScheme('https'));
  }

  // --- Location Picker Logic (Adapted from ReceiveShareScreen) ---
  Future<void> _showLocationPicker() async {
    FocusScope.of(context).unfocus();

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          initialLocation: _cardData.selectedLocation,
          onLocationSelected: (location) {}, // Dummy callback
          // Pass name hint if desired, potentially from titleController
          businessNameHint: _cardData.titleController.text,
        ),
      ),
    );

    if (result != null && mounted) {
      Future.microtask(() => FocusScope.of(context).unfocus());

      final Location selectedLocation =
          result is Map ? result['location'] : result as Location;

      // Fetch details for the *newly selected* location to get address/website etc.
      try {
        if (selectedLocation.placeId == null ||
            selectedLocation.placeId!.isEmpty) {
          print(
              "WARN: Location picked has no Place ID. Performing basic update.");
          setState(() {
            _cardData.selectedLocation = selectedLocation;
            _cardData.searchController.text =
                selectedLocation.address ?? 'Selected Location';
            _cardData.locationEnabled = true; // Assume enabled if picked
          });
          return;
        }

        Location detailedLocation =
            await _mapsService.getPlaceDetails(selectedLocation.placeId!);
        print(
            "Edit Modal: Fetched details for picked location: ${detailedLocation.displayName}");

        // Update cardData state
        setState(() {
          _cardData.selectedLocation = detailedLocation;
          _cardData.titleController.text = detailedLocation
              .getPlaceName(); // Update title? Discuss if needed
          _cardData.websiteController.text = detailedLocation.website ??
              _cardData.websiteController
                  .text; // Keep existing website if new one is null? Or override?
          _cardData.searchController.text =
              detailedLocation.address ?? ''; // For display in location field
          _cardData.locationEnabled = true;
        });
      } catch (e) {
        print("Error getting place details after picking location: $e");
        // Fallback: Update with the basic location selected if details fetch fails
        setState(() {
          _cardData.selectedLocation = selectedLocation;
          _cardData.searchController.text =
              selectedLocation.address ?? 'Selected Location';
          _cardData.locationEnabled = true;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating location details: $e')),
          );
        }
      }
    }
  }
  // --- End Location Picker Logic ---

  // --- Category Selection Logic (Adapted from ExperienceCardForm) ---
  Future<void> _showCategorieselectionDialog() async {
    FocusScope.of(context).unfocus(); // Dismiss keyboard

    // Filter out Add/Edit options if they exist in the list passed from parent
    final displayCategories =
        widget.userCategories; // Assume parent passes clean list

    final String? selectedValue = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight:
                    MediaQuery.of(context).size.height * 0.6), // Limit height
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text('Select Category',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: displayCategories.length,
                    itemBuilder: (context, index) {
                      final category = displayCategories[index];
                      final bool isSelected =
                          category.name == _cardData.selectedcategory;
                      return ListTile(
                        leading: Text(category.icon,
                            style: const TextStyle(fontSize: 20)),
                        title: Text(category.name),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: Colors.blue)
                            : null,
                        onTap: () {
                          Navigator.pop(
                              context, category.name); // Return category name
                        },
                        visualDensity: VisualDensity.compact,
                      );
                    },
                  ),
                ),
                // Don't include Add/Edit buttons within the edit modal's category selector
              ],
            ),
          ),
        );
      },
    );

    // Handle the dialog result
    if (selectedValue != null) {
      if (_cardData.selectedcategory != selectedValue) {
        setState(() {
          _cardData.selectedcategory = selectedValue;
        });
      }
    }
  }

  // Helper to get category icon
  String _getIconForSelectedCategory() {
    final selectedName = _cardData.selectedcategory;
    if (selectedName == null) return '❓';
    try {
      final matchingCategory = widget.userCategories.firstWhere(
        (category) => category.name == selectedName,
      );
      return matchingCategory.icon;
    } catch (e) {
      return '❓'; // Not found
    }
  }
  // --- End Category Selection Logic ---

  void _saveAndClose() {
    if (_formKey.currentState!.validate()) {
      // Construct the updated Experience object
      final Location locationToSave = (_cardData.locationEnabled &&
              _cardData.selectedLocation != null)
          ? _cardData.selectedLocation!
          : Location(
              latitude: 0.0,
              longitude: 0.0,
              address: 'No location specified'); // Default/disabled location

      final updatedExperience = widget.experience.copyWith(
        name: _cardData.titleController.text.trim(),
        category: _cardData.selectedcategory, // Already a string
        location: locationToSave,
        yelpUrl: _cardData.yelpUrlController.text.trim().isNotEmpty
            ? _cardData.yelpUrlController.text.trim()
            : null,
        website: _cardData.websiteController.text.trim().isNotEmpty
            ? _cardData.websiteController.text.trim()
            : null,
        // Decide how to handle description vs notes
        description: _cardData.notesController.text
            .trim(), // Use notes as description? Or keep separate?
        additionalNotes: _cardData.notesController.text.trim().isNotEmpty
            ? _cardData.notesController.text.trim()
            : null, // Or separate logic
        updatedAt: DateTime.now(), // Update timestamp
        // Keep other fields like sharedMediaPaths, ownerUserId, createdAt etc. from original
      );

      Navigator.of(context).pop(updatedExperience); // Return the updated object
    } else {
      // Show error if form invalid
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fix the errors in the form.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Make modal content scrollable and handle keyboard padding
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min, // Fit content vertically
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Modal Title
              Text(
                'Edit Experience',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),

              // --- Form Fields (Similar to ExperienceCardForm) ---

              // Location selection (using adapted widget/logic)
              GestureDetector(
                onTap: (_cardData.locationEnabled) ? _showLocationPicker : null,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: _cardData.locationEnabled
                            ? Colors.grey
                            : Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.location_on,
                          color: _cardData.locationEnabled
                              ? Colors.grey[600]
                              : Colors.grey[400]),
                      SizedBox(width: 12),
                      Expanded(
                        child: _cardData.selectedLocation != null &&
                                _cardData.selectedLocation!.latitude != 0.0
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _cardData.selectedLocation!
                                        .getPlaceName(), // Use helper
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: _cardData.locationEnabled
                                            ? Colors.black
                                            : Colors.grey[500]),
                                  ),
                                  if (_cardData.selectedLocation!.address !=
                                      null)
                                    Text(
                                      _cardData.selectedLocation!.address!,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: _cardData.locationEnabled
                                              ? Colors.black87
                                              : Colors.grey[500]),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              )
                            : Text(
                                'Select location',
                                style: TextStyle(
                                    color: _cardData.locationEnabled
                                        ? Colors.grey[600]
                                        : Colors.grey[400]),
                              ),
                      ),
                      Transform.scale(
                        // Toggle switch
                        scale: 0.8,
                        child: Switch(
                          value: _cardData.locationEnabled,
                          onChanged: (value) {
                            setState(() {
                              _cardData.locationEnabled = value;
                            });
                          },
                          activeColor: Colors.blue,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16),

              // Experience title
              TextFormField(
                controller: _cardData.titleController,
                decoration: InputDecoration(
                  labelText: 'Experience Title',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),

              // Category Selection Button
              Text('Category',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey[600])),
              const SizedBox(height: 4),
              OutlinedButton(
                onPressed: _showCategorieselectionDialog,
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0)),
                  side: BorderSide(color: Colors.grey),
                  alignment: Alignment.centerLeft,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(_getIconForSelectedCategory(),
                            style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Text(
                          _cardData.selectedcategory ?? 'Select Category',
                          style: TextStyle(
                              color: _cardData.selectedcategory != null
                                  ? Theme.of(context).textTheme.bodyLarge?.color
                                  : Colors.grey[600]),
                        ),
                      ],
                    ),
                    const Icon(Icons.arrow_drop_down, color: Colors.grey),
                  ],
                ),
              ),
              // TODO: Add validation message display if needed
              SizedBox(height: 16),

              // Yelp URL
              TextFormField(
                controller: _cardData.yelpUrlController,
                decoration: InputDecoration(
                  labelText: 'Yelp URL (optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(FontAwesomeIcons.yelp),
                ),
                keyboardType: TextInputType.url,
                validator: (value) {
                  if (value != null &&
                      value.isNotEmpty &&
                      !_isValidUrl(value)) {
                    return 'Please enter a valid URL (http/https)';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),

              // Official website
              TextFormField(
                controller: _cardData.websiteController,
                decoration: InputDecoration(
                  labelText: 'Official Website (optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.language),
                ),
                keyboardType: TextInputType.url,
                validator: (value) {
                  if (value != null &&
                      value.isNotEmpty &&
                      !_isValidUrl(value)) {
                    return 'Please enter a valid URL (http/https)';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),

              // Notes field (using description/additionalNotes)
              TextFormField(
                controller: _cardData.notesController,
                decoration: InputDecoration(
                  labelText: 'Notes (optional)', // Or 'Description'
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.notes),
                  alignLabelWithHint: true,
                ),
                keyboardType: TextInputType.multiline,
                minLines: 3,
                maxLines: null,
              ),
              SizedBox(height: 24), // Space before buttons

              // --- Action Buttons ---
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop(), // Close without saving
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _saveAndClose,
                    child: const Text('Save Changes'),
                    style: ElevatedButton.styleFrom(
                        // backgroundColor: Theme.of(context).primaryColor, // Optional styling
                        // foregroundColor: Colors.white,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 16), // Bottom padding
            ],
          ),
        ),
      ),
    );
  }
}

// Helper extension for Location (if not already defined globally)
// Ensure this is consistent with the one in receive_share_screen.dart
// or move it to the Location model file.
extension LocationNameHelperModal on Location {
  String getPlaceName() {
    if (displayName != null &&
        displayName!.isNotEmpty &&
        !_containsCoordinates(displayName!)) {
      return displayName!;
    }
    if (address != null) {
      final parts = address!.split(',');
      if (parts.isNotEmpty) return parts.first.trim();
    }
    return 'Unnamed Location';
  }

  bool _containsCoordinates(String text) {
    final coordRegex =
        RegExp(r'-?\d+\.\d+ ?, ?-?\d+\.\d+'); // Basic coordinate pattern
    return coordRegex.hasMatch(text);
  }
}

// Required for Location Picker Screen import
class LocationPickerScreen extends StatelessWidget {
  final Location? initialLocation;
  final Function(Location) onLocationSelected;
  final String? businessNameHint;

  const LocationPickerScreen({
    Key? key,
    this.initialLocation,
    required this.onLocationSelected,
    this.businessNameHint,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Replace with your actual LocationPickerScreen implementation
    return Scaffold(
      appBar: AppBar(title: Text("Select Location (Placeholder)")),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            // Simulate selecting a location
            Navigator.pop(
                context,
                Location(
                    latitude: 40.7128,
                    longitude: -74.0060,
                    address: "New York, NY, USA",
                    placeId: "ChIJOwg_06VPwokRYv534QaPC8g",
                    displayName: "New York"));
          },
          child: Text("Select New York (Placeholder)"),
        ),
      ),
    );
  }
}
