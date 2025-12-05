import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/review.dart';
import '../models/experience.dart';
import '../models/user_category.dart';
import '../models/color_category.dart';
import '../services/experience_service.dart';
import '../widgets/write_review_modal.dart';
import 'experience_page_screen.dart';

// Helper function to parse hex color string
Color _parseColor(String hexColor) {
  hexColor = hexColor.toUpperCase().replaceAll("#", "");
  if (hexColor.length == 6) {
    hexColor = "FF$hexColor"; // Add alpha if missing
  }
  if (hexColor.length == 8) {
    try {
      return Color(int.parse("0x$hexColor"));
    } catch (e) {
      return Colors.grey; // Default color on parsing error
    }
  }
  return Colors.grey; // Default color on invalid format
}

class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key});

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  final ExperienceService _experienceService = ExperienceService();

  List<Review> _userReviews = [];
  bool _isLoading = true;

  // Cache for experience data associated with reviews
  final Map<String, Experience> _reviewExperienceCache = {};
  // Cache for categories from experience owners
  final Map<String, UserCategory> _categoryCache = {};
  final Map<String, ColorCategory> _colorCategoryCache = {};

  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _loadUserReviews();
  }

  /// Load reviews posted by the current user
  Future<void> _loadUserReviews() async {
    if (!mounted || _currentUserId == null) return;

    setState(() => _isLoading = true);

    try {
      final reviews = await _experienceService.getReviewsByUser(_currentUserId!);

      // Fetch experience data for each review
      final Set<String> experienceIds = reviews
          .map((r) => r.experienceId)
          .where((id) => id.isNotEmpty)
          .toSet();

      for (final expId in experienceIds) {
        if (!_reviewExperienceCache.containsKey(expId)) {
          try {
            final experience = await _experienceService.getExperience(expId);
            if (experience != null) {
              _reviewExperienceCache[expId] = experience;

              // If denormalized fields are missing, fetch category from owner
              await _fetchExperienceCategoryIfNeeded(experience);
            }
          } catch (e) {
            debugPrint(
                'ReviewsScreen: Could not load experience $expId for review - $e');
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _userReviews = reviews;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('ReviewsScreen: error loading user reviews - $e');
      if (!mounted) return;
      setState(() {
        _userReviews = [];
        _isLoading = false;
      });
    }
  }

  /// Fetch category and color category from experience owner if denormalized fields are missing
  Future<void> _fetchExperienceCategoryIfNeeded(Experience experience) async {
    final ownerId = experience.createdBy;
    if (ownerId == null || ownerId.isEmpty) return;

    // Check if we need to fetch category
    final bool needsCategory = (experience.categoryIconDenorm == null ||
            experience.categoryIconDenorm!.isEmpty) &&
        experience.categoryId != null &&
        experience.categoryId!.isNotEmpty &&
        !_categoryCache.containsKey(experience.categoryId);

    // Check if we need to fetch color category
    final bool needsColorCategory = (experience.colorHexDenorm == null ||
            experience.colorHexDenorm!.isEmpty) &&
        experience.colorCategoryId != null &&
        experience.colorCategoryId!.isNotEmpty &&
        !_colorCategoryCache.containsKey(experience.colorCategoryId);

    if (!needsCategory && !needsColorCategory) return;

    try {
      // Fetch category from owner's categories subcollection
      if (needsCategory && experience.categoryId != null) {
        final categoryDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(ownerId)
            .collection('categories')
            .doc(experience.categoryId)
            .get();

        if (categoryDoc.exists) {
          final category = UserCategory.fromFirestore(categoryDoc);
          _categoryCache[experience.categoryId!] = category;
        }
      }

      // Fetch color category from owner's color_categories subcollection
      if (needsColorCategory && experience.colorCategoryId != null) {
        final colorCategoryDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(ownerId)
            .collection('color_categories')
            .doc(experience.colorCategoryId)
            .get();

        if (colorCategoryDoc.exists) {
          final colorCategory = ColorCategory.fromFirestore(colorCategoryDoc);
          _colorCategoryCache[experience.colorCategoryId!] = colorCategory;
        }
      }
    } catch (e) {
      debugPrint(
          'ReviewsScreen: Could not load category for experience ${experience.id} - $e');
    }
  }

  /// Format a DateTime as a human-readable time ago string
  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 365) {
      final years = (difference.inDays / 365).floor();
      return '$years ${years == 1 ? 'year' : 'years'} ago';
    } else if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    } else {
      return 'Just now';
    }
  }

  /// Build the header showing total review count
  Widget _buildReviewCountHeader(int count) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: const BoxDecoration(color: Colors.white),
      child: Text(
        '$count ${count == 1 ? 'Review' : 'Reviews'}',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w400,
              color: Colors.grey,
            ),
        textAlign: TextAlign.center,
      ),
    );
  }

  /// Build a review card showing experience info
  Widget _buildReviewCard(Review review) {
    final experience = _reviewExperienceCache[review.experienceId];
    final timeAgo = _formatTimeAgo(review.createdAt);

    // Get category icon and color from experience
    String categoryIcon = '📍';
    Color leadingBoxColor = Colors.grey.withOpacity(0.3);

    if (experience != null) {
      // Try to get icon from denormalized field first
      if (experience.categoryIconDenorm != null &&
          experience.categoryIconDenorm!.isNotEmpty) {
        categoryIcon = experience.categoryIconDenorm!;
      } else if (experience.categoryId != null) {
        final category = _categoryCache[experience.categoryId];
        if (category != null) {
          categoryIcon = category.icon;
        }
      }

      // Get color from denormalized field first
      if (experience.colorHexDenorm != null &&
          experience.colorHexDenorm!.isNotEmpty) {
        leadingBoxColor =
            _parseColor(experience.colorHexDenorm!).withOpacity(0.5);
      } else if (experience.colorCategoryId != null) {
        final colorCategory = _colorCategoryCache[experience.colorCategoryId];
        if (colorCategory != null) {
          leadingBoxColor = colorCategory.color.withOpacity(0.5);
        }
      }
    }

    // Experience name and address
    final String experienceName = experience?.name ?? 'Unknown Experience';
    final String? experienceAddress = experience?.location.address;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 1,
      color: const Color.fromARGB(225, 250, 250, 250),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Category icon box, Experience name, Address, Time, Menu
            Row(
              children: [
                // Tappable experience info
                Expanded(
                  child: InkWell(
                    onTap: experience != null
                        ? () => _navigateToExperience(experience)
                        : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      children: [
                        // Category icon box
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: leadingBoxColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            categoryIcon,
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Experience Name and Address
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                experienceName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (experienceAddress != null &&
                                  experienceAddress.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  experienceAddress,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              const SizedBox(height: 2),
                              Text(
                                timeAgo,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Rating Icon and Menu
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (review.isPositive != null)
                      Icon(
                        review.isPositive! ? Icons.thumb_up : Icons.thumb_down,
                        color: review.isPositive! ? Colors.green : Colors.red,
                        size: 18,
                      ),
                    // Three-dot menu for edit/delete
                    PopupMenuButton<String>(
                      color: Colors.white,
                      icon: const Icon(Icons.more_vert, size: 20),
                      onSelected: (value) {
                        if (value == 'edit') {
                          _showEditReviewModal(review);
                        } else if (value == 'delete') {
                          _confirmDeleteReview(review);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: 18),
                              SizedBox(width: 8),
                              Text('Edit'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, size: 18, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Delete', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Review Content
            Text(
              review.content,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
              ),
            ),
            // Review Photos
            if (review.imageUrls.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildReviewPhotoGallery(review.imageUrls),
            ],
          ],
        ),
      ),
    );
  }

  /// Navigate to experience page from a review card
  Future<void> _navigateToExperience(Experience experience) async {
    // Find the category for this experience
    UserCategory? category;
    if (experience.categoryId != null) {
      category = _categoryCache[experience.categoryId];
    }

    // Create a fallback category if not found
    final UserCategory displayCategory = category ??
        UserCategory(
          id: experience.categoryId ?? '',
          name: 'Uncategorized',
          icon: experience.categoryIconDenorm ?? '📍',
          ownerUserId: experience.createdBy ?? '',
        );

    // Get color categories for this experience
    List<ColorCategory> colorCategories = [];
    if (experience.colorCategoryId != null) {
      final colorCategory = _colorCategoryCache[experience.colorCategoryId];
      if (colorCategory != null) {
        colorCategories = [colorCategory];
      }
    }

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => ExperiencePageScreen(
          experience: experience,
          category: displayCategory,
          userColorCategories: colorCategories,
          additionalUserCategories: category != null ? [category] : [],
          readOnlyPreview: true,
        ),
      ),
    );

    // Refresh reviews if something changed
    if (result == true) {
      _loadUserReviews();
    }
  }

  /// Build a photo gallery for review images
  Widget _buildReviewPhotoGallery(List<String> imageUrls) {
    if (imageUrls.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: imageUrls.length,
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: () => _showFullScreenImage(imageUrls, index),
            child: Container(
              width: 80,
              height: 80,
              margin:
                  EdgeInsets.only(right: index < imageUrls.length - 1 ? 8 : 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                image: DecorationImage(
                  image: NetworkImage(imageUrls[index]),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Show full screen image viewer
  void _showFullScreenImage(List<String> imageUrls, int initialIndex) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: PageController(initialPage: initialIndex),
              itemCount: imageUrls.length,
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  child: Center(
                    child: Image.network(
                      imageUrls[index],
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shows the edit review modal
  void _showEditReviewModal(Review review) {
    showDialog(
      context: context,
      builder: (context) => WriteReviewModal(
        initialRating: review.isPositive,
        initialContent: review.content,
        initialImageUrls: review.imageUrls,
        isEditing: true,
        onSubmit: (isPositive, content, newImages, existingImageUrls) =>
            _handleReviewUpdate(review, isPositive, content, newImages, existingImageUrls),
      ),
    );
  }

  /// Uploads review images to Firebase Storage and returns the download URLs
  Future<List<String>> _uploadReviewImages(List<File> images, String reviewId) async {
    final List<String> uploadedUrls = [];

    for (int i = 0; i < images.length; i++) {
      final file = images[i];
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
      final ref = FirebaseStorage.instance
          .ref()
          .child('review_photos')
          .child(reviewId)
          .child(fileName);

      await ref.putFile(file);
      final url = await ref.getDownloadURL();
      uploadedUrls.add(url);
    }

    return uploadedUrls;
  }

  /// Handles review update
  Future<void> _handleReviewUpdate(
    Review review,
    bool? isPositive,
    String content,
    List<File> newImages,
    List<String> existingImageUrls,
  ) async {
    try {
      // Upload new images
      List<String> newImageUrls = [];
      if (newImages.isNotEmpty) {
        newImageUrls = await _uploadReviewImages(newImages, review.id);
      }

      // Combine existing and new image URLs
      final allImageUrls = [...existingImageUrls, ...newImageUrls];

      // Update review
      final updatedReview = review.copyWith(
        isPositive: isPositive,
        content: content,
        imageUrls: allImageUrls,
        updatedAt: DateTime.now(),
      );
      await _experienceService.updateReview(updatedReview);

      // Refresh reviews list
      await _loadUserReviews();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Review updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update review: $e')),
        );
      }
      rethrow;
    }
  }

  /// Shows confirmation dialog before deleting a review
  Future<void> _confirmDeleteReview(Review review) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Delete Review'),
        content: const Text(
            'Are you sure you want to delete your review? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _experienceService.deleteReview(review);
        await _loadUserReviews();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Review deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete review: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: const Text('My Reviews'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _userReviews.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.rate_review_outlined,
                          size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No reviews yet',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Reviews you write will appear here',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadUserReviews,
                  child: ListView.builder(
                    itemCount: _userReviews.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _buildReviewCountHeader(_userReviews.length);
                      }
                      final review = _userReviews[index - 1];
                      return _buildReviewCard(review);
                    },
                  ),
                ),
    );
  }
}
