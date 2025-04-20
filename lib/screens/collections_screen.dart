import 'package:flutter/material.dart';
import '../models/experience.dart';
import '../models/user_category.dart';
import '../services/auth_service.dart';
import '../services/experience_service.dart';

class CollectionsScreen extends StatefulWidget {
  CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  final _authService = AuthService();
  final _experienceService = ExperienceService();

  bool _isLoading = true;
  List<UserCategory> _categories = [];
  List<Experience> _experiences = [];
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _userEmail = _authService.currentUser?.email ?? 'Guest';
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    final userId = _authService.currentUser?.uid;
    try {
      final categories = await _experienceService.getUserCategories();
      List<Experience> experiences = [];
      if (userId != null) {
        experiences = await _experienceService.getExperiencesByUser(userId);
      }

      if (mounted) {
        setState(() {
          _categories = categories;
          _experiences = experiences;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  int _getExperienceCountForCategory(UserCategory category) {
    return _experiences.where((exp) => exp.category == category.name).length;
  }

  Widget _buildCategoriesList() {
    if (_categories.isEmpty) {
      return const Center(child: Text('No categories found.'));
    }

    return ListView.builder(
      itemCount: _categories.length,
      itemBuilder: (context, index) {
        final category = _categories[index];
        final count = _getExperienceCountForCategory(category);
        return ListTile(
          leading: Text(
            category.icon,
            style: const TextStyle(fontSize: 24),
          ),
          title: Text(category.name),
          subtitle: Text('$count ${count == 1 ? "experience" : "experiences"}'),
          trailing: IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              print('Options pressed for ${category.name}');
            },
          ),
          onTap: () {
            print('Tapped on ${category.name}');
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Collection'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Categories'),
              Tab(text: 'Experiences'),
              Tab(text: 'Content'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildCategoriesList(),
                  Center(
                      child: Text('Experiences Tab Content for $_userEmail')),
                  Center(child: Text('Content Tab Content for $_userEmail')),
                ],
              ),
      ),
    );
  }
}
