import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:plendy/utils/haptic_feedback.dart';

/// A modal dialog for writing or editing a review
class WriteReviewModal extends StatefulWidget {
  final bool? initialRating; // true = thumbs up, false = thumbs down, null = no selection
  final String initialContent;
  final List<String> initialImageUrls; // Existing image URLs (for editing)
  final bool isEditing;
  final Function(bool? isPositive, String content, List<File> newImages, List<String> existingImageUrls) onSubmit;

  const WriteReviewModal({
    super.key,
    this.initialRating,
    this.initialContent = '',
    this.initialImageUrls = const [],
    this.isEditing = false,
    required this.onSubmit,
  });

  @override
  State<WriteReviewModal> createState() => _WriteReviewModalState();
}

class _WriteReviewModalState extends State<WriteReviewModal> {
  static const int _maxCharacters = 5000;
  static const int _maxImages = 5;
  
  late TextEditingController _contentController;
  bool? _selectedRating;
  bool _isSubmitting = false;
  
  // Image management
  final List<File> _newImages = []; // New images to upload
  late List<String> _existingImageUrls; // Existing image URLs (for editing)
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.initialContent);
    _selectedRating = widget.initialRating;
    _existingImageUrls = List<String>.from(widget.initialImageUrls);
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  int get _totalImageCount => _newImages.length + _existingImageUrls.length;

  Future<void> _pickImages() async {
    if (_totalImageCount >= _maxImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Maximum $_maxImages photos allowed')),
      );
      return;
    }

    final remainingSlots = _maxImages - _totalImageCount;
    
    try {
      final List<XFile> images = await _picker.pickMultiImage(
        imageQuality: 80,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (images.isNotEmpty) {
        final imagesToAdd = images.take(remainingSlots).toList();
        setState(() {
          _newImages.addAll(imagesToAdd.map((x) => File(x.path)));
        });

        if (images.length > remainingSlots) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Only added $remainingSlots photos (max $_maxImages)')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick images: $e')),
        );
      }
    }
  }

  void _removeNewImage(int index) {
    setState(() {
      _newImages.removeAt(index);
    });
  }

  void _removeExistingImage(int index) {
    setState(() {
      _existingImageUrls.removeAt(index);
    });
  }

  void _handleSubmit() async {
    final content = _contentController.text.trim();
    
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please write a review before submitting')),
      );
      return;
    }

    if (content.length > _maxCharacters) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Review must be $_maxCharacters characters or less')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    
    try {
      await widget.onSubmit(_selectedRating, content, _newImages, _existingImageUrls);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit review: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final characterCount = _contentController.text.length;
    final isOverLimit = characterCount > _maxCharacters;

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
          final availableHeight = MediaQuery.of(context).size.height - keyboardHeight - 100; // Account for dialog margins

          return Container(
            constraints: BoxConstraints(
              maxWidth: 650,
              maxHeight: availableHeight > 400 ? availableHeight : 400, // Minimum height of 400
            ),
            padding: const EdgeInsets.all(20),
            child: GestureDetector(
              onTap: withHeavyTap(() => FocusScope.of(context).unfocus()),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.isEditing ? 'Edit Review' : 'Write a Review',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Rating Selection
            Text(
              'Do you recommend this experience? (Optional)',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Thumbs Up
                GestureDetector(
                  onTap: withHeavyTap(_isSubmitting ? null : () {
                    setState(() {
                      _selectedRating = _selectedRating == true ? null : true;
                    });
                  }),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: _selectedRating == true
                          ? Colors.green.withOpacity(0.2)
                          : Colors.grey.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _selectedRating == true
                            ? Colors.green
                            : Colors.grey.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      _selectedRating == true
                          ? Icons.thumb_up
                          : Icons.thumb_up_outlined,
                      color: _selectedRating == true
                          ? Colors.green
                          : Colors.grey,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                // Thumbs Down
                GestureDetector(
                  onTap: withHeavyTap(_isSubmitting ? null : () {
                    setState(() {
                      _selectedRating = _selectedRating == false ? null : false;
                    });
                  }),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: _selectedRating == false
                          ? Colors.red.withOpacity(0.2)
                          : Colors.grey.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _selectedRating == false
                            ? Colors.red
                            : Colors.grey.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      _selectedRating == false
                          ? Icons.thumb_down
                          : Icons.thumb_down_outlined,
                      color: _selectedRating == false
                          ? Colors.red
                          : Colors.grey,
                      size: 32,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Review Text Input
            ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: 120,
                maxHeight: 200,
              ),
              child: TextField(
                controller: _contentController,
                maxLines: null,
                minLines: 5,
                textAlignVertical: TextAlignVertical.top,
                enabled: !_isSubmitting,
                decoration: InputDecoration(
                  hintText: 'Share your experience...',
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Theme.of(context).primaryColor),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 8),
            
            // Character Count
            Text(
              '$characterCount / $_maxCharacters',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: isOverLimit ? Colors.red : Colors.grey[600],
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            
            // Photo Section
            _buildPhotoSection(),
            const SizedBox(height: 16),
            
            // Submit Button
            ElevatedButton(
              onPressed: _isSubmitting || isOverLimit ? null : _handleSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      widget.isEditing ? 'Update Review' : 'Post Review',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
                ],
              ),
            ),
          ),
        );
        },
      ),
    );
  }

  Widget _buildPhotoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with Add Photos button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Photos ($_totalImageCount/$_maxImages)',
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (_totalImageCount < _maxImages)
              TextButton.icon(
                onPressed: _isSubmitting ? null : _pickImages,
                icon: const Icon(Icons.add_photo_alternate, size: 20),
                label: const Text('Add Photos'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        
        // Photo Grid
        if (_totalImageCount > 0)
          SizedBox(
            height: 80,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                // Existing images (URLs)
                ..._existingImageUrls.asMap().entries.map((entry) {
                  return _buildImageThumbnail(
                    child: Image.network(
                      entry.value,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                    ),
                    onRemove: () => _removeExistingImage(entry.key),
                  );
                }),
                // New images (Files)
                ..._newImages.asMap().entries.map((entry) {
                  return _buildImageThumbnail(
                    child: Image.file(
                      entry.value,
                      fit: BoxFit.cover,
                    ),
                    onRemove: () => _removeNewImage(entry.key),
                  );
                }),
              ],
            ),
          )
        else
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
            ),
            child: InkWell(
              onTap: withHeavyTap(_isSubmitting ? null : _pickImages),
              borderRadius: BorderRadius.circular(12),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate, color: Colors.grey[500], size: 28),
                    const SizedBox(height: 4),
                    Text(
                      'Add photos to your review',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildImageThumbnail({required Widget child, required VoidCallback onRemove}) {
    return Container(
      width: 80,
      height: 80,
      margin: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 80,
              height: 80,
              child: child,
            ),
          ),
          // Remove button
          if (!_isSubmitting)
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: withHeavyTap(onRemove),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
