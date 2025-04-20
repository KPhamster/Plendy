import 'package:flutter/material.dart';
import '../models/experience.dart';
import '../models/user_category.dart';
import '../services/auth_service.dart';
import '../services/experience_service.dart';
import '../widgets/add_category_modal.dart';
import '../widgets/edit_categories_modal.dart';

class CollectionsScreen extends StatefulWidget {
  CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen>
    with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  final _experienceService = ExperienceService();

  late TabController _tabController;
  int _currentTabIndex = 0;

  bool _isLoading = true;
  List<UserCategory> _categories = [];
  List<Experience> _experiences = [];
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _userEmail = _authService.currentUser?.email ?? 'Guest';
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _currentTabIndex = _tabController.index;
        });
      } else {
        if (_currentTabIndex != _tabController.index) {
          setState(() {
            _currentTabIndex = _tabController.index;
          });
        }
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

  Future<void> _showAddCategoryModal() async {
    final result = await showModalBottomSheet<UserCategory>(
      context: context,
      builder: (_) => const AddCategoryModal(),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );

    if (result != null) {
      print("AddCategoryModal returned a category, refreshing data...");
      _loadData();
    } else {
      print("AddCategoryModal closed without adding.");
    }
  }

  Future<void> _showEditCategoriesModal() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      builder: (_) => const EditCategoriesModal(),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );

    if (result == true) {
      print("EditCategoriesModal returned true, refreshing data...");
      _loadData();
    } else {
      print("EditCategoriesModal closed or returned false (no changes saved).");
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
          onTap: () {
            print('Tapped on ${category.name}');
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Collection'),
        actions: [
          if (_currentTabIndex == 0)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit Categories',
              onPressed: _showEditCategoriesModal,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Categories'),
            Tab(text: 'Experiences'),
            Tab(text: 'Content'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildCategoriesList(),
                Center(child: Text('Experiences Tab Content for $_userEmail')),
                Center(child: Text('Content Tab Content for $_userEmail')),
              ],
            ),
      floatingActionButton: _currentTabIndex == 0
          ? FloatingActionButton(
              onPressed: _showAddCategoryModal,
              tooltip: 'Add Category',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
