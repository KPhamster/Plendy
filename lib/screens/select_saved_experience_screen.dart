import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/experience.dart';
import '../services/experience_service.dart';
import '../models/user_category.dart';
// import '../widgets/experience_list_item.dart'; // Commented out - using ListTile

class SelectSavedExperienceScreen extends StatefulWidget {
  const SelectSavedExperienceScreen({super.key});

  @override
  _SelectSavedExperienceScreenState createState() =>
      _SelectSavedExperienceScreenState();
}

class _SelectSavedExperienceScreenState
    extends State<SelectSavedExperienceScreen> {
  final ExperienceService _experienceService = ExperienceService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Future<List<Experience>>? _userExperiencesFuture;
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
      final experiencesFuture = _experienceService.getExperiencesByUser(userId);
      final categoriesFuture = _experienceService.getUserCategories();

      _userExperiencesFuture = Future.wait([experiencesFuture, categoriesFuture]).then((results) {
        final experiences = results[0] as List<Experience>;
        final categories = results[1] as List<UserCategory>;
        setState(() {
          _allExperiences = experiences;
          _filteredExperiences = experiences;
          _userCategories = categories;
        });
        return experiences;
      }).catchError((error) {
        print("Error loading user experiences or categories: $error");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $error')),
        );
        setState(() {
          _allExperiences = [];
          _filteredExperiences = [];
          _userCategories = [];
        });
        return <Experience>[];
      });
    } else {
      // Handle case where user is not logged in
      print("User not logged in, cannot load experiences.");
      setState(() {
        _userExperiencesFuture = Future.value([]); // Return empty future
        _allExperiences = [];
        _filteredExperiences = [];
      });
      // Optionally show a message or navigate away
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('You must be logged in to select experiences.')),
      );
    }
  }

  void _filterExperiences() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredExperiences = _allExperiences;
      } else {
        _filteredExperiences = _allExperiences.where((exp) {
          final nameLower = exp.name.toLowerCase();
          final notesLower = exp.additionalNotes?.toLowerCase() ?? '';
          final addressLower = exp.location.address?.toLowerCase() ?? '';
          final cityLower = exp.location.city?.toLowerCase() ?? '';
          
          String categoryLower = '';
          if (exp.categoryId != null && _userCategories.isNotEmpty) {
            try {
              final category = _userCategories.firstWhere((cat) => cat.id == exp.categoryId);
              categoryLower = category.name.toLowerCase();
            } catch (e) {
              // Category not found or _userCategories is empty, leave categoryLower as ''
              // This means items with non-matching/null categoryId won't match on category search term
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

  @override
  void dispose() {
    _searchController.removeListener(_filterExperiences);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Saved Experience'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search your experiences...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[200],
                contentPadding:
                    EdgeInsets.symmetric(vertical: 0, horizontal: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          // _filterExperiences will be called by the listener
                        },
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
      body: FutureBuilder<List<Experience>>(
        future: _userExperiencesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            print(
                "Snapshot error: ${snapshot.error}"); // Log the specific error
            return Center(
                child: Text('Error loading experiences. Please try again.'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
                child: Text('You haven\'t saved any experiences yet.'));
          } else {
            // Use the filtered list for display
            final experiences = _filteredExperiences;

            if (experiences.isEmpty && _searchController.text.isNotEmpty) {
              return Center(
                child: Text(
                  'No experiences found matching "${_searchController.text}".',
                  textAlign: TextAlign.center,
                ),
              );
            }

            return ListView.builder(
              itemCount: experiences.length,
              itemBuilder: (context, index) {
                final experience = experiences[index];
                // Use ExperienceListItem or create a simple ListTile
                return ListTile(
                  // leading: experience.imageUrls.isNotEmpty
                  //     ? CircleAvatar(backgroundImage: NetworkImage(experience.imageUrls.first))
                  //     : CircleAvatar(child: Icon(Icons.place)), // Placeholder icon
                  title: Text(experience.name),
                  subtitle: Text(experience.location.getFormattedArea() ??
                      experience.location.address ??
                      'No location details'),
                  onTap: () {
                    // Return the selected experience when tapped
                    Navigator.pop(context, experience);
                  },
                );
                /* Potential usage of ExperienceListItem if it exists and is suitable - KEEP COMMENTED
                return ExperienceListItem(
                  experience: experience,
                  onTap: () {
                    Navigator.pop(context, experience);
                  },
                );
                */
              },
            );
          }
        },
      ),
    );
  }
}
