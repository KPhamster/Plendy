import 'package:flutter/material.dart';
import 'package:plendy/models/user_category.dart';
import 'package:plendy/services/experience_service.dart';
import 'package:plendy/widgets/privacy_toggle_button.dart';
import 'package:plendy/utils/haptic_feedback.dart';

class AddCategoryModal extends StatefulWidget {
  final UserCategory? categoryToEdit;

  const AddCategoryModal({super.key, this.categoryToEdit});

  @override
  State<AddCategoryModal> createState() => _AddCategoryModalState();
}

class _AddCategoryModalState extends State<AddCategoryModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final ExperienceService _experienceService = ExperienceService();
  String _selectedIcon = '';
  bool _isLoading = false;
  bool _isPrivate = false;

  bool get _isEditing => widget.categoryToEdit != null;

  // Expanded list of emojis for selection
  final List<String> _emojiOptions = [
    // Food & Drink
    '🍎', '🍏', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🫐', '🍈', '🍒', '🍑', '🥭',
    '🍍', '🥥', '🥝', '🍅', '🍆', '🥑', '🥦', '🫛', '🥒', '🌶️', '🌽', '🥕', '🫑', '🥔', '🧅', '🧄', '🍄', '🥜',
    '🌰', '🍞', '🥐', '🥯', '🥞', '🍳', '🧇', '🥓', '🥩', '🍗', '🍖', '🍤', '🍣', '🍱', '🍚', '🍛', '🍜',
    '🍲', '🥣', '🥗', '🍝', '🍠', '🥡', '🥪', '🌭', '🍔', '🍟', '🍕', '🥫', '🥙', '🥘', '🌮', '🌯', '🥨', '🥟',
    '🦪', '🦞', '🦐', '🦑', '🍢', '🍡', '🍧', '🍨', '🍦', '🥧', '🍰', '🎂', '🧁', '🍮', '🍭', '🍬', '🍫', '🍿', '🍩', '🍪',
    '🍯', '🥤', '🧃', '🧉', '🧊', '🥛', '☕', '🫖', '🧋', '🍵', '🍶', '🍾', '🍷', '🍸', '🍹', '🍺', '🍻', '🥂', '🥃',
    
    // Utensils & Tableware
    '🍽️', '🥢', '🍴', '🥄', '🧂',

    // Places & Buildings
    '🏠', '🏡', '🏢', '🏣', '🏤', '🏥', '🏦', '🏨', '🏩', '🏪', '🏫', '🏬', '🏭', '🏯', '🏰', '🏛️', '⛪', '🕌', '🕍',
    '⛩️', '🕋', '⛲', '🗽', '🗼', '🏟️', '🎡', '🎢', '🎠', '⛺', '🏕️', '🏖️', '🏜️', '🏝️', '🏞️', '⛰️', '🏔️', '🗻', '🌋', '🏗️', '🛖',
    '🛣️', '🛤️', '🗺️', '🧭', '📍', '🏘️', '🌳', '🌆', '🌇', '🌅', '🌄', '⛱️', '🛍️', '🛒', '💈', '♨️', '⭐', '🌠', '🌌', '🪐', '🌍', '🌏', '🌎', '🪨', '🪵',
    '❄️', '☃️',

    // Nature & Plants
    '🌵', '🌲', '🌳', '🌴', '🌱', '🌿', '☘️', '🍀', '🎍', '🎋', '🍂', '🍁', '🍃', '🪴', '🏵️', '🌸', '🌹', '🌺', '🌻', '🌼', '🌷', '💐', '🥀',

    // Animals
    '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯', '🦁', '🐮', '🐷', '🐽', '🐸', '🐵', '🙈', '🙉', '🙊', '🐒',
    '🦍', '🦧', '🐔', '🐧', '🐦', '🐤', '🐣', '🐥', '🦆', '🦅', '🦉', '🦇', '🐺', '🐗', '🐴', '🐝', '🪲', '🐛', '🐞', '🦋', '🐌', '🐜', '🐢', '🐍', '🦎', '🦂', '🦗', '🕷️', '🕸️', '🦟', '🐠', '🐟', '🐡', '🦈', '🐬', '🐳', '🐋', '🦭', '🦦', '🦑', '🦐', '🦞', '🦀', '🪼', '🐙', '🐊', '🐅', '🐆', '🦓', '🦒', '🐘', '🦏', '🦛', '🐪', '🐫', '🦙', '🦘', '🐃', '🐂', '🐄', '🐎', '🐖', '🐏', '🐑', '🦢', '🦩', '🦚', '🦜', '🦃', '🐓', '🦤', '🦥', '🦦', '🦨', '🦧', '🦣', '🦫', '🐇', '🦝', '🦡', '🦥', '🦬', '🦦', '🦨', '🦩', '🐉', '🐲', '🪽', '🕊️', '🐦‍⬛', '🐤', '🦢',

    // Faces & People
    '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣', '🥲', '🥹', '😊', '😇', '🙂', '🙃', '😉', '😌', '😍', '🥰', '😘', '😗', '😙', '😚', '😋', '😛', '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🫢', '🫣', '🤫', '🤔', '🫠', '🤐', '🤨', '😐', '😑', '😶', '😶‍🌫️', '😏', '😒', '🙄', '😬', '🤥', '😌', '😔', '😪', '😴', '😷', '🤒', '🤕', '🤢', '🤮', '🤧', '🥵', '🥶', '🥴', '😵', '😵‍💫', '🤯', '🤠', '🥳', '😎', '🤓', '🧐', '😕', '🫤', '😟', '🙁', '☹️', '😮', '😯', '😲', '😳', '🥺', '😦', '😧', '😨', '😰', '😥', '😢', '😭', '😱', '😖', '😣', '😞', '😓', '😩', '😫', '🥱', '😤', '😡', '😠', '🤬', '😈', '👿', '💀', '☠️', '💩', '🤡', '👹', '👺', '👻', '👽', '👾', '🤖', '👶', '🧒', '👦', '👧', '🧑', '👱', '👨', '🧔', '👨‍🦰', '👨‍🦱', '👨‍🦳', '👨‍🦲', '👩', '👩‍🦰', '👩‍🦱', '👩‍🦳', '👩‍🦲', '👱‍♀️', '👱‍♂️', '🧓', '👴', '👵', '🙍‍♂️', '🙍‍♀️', '🙎‍♂️', '🙎‍♀️', '🙅‍♂️', '🙅‍♀️', '🙆‍♂️', '🙆‍♀️', '💁‍♀️', '💁‍♂️', '🙋‍♀️', '🙋‍♂️', '🧏‍♂️', '🧏‍♀️', '🙇‍♂️', '🙇‍♀️', '🤦‍♂️', '🤦‍♀️', '🤷‍♂️', '🤷‍♀️', '🧑‍⚕️', '🧑‍🎓', '🧑‍🏫', '🧑‍⚖️', '🧑‍🌾', '🧑‍🍳', '🧑‍🔧', '🧑‍🏭', '🧑‍💼', '🧑‍🔬', '🧑‍💻', '🧑‍🎤', '🧑‍🎨', '🧑‍✈️', '🧑‍🚀', '🧑‍🚒', '👮‍♀️', '👮‍♂️', '🕵️‍♀️', '🕵️‍♂️', '💂‍♀️', '💂‍♂️', '🥷', '👷‍♀️', '👷‍♂️', '🤴', '👸', '👳‍♂️', '👳‍♀️', '👲', '🧕', '🤵', '👰', '🤰', '🤱', '🫄', '🫃', '🧑‍🍼', '👼', '🎅', '🤶', '🧑‍🎄', '🦸‍♂️', '🦸‍♀️', '🦹‍♂️', '🦹‍♀️', '🧙‍♂️', '🧙‍♀️', '🧚‍♂️', '🧚‍♀️', '🧛‍♂️', '🧛‍♀️', '🧜‍♂️', '🧜‍♀️', '🧝‍♂️', '🧝‍♀️', '🧞‍♂️', '🧞‍♀️', '🧟‍♂️', '🧟‍♀️', '🧌', '🚶‍♂️', '🚶‍♀️', '🧍‍♂️', '🧍‍♀️', '🧎‍♂️', '🧎‍♀️', '🧑‍🦯', '🧑‍🦼', '🧑‍🦽', '🏃‍♂️', '🏃‍♀️', '💃', '🕺', '🧗', '🧗‍♂️', '🧗‍♀️', '🏇', '🏂', '🏌️‍♀️', '🏌️‍♂️', '🏄‍♂️', '🏄‍♀️', '🏊‍♂️', '🏊‍♀️', '🚣‍♂️', '🚣‍♀️',

    // Hand Gestures
    '☝️', '👆', '👇', '👈', '👉', '🖖', '✋', '🤚', '🖐️', '🖑', '🤙', '🫱', '🫲', '🫳', '🫴', '👌', '🤌', '🤏', '✌️', '🤞', '🫰', '🤟', '🤘', '🤙', '👍', '👎', '✊', '👊', '🤛', '🤜', '👏', '🫶', '🙌', '👐', '🤲', '🙏', '🫂', '✍️',
    
    // Objects & Everyday Items
    '💄', '💋', '💍', '💎', '⌚', '📱', '📲', '💻', '⌨️', '🖥️', '🖨️', '🖱️', '🖲️', '🧮', '🎥', '📷', '📹', '📼',
    '☎️', '📞', '📟', '📠', '📺', '📻', '⏰', '⏱️', '⏲️', '🕰️', '🔋', '🔌', '💡', '🔦', '🕯️', '🧯', '🛢️', '🛒', '💳', '💰', '💵', '💴', '💶', '💷', '💸', '🧾', '💼', '📁', '📂', '🗂️', '📅', '📆', '🗒️', '🗓️', '📇', '📈', '📉', '📊', '📋', '📌', '📎', '🖇️', '📏', '📐', '✂️', '🗃️', '🗄️', '🗑️', '🔒', '🔓', '🔏', '🔐', '🔑', '🗝️', '🔨', '🪓', '⛏️', '⚒️', '🛠️', '🗡️', '⚔️', '🔫', '🪃', '🏹', '🛡️', '🔧', '🪛', '🔩', '⚙️', '🛞', '🧱', '⛓️', '🧲', '🪜', '⚗️', '🧪', '🧫', '🧬', '🔬', '🔭', '📡', '💉', '🩸', '💊', '🩹', '🩺',

    // Clothing & Accessories
    '👓', '🕶️', '🥽', '🥼', '🦺', '👔', '👕', '👖', '🧣', '🧤', '🧥', '🧦', '👗', '👘', '🥻', '🩱', '🩲', '🩳', '👙', '👚', '👛', '👜', '👝', '🛍️', '🎒', '🩴', '👞', '👟', '🥾', '🥿', '👠', '👡', '🩰', '👢', '👑', '👒', '🎩', '🎓', '🧢', '🪖', '⛑️', '💄', '💍', '💼', 

    // Music & Arts
    '🎤', '🎧', '🎼', '🎵', '🎶', '🎷', '🎸', '🎹', '🥁', '🎺', '🎻', '🎬', '🎨', '🎭',

    // Celebration & Party
    '🎂', '🎉', '🎊', '🎈', '🎇', '🎆', '✨', '🪄', '🎎', '🎏', '🪅', '🪩', '🎀', '🎁', '🪧', '🧧', '🎐', 

    // Sports & Activities
    '⚽', '⚾', '🏀', '🏐', '🏈', '🏉', '🎱', '🎳', '🥎', '🏓', '🏸', '🏒', '🏑', '🏏', '🥅', '🥊', '🥋', '🥌', '⛳', '⛸️', '🎣', '🎽', '🎿', '🛷', '⛷️', '🏂', '🪂', '🏹', '🧗', '🧗‍♂️', '🧗‍♀️', '🚵', '🚵‍♂️', '🚵‍♀️', '🚴', '🚴‍♂️', '🚴‍♀️', '🏊', '🏊‍♂️', '🏊‍♀️', '🤽', '🤽‍♂️', '🤽‍♀️', '🏄', '🏄‍♂️', '🏄‍♀️', '🧘', '🏋️', '🏋️‍♂️', '🏋️‍♀️', '🤸', '🤸‍♂️', '🤸‍♀️', '⛹️', '⛹️‍♂️', '⛹️‍♀️', '🤼', '🤼‍♂️', '🤼‍♀️', '🤾', '🤾‍♂️', '🤾‍♀️', '🧙‍♂️', '🧙‍♀️', '🎮', '🕹️', '🎲', '🧩', '🧸', '🪁', '🪀', '🎰', '🎯', '🪃', '🛹', '🛼', '🥏', '🪃', '🎠', '🎡', '🥍', 

    // Awards & Achievement
    '🏆', '🏅', '🥇', '🥈', '🥉', '🎫', '🎟️',

    // Science, Education & Office
    '📖', '📚', '📓', '📒', '📔', '📕', '📗', '📘', '📙', '📚', '🧮', '🔬', '🔭', '🛰️', '🔬', '📡', '🧪', '🧫', '🧬', '📝', '✏️', '✒️', '🖋️', '🖊️', '🖌️', '🖍️', '📅', '📆', '🗓️', '📇', '📈', '📉', '📊', '📋', '📌', '📎', '🖇️', 

    // Transportation & Travel
    '🚗', '🚕', '🚙', '🛻', '🚐', '🚚', '🚛', '🚜', '🦽', '🦼', '🛴', '🚲', '🛵', '🏍️', '🛺', '🚔', '🚓', '🚑', '🚒', '🚐', '🚚', '🚛', '🛻', '🚜', '🛴', '🛹', '🛼', '🚂', '🚃', '🚄', '🚅', '🚆', '🚇', '🚈', '🚉', '🚊', '🚝', '🚞', '🚋', '🚌', '🚍', '🚎', '🚐', '🏎️', '🚓', '⛵', '🛥️', '🚤', '🛳️', '⛴️', '🚢', '✈️', '🛩️', '🛫', '🛬', '🪂', '💺', '🚁', '🛰️', '🚀', '🛸', '🪐',

    // Shapes, Symbols, & Miscellaneous
    '❤️', '🩷', '🧡', '💛', '💚', '💙', '🩵', '💜', '🤎', '🖤', '🤍', '🩶', '💔', '❤️‍🔥', '💕', '💞', '💓', '💗', '💖', '💘', '💝', '💟', '🔘', '🔴', '🟠', '🟡', '🟢', '🔵', '🟣', '🟤', '⚫', '⚪', '🟥', '🟧', '🟨', '🟩', '🟦', '🟪', '🟫', '⬛', '⬜', '◼️', '◻️', '◾', '◽', '▪️', '▫️', '◯', '❓', '❔', '❗', '‼️', '⁉️', '✔️', '☑️', '✅', '❌', '✖️', '➕', '➖', '➗', '✳️', '✴️', '➰', '➿', '〽️', '💲', '💯', '♠️', '♥️', '♦️', '♣️', '🃏', '🀄', '🎴', '🔔', '🔕', '🔒', '🔓', '🔏', '🔐', '🔑', '🗝️', '⚓', '🚬', '🪦', '⚖️', '♀️', '♂️', '⚧️',

    // Weather
    '☀️', '🌤️', '⛅', '⛈️', '🌩️', '🌧️', '🌨️', '❄️', '☁️', '🌦️', '🌪️', '🌫️', '🌬️', '🌈', '☃️', '🌂', '☔', '💧', '💦', '🫧',

    // Flags
    // National flags
    '🇦🇫','🇦🇱','🇩🇿','🇦🇩','🇦🇴','🇦🇬','🇦🇷','🇦🇲','🇦🇺','🇦🇹','🇦🇿','🇧🇸','🇧🇭','🇧🇩','🇧🇧','🇧🇾','🇧🇪','🇧🇿','🇧🇯','🇧🇹','🇧🇴','🇧🇦','🇧🇼','🇧🇷','🇧🇳','🇧🇬','🇧🇫','🇧🇮','🇨🇻','🇰🇭','🇨🇲','🇨🇦','🇨🇫','🇹🇩','🇨🇱','🇨🇳','🇨🇴','🇰🇲','🇨🇬','🇨🇩','🇨🇷','🇭🇷','🇨🇺','🇨🇾','🇨🇿','🇩🇰','🇩🇯','🇩🇲','🇩🇴','🇪🇨','🇪🇬','🇸🇻','🇬🇶','🇪🇷','🇪🇪','🇪🇸','🇪🇹','🇫🇲','🇫🇮','🇫🇷','🇬🇦','🇬🇲','🇬🇪','🇩🇪','🇬🇭','🇬🇷','🇬🇩','🇬🇹','🇬🇳','🇬🇼','🇬🇾','🇭🇹','🇭🇳','🇭🇺','🇮🇸','🇮🇳','🇮🇩','🇮🇷','🇮🇶','🇮🇪','🇮🇱','🇮🇹','🇯🇲','🇯🇵','🇯🇴','🇰🇿','🇰🇪','🇰🇮','🇰🇵','🇰🇷','🇽🇰','🇰🇼','🇰🇬','🇱🇦','🇱🇻','🇱🇧','🇱🇸','🇱🇷','🇱🇾','🇱🇮','🇱🇹','🇱🇺','🇲🇬','🇲🇼','🇲🇾','🇲🇻','🇲🇱','🇲🇹','🇲🇭','🇲🇷','🇲🇺','🇲🇽','🇲🇩','🇲🇨','🇲🇳','🇲🇪','🇲🇦','🇲🇿','🇲🇲','🇳🇦','🇳🇷','🇳🇵','🇳🇱','🇳🇿','🇳🇮','🇳🇪','🇳🇬','🇳🇴','🇴🇲','🇵🇰','🇵🇼','🇵🇸','🇵🇦','🇵🇬','🇵🇾','🇵🇪','🇵🇭','🇵🇱','🇵🇹','🇶🇦','🇷🇴','🇷🇺','🇷🇼','🇰🇳','🇱🇨','🇻🇨','🇼🇸','🇸🇲','🇸🇹','🇸🇦','🇸🇳','🇷🇸','🇸🇨','🇸🇱','🇸🇬','🇸🇰','🇸🇮','🇸🇧','🇸🇴','🇿🇦','🇸🇸','🇪🇸','🇱🇰','🇸🇩','🇸🇷','🇸🇪','🇨🇭','🇸🇾','🇹🇼','🇹🇯','🇹🇿','🇹🇭','🇹🇱','🇹🇬','🇹🇴','🇹🇹','🇹🇳','🇹🇷','🇹🇲','🇹🇻','🇺🇬','🇺🇦','🇦🇪','🇬🇧','🇺🇸','🇺🇾','🇺🇿','🇻🇺','🇻🇦','🇻🇪','🇻🇳','🇾🇪','🇿🇲','🇿🇼',
    // Popular non-national flags
    '🏳️‍🌈','🏴‍☠️','🏳️','🏁','🚩','🏴','🏳️‍⚧️','🏳️‍🌈',

  ];

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _nameController.text = widget.categoryToEdit!.name;
      _selectedIcon = widget.categoryToEdit!.icon;
      _isPrivate = widget.categoryToEdit!.isPrivate;
      if (!_emojiOptions.contains(_selectedIcon)) {
        _selectedIcon = _emojiOptions.isNotEmpty ? _emojiOptions.first : '';
      }
    } else if (_emojiOptions.isNotEmpty) {
      _selectedIcon = _emojiOptions.first;
      _isPrivate = false;
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
        UserCategory resultCategory;
        if (_isEditing) {
          final updatedCategory = widget.categoryToEdit!.copyWith(
            name: name,
            icon: icon,
            isPrivate: _isPrivate,
          );
          await _experienceService.updateUserCategory(updatedCategory);
          resultCategory = updatedCategory;
          print("Category updated: ${resultCategory.name}");
        } else {
          resultCategory = await _experienceService.addUserCategory(
            name,
            icon,
            isPrivate: _isPrivate,
          );
          print("Category added: ${resultCategory.name}");
        }

        if (mounted) {
          Navigator.of(context).pop(resultCategory);
        }
      } catch (e) {
        print("Error saving category: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Error ${_isEditing ? "updating" : "adding"} category: ${e.toString()}')),
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

    return Material(
      color: Colors.white,
      child: SingleChildScrollView(
        child: Padding(
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
                  Text(
                    _isEditing ? 'Edit Category' : 'Create a New Category',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Cancel',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PrivacyToggleButton(
                      isPrivate: _isPrivate,
                      onPressed: () {
                        setState(() {
                          _isPrivate = !_isPrivate;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: _isEditing
                      ? 'Edit category name'
                      : 'Name your new category',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                textCapitalization: TextCapitalization.sentences,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a category name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Select Icon',
                style: Theme.of(context).textTheme.titleMedium,
              ),
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
                      onTap: withHeavyTap(() {
                        setState(() {
                          _selectedIcon = emoji;
                        });
                      }),
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
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    _isLoading
                        ? 'Saving...'
                        : _isEditing
                            ? 'Update Category'
                            : 'Save Category',
                  ),
                  onPressed: _isLoading ? null : _saveCategory,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
