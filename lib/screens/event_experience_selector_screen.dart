import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import '../models/experience.dart';
import '../models/user_category.dart';
import '../models/color_category.dart';

/// A reusable full-screen modal for selecting experiences for events.
/// 
/// This screen provides a two-tab interface (Categories and Experiences) that allows
/// users to browse and select experiences using checkboxes. It mirrors the functionality
/// of the Collections screen but without the Content tab and with persistent checkboxes
/// on all experience items.
/// 
/// Usage:
/// ```dart
/// final result = await Navigator.of(context).push(
///   MaterialPageRoute(
///     builder: (ctx) => EventExperienceSelectorScreen(
///       categories: categories,
///       colorCategories: colorCategories,
///       experiences: experiences,
///     ),
///     fullscreenDialog: true,
///   ),
/// );
/// if (result != null && result is Set<String>) {
///   // result contains the selected experience IDs
/// }
/// ```
class EventExperienceSelectorScreen extends StatefulWidget {
  final List<UserCategory> categories;
  final List<ColorCategory> colorCategories;
  final List<Experience> experiences;
  final Set<String>? preSelectedExperienceIds;
  final String? title;

  const EventExperienceSelectorScreen({
    super.key,
    required this.categories,
    required this.colorCategories,
    required this.experiences,
    this.preSelectedExperienceIds,
    this.title,
  });

  @override
  State<EventExperienceSelectorScreen> createState() =>
      _EventExperienceSelectorScreenState();
}

