import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/experience.dart';
import '../services/experience_service.dart';
import '../models/user_category.dart';
import '../config/colors.dart';

class SelectSavedExperienceModalContent extends StatefulWidget {
  final ScrollController? scrollController; // Optional: for DraggableScrollableSheet

  const SelectSavedExperienceModalContent({super.key, this.scrollController});

  @override
  _SelectSavedExperienceModalContentState createState() =>
      _SelectSavedExperienceModalContentState();
}

class _SelectSavedExperienceModalContentState
    extends State<SelectSavedExperienceModalContent> {
  final ExperienceService _experienceService = ExperienceService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Future<List<dynamic>>? _dataFuture;
  List<Experience> _filteredExperiences = [];
  List<Experience> _allExperiences = [];
  List<UserCategory> _userCategories = [];

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserExperiences();
    _searchController.addListener(_filterExperiences);
  }

  void _loadUserExperiences() {
    final userId = _auth.currentUser?.uid;
    if (userId != null) {
      // Fetch all of the user's experiences (no limit) so search covers everything
      final experiencesFuture =
          _experienceService.getExperiencesByUser(userId, limit: 0);
      final categoriesFuture = _experienceService.getUserCategories();

      _dataFuture = Future.wait([experiencesFuture, categoriesFuture])
        ..then((results) {
          if (mounted) {
            final experiences = results[0] as List<Experience>;
            final categories = results[1] as List<UserCategory>;
            setState(() {
              _allExperiences = experiences;
              _filteredExperiences = experiences;
              _userCategories = categories;
            });
          }
        }).catchError((error) {
          print("Error loading user experiences or categories in modal: $error");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error loading data: $error')),
            );
            setState(() {
              _allExperiences = [];
              _filteredExperiences = [];
              _userCategories = [];
            });
          }
        });
    } else {
      print("User not logged in, cannot load experiences in modal.");
      if (mounted) {
        setState(() {
          _dataFuture = Future.value([[], []]);
          _allExperiences = [];
          _filteredExperiences = [];
          _userCategories = [];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('You must be logged in to select experiences.')),
        );
        // Optionally pop the modal if user is not logged in
        // Navigator.pop(context);
      }
    }
  }

  void _filterExperiences() {
    final query = _searchController.text.toLowerCase();
    if (mounted) {
      setState(() {
        if (query.isEmpty) {
          _filteredExperiences = _allExperiences;
        } else {
          _filteredExperiences = _allExperiences.where((exp) {
            final nameLower = exp.name.toLowerCase();
            final notesLower = exp.additionalNotes?.toLowerCase() ?? '';
            final addressLower = exp.location.address?.toLowerCase() ?? '';
            final cityLower = exp.location.city?.toLowerCase() ?? '';
            
            // MODIFIED: Get category name using categoryId and _userCategories list
            String categoryLower = '';
            if (exp.categoryId != null && _userCategories.isNotEmpty) {
              try {
                final category = _userCategories.firstWhere((cat) => cat.id == exp.categoryId);
                categoryLower = category.name.toLowerCase();
              } catch (e) {
                // Category not found in _userCategories, leave categoryLower as ''
                // This means items with a categoryId not in _userCategories 
                // (or null categoryId) won't match on a category search term.
              }
            }

            return nameLower.contains(query) ||
                notesLower.contains(query) ||
                addressLower.contains(query) ||
                cityLower.contains(query) ||
                categoryLower.contains(query);
          }).toList();
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterExperiences);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // This widget is now intended to be the content of a modal,
    // so we don't need a full Scaffold here.
    // The AppBar functionality (title & search) will be part of this Column.
    return Padding(
      padding: const EdgeInsets.all(16.0), // Add some padding around the modal content
      child: Column(
        mainAxisSize: MainAxisSize.min, // Important for modals
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Optional Title for the modal
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Text(
              'Select Saved Experience',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
          ),
          // Search Bar
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Search your experiences',
              prefixIcon: Icon(Icons.search, color: Theme.of(context).primaryColor),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25.0),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25.0),
                borderSide: const BorderSide(
                  color: AppColors.backgroundColorDark,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25.0),
                borderSide: const BorderSide(
                  color: AppColors.backgroundColorDark,
                  width: 2,
                ),
              ),
              filled: true,
              fillColor: AppColors.backgroundColorDark,
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: 'Clear Search',
                      onPressed: () {
                        _searchController.clear();
                        // _filterExperiences will be called by the listener
                      },
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16.0), // Spacing after search bar
          // List of experiences
          Expanded( // Allows the ListView to take available space within the Column
            child: FutureBuilder<List<dynamic>>(
              future: _dataFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  print(
                      "Snapshot error in modal: ${snapshot.error}");
                  return const Center(
                      child: Text('Error loading experiences. Please try again.'));
                } else if (!snapshot.hasData || snapshot.data!.isEmpty && _searchController.text.isEmpty) {
                  return const Center(
                      child: Text('You haven\'t saved any experiences yet.'));
                } else {
                  final experiences = _filteredExperiences;

                  if (experiences.isEmpty && _searchController.text.isNotEmpty) {
                    return Center(
                      child: Text(
                        'No experiences found matching "${_searchController.text}".',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  if (experiences.isEmpty && _allExperiences.isEmpty) {
                     return const Center(
                        child: Text('You haven\'t saved any experiences yet.'));
                  }


                  return ListView.builder(
                    controller: widget.scrollController, // Use the passed scrollController
                    itemCount: experiences.length,
                    itemBuilder: (context, index) {
                      final experience = experiences[index];
                      return ListTile(
                        title: Text(experience.name),
                        subtitle: Text(experience.location.getFormattedArea() ??
                            experience.location.address ??
                            'No location details'),
                        onTap: () {
                          // Return the selected experience when tapped
                          Navigator.pop(context, experience);
                        },
                      );
                    },
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
