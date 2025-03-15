import 'package:flutter/material.dart';
import '../widgets/map_widget.dart';
import '../models/experience.dart';

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
  Location? _selectedLocation;
  
  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
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
          Expanded(
            child: PlendyMapWidget(
              initialLocation: widget.initialLocation,
              showUserLocation: true,
              allowSelection: true,
              onLocationSelected: (location) {
                setState(() {
                  _selectedLocation = location;
                });
              },
            ),
          ),
          
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
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(_selectedLocation!.address ?? 'Location Selected'),
                  SizedBox(height: 8),
                  Text(
                    'Coordinates: ${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                  SizedBox(height: 16),
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