class _EventExperienceSelectorScreenState
    extends State<EventExperienceSelectorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentTabIndex = 0;
  late Set<String> _selectedExperienceIds;
  UserCategory? _selectedCategory;
  ColorCategory? _selectedColorCategory;
  bool _showingColorCategories = false;

  @override
  void initState() {
    super.initState();
    _selectedExperienceIds = widget.preSelectedExperienceIds != null
        ? Set.from(widget.preSelectedExperienceIds!)
        : {};
    _tabController = TabController(length: 2, vsync: this);
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
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Helper to parse hex color string
  Color _parseColor(String hexColor) {
    hexColor = hexColor.toUpperCase().replaceAll("#", "");
    if (hexColor.length == 6) {
      hexColor = "FF$hexColor";
    }
    if (hexColor.length == 8) {
      try {
        return Color(int.parse("0x$hexColor"));
      } catch (e) {
        return Colors.grey;
      }
    }
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'Select Experiences for Event'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedExperienceIds.isEmpty
                    ? Colors.grey.shade300
                    : Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.fromLTRB(12, 6, 16, 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: _selectedExperienceIds.isEmpty
                  ? null
                  : () {
                      Navigator.of(context).pop(_selectedExperienceIds);
                    },
              child: Text('Done (${_selectedExperienceIds.length})'),
            ),
          ),
        ],
      ),
      body: Container(
        color: Colors.white,
        child: Column(
          children: [
            Container(
              color: Colors.white,
              child: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Categories'),
                  Tab(text: 'Experiences'),
                ],
                labelColor: Theme.of(context).primaryColor,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Theme.of(context).primaryColor,
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Categories Tab
                  Container(
                    color: Colors.white,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7.0, vertical: 8.0),
                          child: Row(
                            children: [
                              const Expanded(child: SizedBox()),
                              Flexible(
                                child: Builder(
                                  builder: (context) {
                                    final IconData toggleIcon =
                                        _showingColorCategories
                                            ? Icons.category_outlined
                                            : Icons.color_lens_outlined;
                                    final String toggleLabel =
                                        _showingColorCategories
                                            ? 'Categories'
                                            : 'Color Categories';
                                    void onToggle() {
                                      setState(() {
                                        _showingColorCategories =
                                            !_showingColorCategories;
                                        _selectedCategory = null;
                                        _selectedColorCategory = null;
                                      });
                                    }

                                    return Align(
                                      alignment: Alignment.centerRight,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: TextButton.icon(
                                          style: TextButton.styleFrom(
                                            visualDensity: const VisualDensity(
                                                horizontal: -2, vertical: -2),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8.0),
                                          ),
                                          icon: Icon(toggleIcon),
                                          label: Text(toggleLabel),
                                          onPressed: onToggle,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: _selectedCategory != null
                              ? _buildCategoryExperiencesView()
                              : _selectedColorCategory != null
                                  ? _buildColorCategoryExperiencesView()
                                  : _showingColorCategories
                                      ? _buildColorCategoriesList()
                                      : _buildCategoriesList(),
                        ),
                      ],
                    ),
                  ),
                  // Experiences Tab
                  Container(
                    color: Colors.white,
                    child: _buildExperiencesListView(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriesList() {
    if (widget.categories.isEmpty) {
      return const Center(child: Text('No categories found.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80.0),
      itemCount: widget.categories.length,
      itemBuilder: (context, index) {
        final category = widget.categories[index];
        final count = widget.experiences
            .where((exp) =>
                exp.categoryId == category.id ||
                exp.otherCategories.contains(category.id))
            .length;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
          leading: Text(category.icon, style: const TextStyle(fontSize: 24)),
          title: Text(category.name),
          subtitle: Text('$count ${count == 1 ? "experience" : "experiences"}'),
          onTap: () {
            setState(() {
              _selectedCategory = category;
              _showingColorCategories = false;
              _selectedColorCategory = null;
            });
          },
        );
      },
    );
  }

  Widget _buildColorCategoriesList() {
    if (widget.colorCategories.isEmpty) {
      return const Center(child: Text('No color categories found.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80.0),
      itemCount: widget.colorCategories.length,
      itemBuilder: (context, index) {
        final category = widget.colorCategories[index];
        final count = widget.experiences.where((exp) {
          final bool isPrimary = exp.colorCategoryId == category.id;
          final bool isOther =
              exp.otherColorCategoryIds.contains(category.id);
          return isPrimary || isOther;
        }).length;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
          leading: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: category.color,
              shape: BoxShape.circle,
            ),
          ),
          title: Text(category.name),
          subtitle: Text('$count ${count == 1 ? "experience" : "experiences"}'),
          onTap: () {
            setState(() {
              _selectedColorCategory = category;
              _showingColorCategories = true;
              _selectedCategory = null;
            });
          },
        );
      },
    );
  }

  Widget _buildCategoryExperiencesView() {
    final categoryExperiences = widget.experiences
        .where((exp) =>
            exp.categoryId == _selectedCategory!.id ||
            exp.otherCategories.contains(_selectedCategory!.id))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to Categories',
                onPressed: () {
                  setState(() {
                    _selectedCategory = null;
                  });
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selectedCategory!.name,
                  style: Theme.of(context).textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: categoryExperiences.isEmpty
              ? Center(
                  child: Text(
                      'No experiences found in the "${_selectedCategory!.name}" category.'))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80.0),
                  itemCount: categoryExperiences.length,
                  itemBuilder: (context, index) {
                    return _buildExperienceListItem(
                        categoryExperiences[index]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildColorCategoryExperiencesView() {
    final categoryExperiences = widget.experiences.where((exp) {
      final bool isPrimary = exp.colorCategoryId == _selectedColorCategory!.id;
      final bool isOther =
          exp.otherColorCategoryIds.contains(_selectedColorCategory!.id);
      return isPrimary || isOther;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to Color Categories',
                onPressed: () {
                  setState(() {
                    _selectedColorCategory = null;
                  });
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selectedColorCategory!.name,
                  style: Theme.of(context).textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: categoryExperiences.isEmpty
              ? Center(
                  child: Text(
                      'No experiences found with the "${_selectedColorCategory!.name}" color category.'))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80.0),
                  itemCount: categoryExperiences.length,
                  itemBuilder: (context, index) {
                    return _buildExperienceListItem(
                        categoryExperiences[index]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildExperiencesListView() {
    if (widget.experiences.isEmpty) {
      return const Center(child: Text('No experiences found. Add some!'));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80.0),
      itemCount: widget.experiences.length,
      itemBuilder: (context, index) {
        return _buildExperienceListItem(widget.experiences[index]);
      },
    );
  }

  Widget _buildExperienceListItem(Experience experience) {
    final category = widget.categories.firstWhereOrNull(
      (cat) => cat.id == experience.categoryId,
    );
    final categoryIcon = category?.icon ?? '?';

    final colorCategoryForBox = widget.colorCategories.firstWhereOrNull(
      (cc) => cc.id == experience.colorCategoryId,
    );
    final Color leadingBoxColor = colorCategoryForBox != null
        ? _parseColor(colorCategoryForBox.colorHex).withOpacity(0.5)
        : Colors.white;

    final bool isSelected = _selectedExperienceIds.contains(experience.id);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8.0),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: isSelected,
            onChanged: (bool? value) {
              setState(() {
                if (value ?? false) {
                  _selectedExperienceIds.add(experience.id);
                } else {
                  _selectedExperienceIds.remove(experience.id);
                }
              });
            },
          ),
          const SizedBox(width: 4),
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: leadingBoxColor,
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Text(
              categoryIcon,
              style: const TextStyle(fontSize: 28),
            ),
          ),
        ],
      ),
      title: Text(
        experience.name,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
      subtitle: experience.location.address != null &&
              experience.location.address!.isNotEmpty
          ? Text(
              experience.location.address!,
              style: Theme.of(context).textTheme.bodySmall,
            )
          : null,
      onTap: () {
        setState(() {
          if (_selectedExperienceIds.contains(experience.id)) {
            _selectedExperienceIds.remove(experience.id);
          } else {
            _selectedExperienceIds.add(experience.id);
          }
        });
      },
    );
  }
}
