import 'package:flutter/material.dart';
import 'package:plendy/models/user_collection.dart';
import 'package:plendy/services/experience_service.dart';

class AddCollectionModal extends StatefulWidget {
  final UserCollection? collectionToEdit;

  const AddCollectionModal({super.key, this.collectionToEdit});

  @override
  State<AddCollectionModal> createState() => _AddCollectionModalState();
}

class _AddCollectionModalState extends State<AddCollectionModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final ExperienceService _experienceService = ExperienceService();
  String _selectedIcon = '';
  bool _isLoading = false;

  bool get _isEditing => widget.collectionToEdit != null;

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
    if (_isEditing) {
      _nameController.text = widget.collectionToEdit!.name;
      _selectedIcon = widget.collectionToEdit!.icon;
      if (!_emojiOptions.contains(_selectedIcon)) {
        _selectedIcon = _emojiOptions.isNotEmpty ? _emojiOptions.first : '';
      }
    } else if (_emojiOptions.isNotEmpty) {
      _selectedIcon = _emojiOptions.first;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveCollection() async {
    if (_formKey.currentState!.validate() && _selectedIcon.isNotEmpty) {
      setState(() {
        _isLoading = true;
      });

      final name = _nameController.text.trim();
      final icon = _selectedIcon;

      try {
        UserCollection resultCollection;
        if (_isEditing) {
          final updatedCollection = widget.collectionToEdit!.copyWith(
            name: name,
            icon: icon,
          );
          await _experienceService.updateUserCollection(updatedCollection);
          resultCollection = updatedCollection;
          print("Collection updated: ${resultCollection.name}");
        } else {
          resultCollection =
              await _experienceService.addUserCollection(name, icon);
          print("Collection added: ${resultCollection.name}");
        }

        if (mounted) {
          Navigator.of(context).pop(resultCollection);
        }
      } catch (e) {
        print("Error saving collection: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Error ${_isEditing ? "updating" : "adding"} collection: ${e.toString()}')),
          );
          setState(() {
            _isLoading = false;
          });
        }
      }
    } else if (_selectedIcon.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an icon.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        top: 20.0,
        bottom: bottomPadding + 20.0,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_isEditing ? 'Edit Collection' : 'Create a New Collection',
                    style: Theme.of(context).textTheme.titleLarge),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Cancel',
                ),
              ],
            ),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: _isEditing
                    ? 'Edit collection name'
                    : 'Name your new collection',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a collection name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Text('Select Icon', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 300,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
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
                        style: const TextStyle(fontSize: 24),
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
                label: Text(_isLoading
                    ? 'Saving...'
                    : _isEditing
                        ? 'Update Collection'
                        : 'Save Collection'),
                onPressed: _isLoading ? null : _saveCollection,
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
