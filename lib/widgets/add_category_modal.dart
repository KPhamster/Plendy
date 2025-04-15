import 'package:flutter/material.dart';
import 'package:plendy/models/user_category.dart';
import 'package:plendy/services/experience_service.dart';

class AddCategoryModal extends StatefulWidget {
  const AddCategoryModal({super.key});

  @override
  State<AddCategoryModal> createState() => _AddCategoryModalState();
}

class _AddCategoryModalState extends State<AddCategoryModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final ExperienceService _experienceService = ExperienceService();
  String _selectedIcon = '';
  bool _isLoading = false;

  // Expanded list of emojis for selection
  final List<String> _emojiOptions = [
    // Food & Drink
    '🍽️', '🍔', '🍟', '🌭', '🍕', '🍝', '🌮', '🍣', '🍱', '🍜', '🥡',
    '🍖', '🍗', '🥩', '🥪', '🥗', '🥞', '🥯', '🍳', '🥐', '🥨', '🍦',
    '🍨', '🧁', '🍧', '🍩', '🍿', '🍪', '🎂', '🍰', '☕', '🫖', '🍵',
    '🍺', '🍷', '🍹', '🍾', '🍷', '🍸', '🍹', '🍺', '🍻', '🥂', '🧋',
    '🍎', '🍉', '🍒', '🍆', '🌶️', '🍄', '🥦', '🫛',

    // Utensils
    '🥢', '🍽️', '🍴',

    // Places
    '🏛️', '🎭', '🌳', '🎉', '⭐', '💖', '📍', '🛍️', '🛒', '🏠',
    '🏢', '🏭', '🏥', '🏦', '🏨', '🏪', '🏫', '⛪', '🕌', '🕍',
    '⛩️', '♨️', '💈', '⛺', '🏞️', '🏜️', '🏝️', '⛰️', '🌋', '🗺️',
    '🧭', '🪐', '🌍', '🌌', '🏕️', '🏖️', '🛣️', '🏞️', '🌅', '🌆',
    '🏟️', '🏘️', '🗼', '⛺', '🌊', '❄️', '☃️', '🌠',

    // Activities & Sports
    '🏋️', '🧘', '🎮', '🎨', '🎬', '🎤', '📚', '✏️', '💡', '🛠️',
    '⚽', '🏀', '🏈', '⚾', '🥎', '🎾', '🏐', '🏉', '🎱', '🏓',
    '🏸', '🏒', '🏑', '🏏', '🥅', '⛳', '🏹', '🎣', '🥊', '🥋',
    '🎳', '⛸️', '🎣', '🤿', '🎯', '🪁', '🎮', '🕹️', '🎲', '🎰',
    '🎽', '🛹', '🛼', '🎿', '⛷️', '🏂', '🧗', '🤺', '🏇', '🏊',
    '🏄', '🚣', '🚵', '🚴', '💆', '💇', '💆‍♂️', '💆‍♀️', '💇‍♂️', '💇‍♀️',
    '💆‍♂️', '💆‍♀️', '💇‍♂️', '💇‍♀️', '🏃‍♂️', '💃', '🧘', '🏌️‍♂️', '🚣',
    '🏊',
    '🤽', '🤾', '⛹️', '🏋️', '🤼', '🏆', '🏅', '🥇', '🥈', '🥉',
    '🎫', '🎟️',

    // Objects & Symbols
    '✂️', '💅', '💼', '💰', '📈', '📉', '📊', '📎', '📌', '💡',
    '💻', '📱', '⌚', '🖱️', '📷', '📹', '📺', '📻', '⏰', '🔔',
    '🧩', '🚗', '✈️', '🚀', '⛵', '⚓', '🎈', '🎆', '🎉', '✨',
    '🎃', '🎊', '🎄', '🎎', '🎀', '🎁', '🎞️', '🎠', '🎡', '🎢',
    '🎪', '🖼️', '🎨', '🕶️', '👕', '👖', '🧥', '👗', '👟', '👑',
    '💄', '💍', '💋', '♣️', '♥️', '📢', '🔔', '🎼', '🎵', '🎶',
    '🎙️', '🎤', '🎧', '🎻', '🎸', '🎷', '🎺', '🥁', '🎹', '📻',
    '🔑', '⚖️', '⚔️', '🛡️', '🎥', '🎬', '🔍', '📖', '📚', '💰',
    '📌', '⌛', '🧸', '🔬', '🔭', '♀️', '♂️', '🚬', '🪦',

    //Plants & Flowers
    '🌿', '🌱', '💐', '🌸', '🏵️', '🌹', '🌷', '🌺', '🌻', '🥀',
    '🍀', '🍂', '🌳', '🪵', '🪴', '🌵', '🌲', '🌴',
    // Nature & Animals
    '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯',
    '🦁', '🐮', '🐷', '🐸', '🐵', '🦋', '🐛', '🐜', '🐝', '🐞',
    '🐴', '🦓', '🦄', '🐲', '🐎', '🐬', '🐳', '🦞', '🐠', '🦆',

    //Faces
    '👶', '👦', '👧', '👨', '👩', '👴', '👵', '👲', '👳', '👮',
    '🎅', '👮‍♂️', '🧑‍⚕️', '👨‍🎓', '👨‍💼', '🧑‍🚒', '👰', '🤵', '🧙‍♂️',
    '🧛',
    '👷', '👸', '👹', '👺', '👻', '👼', '👽', '👾', '👿', '💀',
    '💩', '🧑‍🤝‍🧑', '👨‍👩‍👧‍👦', '😀', '😁', '😂', '🤣', '😃', '😄', '😅',
    '😆', '😉', '😊', '😋', '😎', '😍', '😘', '🥰', '😗', '😙',
    '🥲', '🫡', '🤨', '😑', '😐', '😪', '😴', '🥱', '😌', '😒',
    '😓', '😔', '🙃', '🫠', '🫤', '🤑', '😲', '☹️', '🙁', '😖',
    '😟', '😤', '😢', '😭', '😨', '😩', '😬', '🤯', '😮‍💨', '😱',
    '🥵', '🥶', '😳', '🤪', '😵', '😵‍💫', '🥴', '😠', '😡', '🤬',
    '😷', '🤒', '🤕', '🤢', '🤮', '🤧', '😇', '🥳', '🥹', '🤠',
    '🤡', '🤫', '😈', '💀', '☠️', '💪', '🦵', '🦶', '☝️', '🤞',
    '🫰', '🖖', '👌', '🤌', '🤘', '👍', '👎', '✍️', '👏', '🫶',

    // Transportation
    '🚗', '🚓', '🚕', '🚑', '🚒', '🏍️', '🏎️', '🚊', '🚡', '🚂',
    '✈️', '⛵', '🚢', '🏴‍☠️',

    // Misc Symbols
    '❓', '❗', '✔️', '➕', '➖', '➗', '✖️', '💲', '💯', '🔥',
    '❤️', '🩷', '🧡', '💛', '💚', '💙', '🩵', '💜', '🤎', '🖤',
    '🩶', '🤍', '💔', '❤️‍🔥', '💕', '💗', '💝', '💦', '🔘', '🔴',
    '🟠', '🟡', '🟢', '🔵', '🟣', '🟤', '⚫', '⚪', '🟥', '🟧',
    '🟨', '🟩', '🟦', '🟪', '🟫', '⬛', '⬜', '◼️', '◻️', '◾',
  ];

  @override
  void initState() {
    super.initState();
    // Pre-select the first emoji
    if (_emojiOptions.isNotEmpty) {
      _selectedIcon = _emojiOptions.first;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveCategory() async {
    if (_formKey.currentState!.validate() && _selectedIcon.isNotEmpty) {
      setState(() {
        _isLoading = true;
      });

      final name = _nameController.text.trim();
      final icon = _selectedIcon;

      try {
        // Add the category using the service
        final newCategory =
            await _experienceService.addUserCategory(name, icon);
        if (mounted) {
          // Pop the modal and return the newly created category
          Navigator.of(context).pop(newCategory);
        }
      } catch (e) {
        print("Error adding category: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error adding category: ${e.toString()}')),
          );
          setState(() {
            _isLoading = false;
          });
        }
      }
    } else if (_selectedIcon.isEmpty) {
      // Should not happen with pre-selection, but handle just in case
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an icon.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculate padding for bottom sheet content to avoid keyboard overlap
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        top: 20.0,
        bottom: bottomPadding + 20.0, // Adjust bottom padding for keyboard
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min, // Important for bottom sheet
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Create a New Category',
                    style: Theme.of(context).textTheme.titleLarge),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(), // Dismiss modal
                  tooltip: 'Cancel',
                ),
              ],
            ),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name your new category',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a category name';
                }
                // Optional: Add check for existing category name (service layer handles it too)
                return null;
              },
            ),
            const SizedBox(height: 16),
            Text('Select Icon', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            // Simple Emoji Grid
            SizedBox(
              height: 300,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6, // Adjust column count
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _emojiOptions.length,
                itemBuilder: (context, index) {
                  final emoji = _emojiOptions[index];
                  final isSelected = emoji == _selectedIcon;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedIcon = emoji;
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.blue.shade100
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                        border: isSelected
                            ? Border.all(color: Colors.blue, width: 2)
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        emoji,
                        style:
                            const TextStyle(fontSize: 24), // Adjust emoji size
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _isLoading
                    ? Container(
                        width: 20,
                        height: 20,
                        padding: const EdgeInsets.all(2.0),
                        child: const CircularProgressIndicator(
                            strokeWidth: 3, color: Colors.white),
                      )
                    : const Icon(Icons.save),
                label: Text(_isLoading ? 'Saving...' : 'Save Category'),
                onPressed: _isLoading ? null : _saveCategory,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
