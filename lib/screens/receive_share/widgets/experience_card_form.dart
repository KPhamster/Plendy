import 'package:flutter/material.dart';
import 'package:plendy/screens/receive_share_screen.dart'; // For ExperienceCardData
import 'package:plendy/models/experience.dart'; // For ExperienceType and Location
import 'package:plendy/screens/location_picker_screen.dart'; // For Location Picker
import 'package:plendy/services/google_maps_service.dart'; // If needed for location updates
import 'package:plendy/widgets/google_maps_widget.dart'; // If needed

// Define necessary callbacks
typedef OnRemoveCallback = void Function(ExperienceCardData card);
typedef OnLocationSelectCallback = Future<void> Function(
    ExperienceCardData card);
typedef OnUpdateCallback = void
    Function(); // Generic callback to trigger setState in parent

class ExperienceCardForm extends StatefulWidget {
  final ExperienceCardData cardData;
  final bool isFirstCard; // To potentially hide remove button
  final bool canRemove; // Explicit flag to control remove button visibility
  final OnRemoveCallback onRemove;
  final OnLocationSelectCallback onLocationSelect;
  final OnUpdateCallback onUpdate; // Callback to parent
  final GlobalKey<FormState> formKey; // Pass form key down

  const ExperienceCardForm({
    super.key,
    required this.cardData,
    required this.isFirstCard,
    required this.canRemove,
    required this.onRemove,
    required this.onLocationSelect,
    required this.onUpdate,
    required this.formKey,
  });

  @override
  State<ExperienceCardForm> createState() => _ExperienceCardFormState();
}

class _ExperienceCardFormState extends State<ExperienceCardForm> {
  // We will move the logic from _buildExperienceCard here.
  // State variables previously in ExperienceCardData might move here too,
  // or be accessed via widget.cardData.

  late TextEditingController _titleController;
  late TextEditingController _yelpUrlController;
  late TextEditingController _websiteController;
  late TextEditingController
      _searchController; // For location search within the form if needed
  late FocusNode _titleFocusNode;

  bool _isExpanded = true;
  bool _locationEnabled = true;
  Location? _selectedLocation;
  ExperienceType _selectedType = ExperienceType.restaurant;

  // Service needed for location updates if interaction happens within the form
  final GoogleMapsService _mapsService = GoogleMapsService();

  @override
  void initState() {
    super.initState();
    // Initialize controllers and state from widget.cardData
    _titleController = widget.cardData.titleController;
    _yelpUrlController = widget.cardData.yelpUrlController;
    _websiteController = widget.cardData.websiteController;
    _searchController =
        widget.cardData.searchController; // Location search controller
    _titleFocusNode = widget.cardData.titleFocusNode;

    _isExpanded = widget.cardData.isExpanded;
    _locationEnabled = widget.cardData.locationEnabled;
    _selectedLocation = widget.cardData.selectedLocation;
    _selectedType = widget.cardData.selectedType;

    // Add listeners to update the parent's state if necessary
    _titleController.addListener(_handleControllerChange);
    _yelpUrlController.addListener(_handleControllerChange);
    _websiteController.addListener(_handleControllerChange);
    _searchController.addListener(_handleControllerChange);
  }

  void _handleControllerChange() {
    // Update the underlying cardData object
    widget.cardData.selectedType = _selectedType;
    widget.cardData.selectedLocation = _selectedLocation;
    widget.cardData.isExpanded = _isExpanded;
    widget.cardData.locationEnabled = _locationEnabled;
    // Notify the parent widget that something changed, so it can rebuild if needed
    widget.onUpdate();
    // Trigger rebuild of this widget if suffix icon state depends on controller
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    // Remove listeners
    _titleController.removeListener(_handleControllerChange);
    _yelpUrlController.removeListener(_handleControllerChange);
    _websiteController.removeListener(_handleControllerChange);
    _searchController.removeListener(_handleControllerChange);

    // Note: Controllers and FocusNodes are managed by ExperienceCardData
    // and should be disposed there when the cardData is disposed.
    super.dispose();
  }

  // Helper method moved from ReceiveShareScreen
  bool _isValidUrl(String text) {
    return text.startsWith('http://') ||
        text.startsWith('https://') ||
        text.startsWith('www.') ||
        text.contains('yelp.to/') ||
        text.contains('goo.gl/');
  }

