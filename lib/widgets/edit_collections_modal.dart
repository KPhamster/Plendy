import 'package:flutter/material.dart';
import 'package:plendy/models/user_collection.dart';
import 'package:plendy/services/experience_service.dart';
import 'package:plendy/widgets/add_collection_modal.dart';

// UPDATED: Enum for sort order (used as parameter, not state)
enum CollectionSortType { mostRecent, alphabetical }

class EditCollectionsModal extends StatefulWidget {
  const EditCollectionsModal({super.key});

  @override
  State<EditCollectionsModal> createState() => _EditCollectionsModalState();
}

class _EditCollectionsModalState extends State<EditCollectionsModal> {
  final ExperienceService _experienceService = ExperienceService();
  List<UserCollection> _collections =
      []; // Now holds the current display/manual order
  List<UserCollection> _fetchedCollections = []; // Holds original fetched order
  bool _isLoading = false;
  bool _collectionsChanged =
      false; // Track if *any* change to order/content occurred

  @override
  void initState() {
    super.initState();
    _loadCollections();
  }

  Future<void> _loadCollections() async {
    if (!mounted) return;
    print("_loadCollections START - Setting isLoading=true"); // Log Start
    setState(() {
      _isLoading = true;
    });
    try {
      print(
          "_loadCollections - Calling _experienceService.getUserCollections..."); // Log Before Call
      final collections = await _experienceService.getUserCollections();
      print(
          "_loadCollections - Received ${collections.length} collections from service:"); // Log Received
      collections.forEach((c) => print("  - ${c.name} (ID: ${c.id})"));

      if (mounted) {
        setState(() {
          _fetchedCollections =
              List.from(collections); // Store the original fetched order
          // Initialize _collections with the fetched order (already sorted by index)
          _collections = List.from(_fetchedCollections);
          _isLoading = false;
          print(
              "_loadCollections END - Set state with fetched collections."); // Log State Set
          // No initial sort application needed, _collections starts with saved order
        });
      }
    } catch (error) {
      print("_loadCollections ERROR: $error"); // Log Error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading collections: $error')),
        );
        setState(() {
          _isLoading = false;
          _collections = [];
          _fetchedCollections = [];
          print(
              "_loadCollections END - Set state with empty collections after error."); // Log Error State Set
        });
      }
    }
  }

  // UPDATED: Function now takes sort type and applies it permanently
  void _applySort(CollectionSortType sortType) {
    print("Applying sort permanently: $sortType");
    setState(() {
      if (sortType == CollectionSortType.alphabetical) {
        _collections.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      } else if (sortType == CollectionSortType.mostRecent) {
        _collections.sort((a, b) {
          final tsA = a.lastUsedTimestamp;
          final tsB = b.lastUsedTimestamp;
          if (tsA == null && tsB == null) return 0;
          if (tsA == null) return 1;
          if (tsB == null) return -1;
          return tsB.compareTo(tsA);
        });
      }

      // IMPORTANT: Update orderIndex locally after sorting
      _updateLocalOrderIndices();
      _collectionsChanged = true; // Mark that changes were made
      print(
          "Collection sorted via menu, _collectionsChanged set to true."); // Log flag set

      print("Display collections count after sort: ${_collections.length}");
    });
  }

  // ADDED: Helper to update local orderIndex properties
  void _updateLocalOrderIndices() {
    for (int i = 0; i < _collections.length; i++) {
      _collections[i] = _collections[i].copyWith(orderIndex: i);
    }
    print("Updated local order indices.");
  }

  Future<void> _deleteCollection(UserCollection collection) async {
    // Confirmation Dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Collection?'),
        content: Text(
            'Are you sure you want to delete the "${collection.name}" collection? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() {
        _isLoading = true; // Indicate loading during delete
      });
      try {
        await _experienceService.deleteUserCollection(collection.id);
        // Ensure flag is set *before* loading, as load might reset list
        _collectionsChanged = true;
        print(
            "Collection deleted, _collectionsChanged set to true."); // Log flag set
        _loadCollections(); // Refresh the list immediately after delete
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${collection.name}" collection deleted.')),
          );
        }
      } catch (e) {
        print("Error deleting collection: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting collection: $e')),
          );
          setState(() {
            _isLoading = false; // Reset loading state on error
          });
        }
      }
    }
  }

  Future<void> _editCollection(UserCollection collection) async {
    // Show the AddCollectionModal, passing the collection to edit
    final updatedCollection = await showModalBottomSheet<UserCollection>(
      context: context,
      // Pass the collection to the modal
      builder: (context) => AddCollectionModal(collectionToEdit: collection),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );

    // Check if the modal returned an updated collection
    if (updatedCollection != null && mounted) {
      // No need to call updateUserCollection here, as AddCollectionModal handles it
      // Ensure flag is set *before* loading
      _collectionsChanged = true;
      print(
          "Collection edited, _collectionsChanged set to true."); // Log flag set
      _loadCollections(); // Refresh the list in this modal (will re-apply sort)

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('"${updatedCollection.name}" collection updated.')),
      );
    }
  }

  Future<void> _addNewCollection() async {
    // Show the existing AddCollectionModal
    final newCollection = await showModalBottomSheet<UserCollection>(
      context: context,
      builder: (context) => const AddCollectionModal(),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );

    if (newCollection != null && mounted) {
      // If a new collection was added, mark changes and refresh the list
      // Ensure flag is set *before* loading
      _collectionsChanged = true;
      print(
          "Collection added, _collectionsChanged set to true."); // Log flag set
      _loadCollections(); // Refresh the list (will re-apply sort)
    }
  }

  @override
  Widget build(BuildContext context) {
    print(
        "EditCollectionsModal BUILD START - Current collection count: ${_collections.length}"); // Log Build Start (use _collections)
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    // Calculate a max height (e.g., 70% of screen height)
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.9;

    // Wrap Padding in a Container with constraints
    return Container(
      constraints: BoxConstraints(
        maxHeight: maxHeight,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 16.0,
          right: 16.0,
          top: 8.0,
          bottom: bottomPadding + 16.0, // Padding for keyboard is still needed
        ),
        child: Column(
          // Re-add mainAxisSize: MainAxisSize.min so the column doesn't force max height if content is short
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row (Fixed Top)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.only(left: 8.0, top: 8.0, bottom: 8.0),
                  child: Text('Edit Collections',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                // UPDATED: Sorting Menu Button
                PopupMenuButton<CollectionSortType>(
                  // Use standard sort icon
                  icon: const Icon(Icons.sort),
                  tooltip: "Sort Collections",
                  onSelected: (CollectionSortType result) {
                    // Directly apply the selected sort permanently
                    _applySort(result);
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<CollectionSortType>>[
                    // UPDATED: Menu items (Removed Manual)
                    const PopupMenuItem<CollectionSortType>(
                      value: CollectionSortType.mostRecent,
                      child: Text('Sort by Most Recent'),
                    ),
                    const PopupMenuItem<CollectionSortType>(
                      value: CollectionSortType.alphabetical,
                      child: Text('Sort Alphabetically'),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      _handleClose(), // UPDATED: Use helper to handle close
                  tooltip: 'Close',
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            // Scrollable List Area (Uses Expanded)
            Expanded(
              child: _isLoading && _collections.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _collections.isEmpty
                      ? const Center(child: Text('No collections found.'))
                      // UPDATED: Use ReorderableListView.builder
                      : ReorderableListView.builder(
                          // buildDefaultDragHandles: false, // We use a custom handle
                          itemCount: _collections.length,
                          itemBuilder: (context, index) {
                            final collection = _collections[index];
                            // IMPORTANT: Each item MUST have a unique Key
                            return ListTile(
                              key: ValueKey(collection.id),
                              leading: Text(collection.icon,
                                  style: const TextStyle(fontSize: 24)),
                              title: Text(collection.name),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.edit_outlined,
                                        color: Colors.blue[700], size: 20),
                                    tooltip: 'Edit ${collection.name}',
                                    onPressed: _isLoading
                                        ? null
                                        : () => _editCollection(collection),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline,
                                        color: Colors.red[700], size: 20),
                                    tooltip: 'Delete ${collection.name}',
                                    onPressed: _isLoading
                                        ? null
                                        : () => _deleteCollection(collection),
                                  ),
                                  // ADDED: Drag Handle
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: const Icon(Icons.drag_handle,
                                        color: Colors.grey, size: 24),
                                  ),
                                ],
                              ),
                            );
                          },
                          onReorder: (int oldIndex, int newIndex) {
                            setState(() {
                              // Adjust index if item is moved down in the list
                              if (newIndex > oldIndex) {
                                newIndex -= 1;
                              }
                              // Remove item from old position and insert into new position
                              final UserCollection item =
                                  _collections.removeAt(oldIndex);
                              _collections.insert(newIndex, item);

                              // Update orderIndex property in the local list
                              _updateLocalOrderIndices(); // Use helper

                              _collectionsChanged =
                                  true; // Mark that changes were made
                              print(
                                  "Collection reordered, _collectionsChanged set to true."); // Log flag set

                              // Update orderIndex property in the local list
                              _updateLocalOrderIndices(); // Use helper

                              print("Collections reordered.");
                            });
                          },
                        ),
            ),
            const SizedBox(height: 16),
            // Add New Collection Button (Fixed Bottom)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add New Collection'),
                onPressed: _isLoading ? null : _addNewCollection,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            // ADDED Padding below button
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ADDED: Helper function to handle closing and potentially saving order
  Future<void> _handleClose() async {
    // UPDATED: Save if any changes were flagged
    bool shouldSaveChanges = _collectionsChanged;
    print(
        "Closing EditCollectionsModal. Should save changes: $shouldSaveChanges");

    if (shouldSaveChanges) {
      setState(() {
        _isLoading = true;
      }); // Show loading indicator
      try {
        // Prepare data for batch update
        final List<Map<String, dynamic>> updates = [];
        for (int i = 0; i < _collections.length; i++) {
          // Ensure collection has an ID and index before adding to update
          if (_collections[i].id.isNotEmpty &&
              _collections[i].orderIndex != null) {
            updates.add({
              'id': _collections[i].id,
              'orderIndex':
                  _collections[i].orderIndex!, // Use ! as we updated it
            });
          } else {
            print(
                "Warning: Skipping collection with missing id or index: ${_collections[i].name}");
          }
        }

        print("Attempting to save order for ${updates.length} collections.");
        await _experienceService.updateCollectionOrder(updates);
        print("Collection order saved successfully.");
        if (mounted) {
          Navigator.of(context)
              .pop(true); // Indicate changes were made and saved
        }
      } catch (e) {
        print("Error saving collection order: $e");
        if (mounted) {
          // Show error message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error saving collection order: $e")),
          );
          // Optionally, don't pop or pop indicating failure?
          // For now, we still pop but indicate no changes were successfully saved (original _collectionsChanged state)
          Navigator.of(context)
              .pop(_collectionsChanged && false); // Force false if save failed
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          }); // Hide loading indicator
        }
      }
    } else {
      // No changes to save, just pop
      Navigator.of(context).pop(_collectionsChanged);
    }
  }
}
