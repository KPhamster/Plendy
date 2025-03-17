import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../widgets/google_maps_widget.dart';
import '../models/experience.dart';
import '../services/google_maps_service.dart';

class LocationPickerScreen extends StatefulWidget {
  final Location? initialLocation;
  final Function(Location) onLocationSelected;
  final String title;
  
  const LocationPickerScreen({
    Key? key,
    this.initialLocation,
    required this.onLocationSelected,
    this.title = 'Select Location',
  }) : super(key: key);

  @override
  _LocationPickerScreenState createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final GoogleMapsService _mapsService = GoogleMapsService();
  Location? _selectedLocation;
  List<Map<String, dynamic>> _searchResults = [];
  bool _showSearchResults = false;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  
  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  Future<void> _searchPlaces(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
      });
      return;
    }
    
    setState(() {
      _isSearching = true;
    });
    
    try {
      final results = await _mapsService.searchPlaces(query);
      
      setState(() {
        _searchResults = results;
        _showSearchResults = results.isNotEmpty;
        _isSearching = false;
      });
    } catch (e) {
      print('Error searching places: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error searching places: $e')),
      );
      
      setState(() {
        _isSearching = false;
      });
    }
  }
  
  Future<void> _selectSearchResult(Map<String, dynamic> result) async {
    setState(() {
      _showSearchResults = false;
      _isSearching = true;
    });
    
    try {
      final placeId = result['placeId'];
      final location = await _mapsService.getPlaceDetails(placeId);
      
      if (location != null) {
        setState(() {
          _selectedLocation = location;
          _searchController.text = location.address ?? 'Selected Location';
        });
      }
    } catch (e) {
      print('Error getting place details: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error selecting location: $e')),
      );
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }
  
  Future<void> _onLocationSelected(Location location) async {
    setState(() {
      _selectedLocation = location;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_selectedLocation != null)
            IconButton(
              icon: Icon(Icons.check),
              onPressed: () {
                widget.onLocationSelected(_selectedLocation!);
                Navigator.of(context).pop(_selectedLocation);
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search for a place',
                    border: InputBorder.none,
                    prefixIcon: Icon(Icons.search),
                    suffixIcon: _isSearching 
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                                _searchResults = [];
                                _showSearchResults = false;
                              });
                            },
                          )
                        : null,
                  ),
                  onChanged: _searchPlaces,
                ),
              ),
            ),
          ),
          
          // Search results
          if (_showSearchResults)
            Container(
              constraints: BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final result = _searchResults[index];
                  return ListTile(
                    title: Text(result['description'] ?? 'Unknown Place'),
                    onTap: () => _selectSearchResult(result),
                  );
                },
              ),
            ),
          
          // Map takes remaining space
          Expanded(
            child: GoogleMapsWidget(
              initialLocation: widget.initialLocation,
              showUserLocation: true,
              allowSelection: true,
              onLocationSelected: _onLocationSelected,
            ),
          ),
          
          // Information about selected location
          if (_selectedLocation != null)
            Container(
              padding: EdgeInsets.all(16),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Selected Location',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  SizedBox(height: 12),
                  
                  // Place name - using our new getPlaceName helper
                  Text(
                    _selectedLocation!.getPlaceName(),
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 8),
                  
                  // Full address
                  if (_selectedLocation!.address != null) ...[  
                    Text(
                      _selectedLocation!.address!,
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                    SizedBox(height: 8),
                  ],
                  
                  // Area details if available
                  Row(children: [
                    if (_selectedLocation!.city != null) ...[  
                      Icon(Icons.location_city, size: 16, color: Colors.grey[600]),
                      SizedBox(width: 4),
                      Text(
                        _selectedLocation!.city!,
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      SizedBox(width: 16),
                    ],
                    if (_selectedLocation!.state != null) ...[  
                      Text(
                        _selectedLocation!.state!,
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      SizedBox(width: 8),
                    ],
                    if (_selectedLocation!.country != null) ...[  
                      Text(
                        _selectedLocation!.country!,
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                    ],
                  ]),
                  SizedBox(height: 12),
                  
                  // Coordinates
                  Row(
                    children: [
                      Icon(Icons.gps_fixed, size: 16, color: Colors.grey[600]),
                      SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  
                  // Confirm button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        widget.onLocationSelected(_selectedLocation!);
                        Navigator.of(context).pop(_selectedLocation);
                      },
                      child: Text('Confirm Location'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}