  // Build method - Logic from _buildExperienceCard goes here
  @override
  Widget build(BuildContext context) {
    // The UI structure from _buildExperienceCard will be implemented here,
    // using state variables like _isExpanded, _selectedLocation, etc.,
    // and calling callbacks like widget.onRemove, widget.onLocationSelect.

    return Card(
      margin: EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 2,
      child: Form(
        key: widget.formKey, // Use the passed form key
        child: Column(
          children: [
            // Header row with expand/collapse and delete functionality
            InkWell(
              onTap: () {
                setState(() {
                  _isExpanded = !_isExpanded;
                  widget.cardData.isExpanded = _isExpanded; // Update data model
                  // Unfocus any active fields when collapsing
                  if (!_isExpanded) {
                    FocusScope.of(context).unfocus();
                  }
                });
                widget.onUpdate(); // Notify parent
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      _isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.blue,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _titleController.text.isNotEmpty
                            ? _titleController.text
                            : "New Experience",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    // Use the passed flag to control delete button
                    if (widget.canRemove)
                      IconButton(
                        icon:
                            Icon(Icons.delete_outline, color: Colors.red[400]),
                        onPressed: () => widget.onRemove(widget.cardData),
                        tooltip: 'Remove experience',
                      ),
                  ],
                ),
              ),
            ),

            // Expandable content
            if (_isExpanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Button to choose saved experience
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        icon: Icon(Icons.bookmark_outline),
                        label: Text('Choose a saved experience'),
                        onPressed: null, // No functionality yet
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue,
                          padding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                    SizedBox(height: 12),

                    // Location selection with preview
                    GestureDetector(
                      // Call the parent's location selection logic
                      onTap: (_locationEnabled)
                          ? () => widget.onLocationSelect(widget.cardData)
                          : null,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: _locationEnabled
                                  ? Colors.grey
                                  : Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(4),
                          color: Colors.transparent,
                        ),
                        padding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        child: Row(
                          children: [
                            Icon(Icons.location_on,
                                color: _locationEnabled
                                    ? Colors.grey[600]
                                    : Colors.grey[400]),
                            SizedBox(width: 12),
                            Expanded(
                              child: _selectedLocation != null
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Place name in bold
                                        Text(
                                          _selectedLocation!.getPlaceName(),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: _locationEnabled
                                                ? Colors.black
                                                : Colors.grey[500],
                                          ),
                                        ),
                                        // Address
                                        Text(
                                          _selectedLocation!.address ??
                                              'No address',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: _locationEnabled
                                                ? Colors.black87
                                                : Colors.grey[500],
                                          ),
                                        ),
                                      ],
                                    )
                                  : Text(
                                      'Select location',
                                      style: TextStyle(
                                          color: _locationEnabled
                                              ? Colors.grey[600]
                                              : Colors.grey[400]),
                                    ),
                            ),
                            // Toggle switch inside the location field
                            Transform.scale(
                              scale: 0.8,
                              child: Switch(
                                value: _locationEnabled,
                                onChanged: (value) {
                                  setState(() {
                                    _locationEnabled = value;
                                    widget.cardData.locationEnabled =
                                        value; // Update model
                                  });
                                  widget.onUpdate(); // Notify parent
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
                      controller: _titleController,
                      focusNode: _titleFocusNode,
                      decoration: InputDecoration(
                        labelText: 'Experience Title',
                        hintText: 'Enter title',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.title),
                        suffixIcon: _titleController.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  setState(() {
                                    _titleController.clear();
                                  });
                                  widget
                                      .onUpdate(); // Notify parent title changed
                                },
                              )
                            : null,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a title';
                        }
                        return null;
                      },
                      onChanged: (value) {
                        // Trigger a rebuild to show/hide the clear button
                        // and update the card title when collapsed
                        _handleControllerChange(); // Use central handler
                      },
                    ),
                    SizedBox(height: 16),

                    // Experience type selection
                    DropdownButtonFormField<ExperienceType>(
                      value: _selectedType,
                      decoration: InputDecoration(
                        labelText: 'Experience Type',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.category),
                      ),
                      items: ExperienceType.values.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(type.displayName),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedType = value;
                            widget.cardData.selectedType =
                                value; // Update model
                          });
                          widget.onUpdate(); // Notify parent
                        }
                      },
                    ),
                    SizedBox(height: 16),

                    // Yelp URL
                    TextFormField(
                      controller: _yelpUrlController,
                      decoration: InputDecoration(
                        labelText: 'Yelp URL (optional)',
                        hintText: 'https://yelp.com/...',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.restaurant_menu),
                        suffixIcon: _yelpUrlController.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  setState(() {
                                    _yelpUrlController.clear();
                                  });
                                  _handleControllerChange();
                                },
                              )
                            : null,
                      ),
                      keyboardType: TextInputType.url,
                      validator: (value) {
                        if (value != null && value.isNotEmpty) {
                          if (!_isValidUrl(value)) {
                            return 'Please enter a valid URL';
                          }
                        }
                        return null;
                      },
                      onChanged: (value) => _handleControllerChange(),
                    ),
                    SizedBox(height: 16),

                    // Official website
                    TextFormField(
                      controller: _websiteController,
                      decoration: InputDecoration(
                        labelText: 'Official Website (optional)',
                        hintText: 'https://...',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.language),
                        suffixIcon: _websiteController.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  setState(() {
                                    _websiteController.clear();
                                  });
                                  _handleControllerChange();
                                },
                              )
                            : null,
                      ),
                      keyboardType: TextInputType.url,
                      validator: (value) {
                        if (value != null && value.isNotEmpty) {
                          if (!_isValidUrl(value)) {
                            return 'Please enter a valid URL';
                          }
                        }
                        return null;
                      },
                      onChanged: (value) => _handleControllerChange(),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
