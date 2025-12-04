import 'package:flutter/material.dart';

/// A modal dialog for writing or editing a review
class WriteReviewModal extends StatefulWidget {
  final bool? initialRating; // true = thumbs up, false = thumbs down, null = no selection
  final String initialContent;
  final bool isEditing;
  final Function(bool? isPositive, String content) onSubmit;

  const WriteReviewModal({
    super.key,
    this.initialRating,
    this.initialContent = '',
    this.isEditing = false,
    required this.onSubmit,
  });

  @override
  State<WriteReviewModal> createState() => _WriteReviewModalState();
}

class _WriteReviewModalState extends State<WriteReviewModal> {
  static const int _maxCharacters = 5000;
  
  late TextEditingController _contentController;
  bool? _selectedRating;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.initialContent);
    _selectedRating = widget.initialRating;
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
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
      await widget.onSubmit(_selectedRating, content);
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        padding: const EdgeInsets.all(20),
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
              'How was your experience? (Optional)',
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
                  onTap: _isSubmitting ? null : () {
                    setState(() {
                      _selectedRating = _selectedRating == true ? null : true;
                    });
                  },
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
                  onTap: _isSubmitting ? null : () {
                    setState(() {
                      _selectedRating = _selectedRating == false ? null : false;
                    });
                  },
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
            Expanded(
              child: TextField(
                controller: _contentController,
                maxLines: null,
                expands: true,
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
    );
  }
}

