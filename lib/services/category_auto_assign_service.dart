import 'package:collection/collection.dart';
import '../models/user_category.dart';
import '../models/color_category.dart';
import '../models/extracted_location_data.dart';
import 'gemini_service.dart';
import 'google_maps_service.dart';

/// Service for automatically assigning categories to experiences based on location data.
/// 
/// This service provides methods to determine the best primary category and color category
/// for a location based on:
/// 1. Google Places API types (for ExtractedLocationData)
/// 2. Location name keyword matching
/// 3. AI-based fallback using Gemini Flash
class CategoryAutoAssignService {
  static final CategoryAutoAssignService _instance = CategoryAutoAssignService._internal();
  
  factory CategoryAutoAssignService() => _instance;
  
  CategoryAutoAssignService._internal();

  final GeminiService _geminiService = GeminiService();
  final GoogleMapsService _mapsService = GoogleMapsService();

  /// Mapping of Google Places API types to common category names.
  /// Maps various place types to the most likely user category.
  static const Map<String, List<String>> _placeTypeToCategoryMapping = {
    'restaurant': ['restaurant', 'meal_delivery', 'meal_takeaway', 'food'],
    'cafe': ['cafe', 'coffee_shop', 'coffee'],
    'bar': ['bar', 'night_club', 'nightclub', 'pub', 'wine_bar', 'brewery'],
    'museum': ['museum', 'art_gallery', 'library', 'cultural'],
    'theater': ['movie_theater', 'performing_arts_theater', 'theater', 'cinema'],
    'park': ['park', 'zoo', 'aquarium', 'amusement_park', 'nature_reserve', 'botanical_garden', 'campground'],
    'event': ['event_venue', 'stadium', 'arena', 'convention_center', 'concert_hall'],
    'attraction': ['tourist_attraction', 'landmark', 'historical_landmark', 'monument', 'place_of_worship'],
    'stay': ['lodging', 'hotel', 'motel', 'resort', 'hostel', 'bed_and_breakfast', 'guest_house', 'vacation_rental'],
    'dessert': ['bakery', 'ice_cream_shop', 'dessert_shop', 'candy_store', 'pastry_shop'],
    'shopping': ['shopping_mall', 'shopping_center', 'department_store', 'clothing_store', 'shoe_store', 'jewelry_store', 'electronics_store', 'furniture_store', 'home_goods_store'],
    'store': ['store', 'supermarket', 'grocery_or_supermarket', 'convenience_store', 'liquor_store', 'book_store'],
    'other': ['establishment', 'point_of_interest'],
  };

  /// Priority ranking for place types when multiple matches are found.
  /// Lower number = higher priority. Types not listed default to priority 50.
  /// This ensures more specific/meaningful categories are preferred over generic ones.
  static const Map<String, int> _placeTypePriority = {
    // Highest priority - very specific place types
    'restaurant': 1,
    'bar': 2,
    'museum': 3,
    'theater': 4,
    'movie_theater': 4,
    'park': 5,
    'zoo': 5,
    'aquarium': 5,
    'hotel': 6,
    'lodging': 6,
    'resort': 6,
    // Medium-high priority - still specific
    'bakery': 10,
    'ice_cream_shop': 10,
    'dessert_shop': 10,
    'cafe': 15,  // Lower than restaurant - often a secondary type
    'coffee_shop': 15,
    'night_club': 16,
    'brewery': 17,
    // Medium priority - somewhat generic
    'tourist_attraction': 20,
    'landmark': 21,
    'stadium': 22,
    'arena': 22,
    // Medium-low priority - somewhat generic but still meaningful
    'shopping_mall': 25,
    'shopping_center': 25,
    'department_store': 26,
    'clothing_store': 27,
    'store': 30,
    // Low priority - very generic types
    'food': 40,
    'point_of_interest': 45,
    'establishment': 50,
  };

  /// Keyword-to-category mapping for location name matching.
  static const Map<String, String> _keywordToCategoryMap = {
    // Restaurant keywords
    'restaurant': 'restaurant',
    'grill': 'restaurant',
    'kitchen': 'restaurant',
    'bistro': 'restaurant',
    'diner': 'restaurant',
    'eatery': 'restaurant',
    'pizzeria': 'restaurant',
    'trattoria': 'restaurant',
    'sushi': 'restaurant',
    'steakhouse': 'restaurant',
    'seafood': 'restaurant',
    'bbq': 'restaurant',
    'barbecue': 'restaurant',
    'taqueria': 'restaurant',
    'ramen': 'restaurant',
    'pho': 'restaurant',
    'thai': 'restaurant',
    'chinese': 'restaurant',
    'mexican': 'restaurant',
    'italian': 'restaurant',
    'indian': 'restaurant',
    'korean': 'restaurant',
    'japanese': 'restaurant',
    'vietnamese': 'restaurant',
    // Cafe keywords
    'cafe': 'cafe',
    'café': 'cafe',
    'coffee': 'cafe',
    'espresso': 'cafe',
    'roastery': 'cafe',
    'tea house': 'cafe',
    'teahouse': 'cafe',
    // Bar keywords
    'bar': 'bar',
    'pub': 'bar',
    'tavern': 'bar',
    'brewery': 'bar',
    'taproom': 'bar',
    'lounge': 'bar',
    'cocktail': 'bar',
    'wine bar': 'bar',
    'saloon': 'bar',
    // Museum keywords
    'museum': 'museum',
    'gallery': 'museum',
    'exhibit': 'museum',
    'art center': 'museum',
    // Theater keywords
    'theater': 'theater',
    'theatre': 'theater',
    'cinema': 'theater',
    'playhouse': 'theater',
    'concert hall': 'theater',
    // Hike keywords (check before park - trailheads should be hikes, not parks)
    'trailhead': 'hike',
    'trail head': 'hike',
    'hiking trail': 'hike',
    'hiking': 'hike',
    'hike': 'hike',
    'trek': 'hike',
    'summit': 'hike',
    'peak': 'hike',
    // Outdoor keywords (for users who have "Outdoor" instead of "Hike")
    'outdoor': 'outdoor',
    'campground': 'outdoor',
    'campsite': 'outdoor',
    'camping': 'outdoor',
    // Park keywords
    'park': 'park',
    'garden': 'park',
    'botanical': 'park',
    'nature reserve': 'park',
    'wildlife': 'park',
    'zoo': 'park',
    'aquarium': 'park',
    'trail': 'park',  // Generic "trail" falls back to park if no "hike" category
    // Event keywords
    'arena': 'event',
    'stadium': 'event',
    'convention': 'event',
    'expo': 'event',
    'fairground': 'event',
    // Attraction keywords
    'landmark': 'attraction',
    'monument': 'attraction',
    'memorial': 'attraction',
    'tower': 'attraction',
    'observation': 'attraction',
    'viewpoint': 'attraction',
    'beach': 'attraction',
    // Stay keywords
    'hotel': 'stay',
    'motel': 'stay',
    'resort': 'stay',
    'inn': 'stay',
    'hostel': 'stay',
    'lodge': 'stay',
    'suites': 'stay',
    'airbnb': 'stay',
    // Dessert keywords
    'bakery': 'dessert',
    'pastry': 'dessert',
    'ice cream': 'dessert',
    'gelato': 'dessert',
    'donut': 'dessert',
    'doughnut': 'dessert',
    'cupcake': 'dessert',
    'cake': 'dessert',
    'sweets': 'dessert',
    'candy': 'dessert',
    'chocolate': 'dessert',
    // Shopping keywords
    'mall': 'shopping',
    'shopping center': 'shopping',
    'town center': 'shopping',
    'shopping plaza': 'shopping',
    'plaza': 'shopping',
    'outlet': 'shopping',
    'marketplace': 'shopping',
    'market': 'shopping',
    'boutique': 'shopping',
  };

  /// Find the "Want to go" color category from the user's categories.
  /// Returns the category ID if found, otherwise returns null.
  String? getWantToGoColorCategoryId(List<ColorCategory> colorCategories) {
    final wantToGoCategory = colorCategories.firstWhereOrNull(
      (cat) => cat.name.toLowerCase() == 'want to go',
    );
    return wantToGoCategory?.id;
  }

  /// Determine the best primary category for an extracted location.
  /// 
  /// Uses a multi-step approach:
  /// 1. Direct match of Places API types to user category names
  /// 2. Mapping-based match using predefined type-to-category mappings
  /// 3. Match based on PlaceType enum
  /// 4. AI-based categorization as fallback (if enabled)
  Future<String?> determineBestCategoryForExtractedLocation(
    ExtractedLocationData locationData,
    List<UserCategory> userCategories, {
    bool useAiFallback = true,
  }) async {
    if (userCategories.isEmpty) return null;

    final placeTypes = locationData.placeTypes ?? [];
    final placeType = locationData.type;
    final locationName = locationData.name;
    
    print('🏷️ CATEGORY MATCH: Determining category for "$locationName"');
    print('   📋 Place types: ${placeTypes.take(5).join(', ')}');
    print('   📋 PlaceType enum: ${placeType.name}');
    
    // Build a lowercase lookup map for user categories
    final categoryLookup = <String, String>{}; // lowercase name -> category ID
    for (final cat in userCategories) {
      categoryLookup[cat.name.toLowerCase()] = cat.id;
    }
    
    // Step 0: Check location name keywords FIRST (more semantic than place types)
    // This catches cases like "Trailhead" → "Hike" even when Google says it's a "park"
    final nameLower = locationName.toLowerCase();
    for (final entry in _keywordToCategoryMap.entries) {
      if (nameLower.contains(entry.key)) {
        final categoryName = entry.value;
        if (categoryLookup.containsKey(categoryName)) {
          print('   ✅ Name keyword match: "${entry.key}" in name → "$categoryName"');
          return categoryLookup[categoryName];
        }
      }
    }
    
    // Step 1: Direct match - collect all placeTypes that match user category names
    // Then select the highest priority match (avoids "cafe" being selected over "restaurant")
    final directMatches = <String, int>{}; // categoryId -> priority
    for (final type in placeTypes) {
      final normalizedType = type.toLowerCase().replaceAll('_', ' ');
      if (categoryLookup.containsKey(normalizedType)) {
        final categoryId = categoryLookup[normalizedType]!;
        final priority = _placeTypePriority[type.toLowerCase()] ?? 50;
        // Only keep the highest priority (lowest number) for each category
        if (!directMatches.containsKey(categoryId) || priority < directMatches[categoryId]!) {
          directMatches[categoryId] = priority;
        }
      }
    }
    
    if (directMatches.isNotEmpty) {
      // Select the category with the highest priority (lowest number)
      final sortedMatches = directMatches.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final bestCategoryId = sortedMatches.first.key;
      final bestCategory = userCategories.firstWhere((c) => c.id == bestCategoryId);
      
      if (directMatches.length > 1) {
        final allMatches = directMatches.keys.map((id) => 
          userCategories.firstWhere((c) => c.id == id).name).toList();
        print('   🎯 Multiple direct matches found: ${allMatches.join(', ')}');
        print('   ✅ Selected highest priority: "${bestCategory.name}" (priority: ${sortedMatches.first.value})');
      } else {
        print('   ✅ Direct match found: "${bestCategory.name}"');
      }
      return bestCategoryId;
    }
    
    // Step 2: Mapping-based match - use predefined mappings with priority
    final mappingMatches = <String, int>{}; // categoryId -> priority
    for (final entry in _placeTypeToCategoryMapping.entries) {
      final categoryName = entry.key.toLowerCase();
      final matchingTypes = entry.value;
      
      // Check if any of the location's placeTypes match this category's types
      for (final type in placeTypes) {
        final normalizedType = type.toLowerCase();
        if (matchingTypes.any((t) => normalizedType.contains(t) || t.contains(normalizedType))) {
          // Found a mapping match, now check if user has this category
          if (categoryLookup.containsKey(categoryName)) {
            final categoryId = categoryLookup[categoryName]!;
            final priority = _placeTypePriority[type.toLowerCase()] ?? 50;
            if (!mappingMatches.containsKey(categoryId) || priority < mappingMatches[categoryId]!) {
              mappingMatches[categoryId] = priority;
            }
          }
        }
      }
    }
    
    if (mappingMatches.isNotEmpty) {
      final sortedMatches = mappingMatches.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final bestCategoryId = sortedMatches.first.key;
      final bestCategory = userCategories.firstWhere((c) => c.id == bestCategoryId);
      
      if (mappingMatches.length > 1) {
        final allMatches = mappingMatches.keys.map((id) => 
          userCategories.firstWhere((c) => c.id == id).name).toList();
        print('   🎯 Multiple mapping matches found: ${allMatches.join(', ')}');
        print('   ✅ Selected highest priority: "${bestCategory.name}" (priority: ${sortedMatches.first.value})');
      } else {
        print('   ✅ Mapping match found: "${bestCategory.name}"');
      }
      return bestCategoryId;
    }
    
    // Step 3: Match based on PlaceType enum
    final enumName = placeType.name.toLowerCase();
    if (categoryLookup.containsKey(enumName)) {
      print('   ✅ Enum match found: "${placeType.name}" → "$enumName"');
      return categoryLookup[enumName];
    }
    
    // Try enum-to-category mapping
    final enumToCategoryMap = {
      'restaurant': 'restaurant',
      'cafe': 'cafe',
      'bar': 'bar',
      'museum': 'museum',
      'park': 'park',
      'hotel': 'stay',
      'lodging': 'stay',
      'store': 'other',
      'shopping': 'other',
      'attraction': 'attraction',
      'landmark': 'attraction',
      'entertainment': 'event',
      'event': 'event',
    };
    
    final mappedCategory = enumToCategoryMap[enumName];
    if (mappedCategory != null && categoryLookup.containsKey(mappedCategory)) {
      print('   ✅ Enum mapping match: "${placeType.name}" → "$mappedCategory"');
      return categoryLookup[mappedCategory];
    }
    
    // Step 4: AI-based fallback (optional, uses Gemini Flash which is cost-effective)
    if (useAiFallback && userCategories.length > 1) {
      print('   🤖 No direct match, using AI to determine best category...');
      try {
        final categoryNames = userCategories.map((c) => c.name).toList();
        final bestCategoryName = await _determineCategoryWithAI(
          locationName: locationName,
          placeTypes: placeTypes,
          availableCategories: categoryNames,
        );
        
        if (bestCategoryName != null) {
          final matchedCategory = userCategories.firstWhereOrNull(
            (c) => c.name.toLowerCase() == bestCategoryName.toLowerCase(),
          );
          if (matchedCategory != null) {
            print('   ✅ AI determined category: "$bestCategoryName"');
            return matchedCategory.id;
          }
        }
      } catch (e) {
        print('   ⚠️ AI categorization failed: $e');
      }
    }
    
    // Fallback: Use 'Restaurant' if available (most common), otherwise first category
    final restaurantCategory = userCategories.firstWhereOrNull(
      (c) => c.name.toLowerCase() == 'restaurant',
    );
    if (restaurantCategory != null) {
      print('   ℹ️ Using default category: "Restaurant"');
      return restaurantCategory.id;
    }
    
    print('   ℹ️ Using first available category: "${userCategories.first.name}"');
    return userCategories.first.id;
  }

  /// Determine the best primary category based on location name.
  /// 
  /// Uses:
  /// 1. Keyword matching in the location name
  /// 2. AI fallback for ambiguous names
  Future<String?> determineBestCategoryByLocationName(
    String locationName,
    List<UserCategory> userCategories, {
    bool useAiFallback = true,
  }) async {
    if (userCategories.isEmpty) return null;
    
    final nameLower = locationName.toLowerCase();
    print('🏷️ CATEGORY BY NAME: Determining category for "$locationName"');
    
    // Build a lowercase lookup map for user categories
    final categoryLookup = <String, String>{}; // lowercase name -> category ID
    for (final cat in userCategories) {
      categoryLookup[cat.name.toLowerCase()] = cat.id;
    }
    
    // Step 1: Keyword-based matching in location name
    for (final entry in _keywordToCategoryMap.entries) {
      if (nameLower.contains(entry.key)) {
        final categoryName = entry.value;
        if (categoryLookup.containsKey(categoryName)) {
          print('   ✅ Keyword match: "${entry.key}" → "$categoryName"');
          return categoryLookup[categoryName];
        }
      }
    }
    
    // Step 2: AI-based fallback
    if (useAiFallback && userCategories.length > 1) {
      print('   🤖 No keyword match, using AI...');
      try {
        final categoryNames = userCategories.map((c) => c.name).toList();
        final bestCategoryName = await _determineCategoryWithAI(
          locationName: locationName,
          placeTypes: [], // No place types available for location picker
          availableCategories: categoryNames,
        );
        
        if (bestCategoryName != null) {
          final matchedCategory = userCategories.firstWhereOrNull(
            (c) => c.name.toLowerCase() == bestCategoryName.toLowerCase(),
          );
          if (matchedCategory != null) {
            print('   ✅ AI determined category: "$bestCategoryName"');
            return matchedCategory.id;
          }
        }
      } catch (e) {
        print('   ⚠️ AI categorization failed: $e');
      }
    }
    
    // Fallback: Use 'Restaurant' if available (most common), otherwise first category
    final restaurantCategory = userCategories.firstWhereOrNull(
      (c) => c.name.toLowerCase() == 'restaurant',
    );
    if (restaurantCategory != null) {
      print('   ℹ️ Using default category: "Restaurant"');
      return restaurantCategory.id;
    }
    
    print('   ℹ️ Using first available category: "${userCategories.first.name}"');
    return userCategories.first.id;
  }

  /// Use Gemini AI to determine the best category for a location.
  /// This is a lightweight call using Gemini Flash for cost efficiency.
  Future<String?> _determineCategoryWithAI({
    required String locationName,
    required List<String> placeTypes,
    required List<String> availableCategories,
  }) async {
    if (!_geminiService.isConfigured) {
      print('   ⚠️ Gemini not configured, skipping AI categorization');
      return null;
    }
    
    // Build a simple prompt for category selection
    final placeTypesInfo = placeTypes.isNotEmpty 
        ? ' with Google Places types: ${placeTypes.take(5).join(', ')}'
        : '';
    final prompt = '''Given a location named "$locationName"$placeTypesInfo.

Choose the single BEST category from this list: ${availableCategories.join(', ')}

Respond with ONLY the category name, nothing else. Choose the most specific and relevant category.''';

    try {
      // Use a simple text generation call
      final response = await _geminiService.generateSimpleText(prompt);
      if (response != null && response.isNotEmpty) {
        // Clean up the response and find matching category
        final cleanResponse = response.trim().toLowerCase();
        for (final category in availableCategories) {
          if (cleanResponse.contains(category.toLowerCase()) ||
              category.toLowerCase().contains(cleanResponse)) {
            return category;
          }
        }
        // If exact match not found, try to find the closest one
        for (final category in availableCategories) {
          if (cleanResponse == category.toLowerCase()) {
            return category;
          }
        }
      }
    } catch (e) {
      print('   ⚠️ AI category determination error: $e');
    }
    
    return null;
  }

  /// Auto-categorize with both Color Category (Want to go) and Primary Category.
  /// 
  /// Returns a record with the determined category IDs:
  /// - colorCategoryId: The "Want to go" color category ID (or null if not found)
  /// - primaryCategoryId: The best matching primary category ID
  Future<({String? colorCategoryId, String? primaryCategoryId})> autoCategorizeForNewLocation({
    required String locationName,
    required List<UserCategory> userCategories,
    required List<ColorCategory> colorCategories,
    List<String>? placeTypes,
    String? placeId,
    bool useAiFallback = true,
  }) async {
    print('🏷️ AUTO-CATEGORIZE: Setting categories for "$locationName"');
    
    // API Fallback: If no placeTypes but we have a placeId, fetch from Places API
    List<String>? effectivePlaceTypes = placeTypes;
    if ((effectivePlaceTypes == null || effectivePlaceTypes.isEmpty) && 
        placeId != null && 
        placeId.isNotEmpty) {
      print('   🔄 No stored placeTypes, fetching from Places API for placeId: $placeId');
      try {
        final detailedLocation = await _mapsService.getPlaceDetails(placeId);
        effectivePlaceTypes = detailedLocation.placeTypes;
        if (effectivePlaceTypes != null && effectivePlaceTypes.isNotEmpty) {
          print('   ✅ Fetched placeTypes from API: ${effectivePlaceTypes.take(5).join(', ')}');
        } else {
          print('   ⚠️ API returned no placeTypes');
        }
      } catch (e) {
        print('   ⚠️ Failed to fetch placeTypes from API: $e');
        effectivePlaceTypes = null;
      }
    } else if (effectivePlaceTypes != null && effectivePlaceTypes.isNotEmpty) {
      print('   📋 Using stored placeTypes: ${effectivePlaceTypes.take(5).join(', ')}');
    }
    
    // Get "Want to go" color category
    final wantToGoId = getWantToGoColorCategoryId(colorCategories);
    if (wantToGoId != null) {
      print('   ✅ Color Category set to "Want to go"');
    }
    
    // Determine best Primary Category - use placeTypes if available for better accuracy
    String? primaryCategoryId;
    if (effectivePlaceTypes != null && effectivePlaceTypes.isNotEmpty) {
      primaryCategoryId = await determineBestCategoryByPlaceTypes(
        locationName,
        effectivePlaceTypes,
        userCategories,
        useAiFallback: useAiFallback,
      );
    } else {
      print('   ℹ️ No placeTypes available (stored or from API), using location name matching');
      primaryCategoryId = await determineBestCategoryByLocationName(
        locationName,
        userCategories,
        useAiFallback: useAiFallback,
      );
    }
    
    return (colorCategoryId: wantToGoId, primaryCategoryId: primaryCategoryId);
  }

  /// Determine the best primary category using stored placeTypes.
  /// This is more accurate than location name matching since it uses actual Google Places data.
  Future<String?> determineBestCategoryByPlaceTypes(
    String locationName,
    List<String> placeTypes,
    List<UserCategory> userCategories, {
    bool useAiFallback = true,
  }) async {
    if (userCategories.isEmpty || placeTypes.isEmpty) {
      return determineBestCategoryByLocationName(locationName, userCategories, useAiFallback: useAiFallback);
    }
    
    print('🏷️ CATEGORY BY PLACE TYPES: Using stored types for "$locationName"');
    
    // Build a lowercase lookup map for user categories
    final categoryLookup = <String, String>{}; // lowercase name -> category ID
    for (final cat in userCategories) {
      categoryLookup[cat.name.toLowerCase()] = cat.id;
    }
    
    // Step 0: Check location name keywords FIRST (more semantic than place types)
    // This catches cases like "Trailhead" → "Hike" even when Google says it's a "park"
    final nameLower = locationName.toLowerCase();
    for (final entry in _keywordToCategoryMap.entries) {
      if (nameLower.contains(entry.key)) {
        final categoryName = entry.value;
        if (categoryLookup.containsKey(categoryName)) {
          print('   ✅ Name keyword match: "${entry.key}" in name → "$categoryName"');
          return categoryLookup[categoryName];
        }
      }
    }
    
    // Step 1: Direct match - collect all placeTypes that match user category names
    // Then select the highest priority match (avoids "cafe" being selected over "restaurant")
    final directMatches = <String, int>{}; // categoryId -> priority
    for (final type in placeTypes) {
      final normalizedType = type.toLowerCase().replaceAll('_', ' ');
      if (categoryLookup.containsKey(normalizedType)) {
        final categoryId = categoryLookup[normalizedType]!;
        final priority = _placeTypePriority[type.toLowerCase()] ?? 50;
        // Only keep the highest priority (lowest number) for each category
        if (!directMatches.containsKey(categoryId) || priority < directMatches[categoryId]!) {
          directMatches[categoryId] = priority;
        }
      }
    }
    
    if (directMatches.isNotEmpty) {
      // Select the category with the highest priority (lowest number)
      final sortedMatches = directMatches.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final bestCategoryId = sortedMatches.first.key;
      final bestCategory = userCategories.firstWhere((c) => c.id == bestCategoryId);
      
      if (directMatches.length > 1) {
        final allMatches = directMatches.keys.map((id) => 
          userCategories.firstWhere((c) => c.id == id).name).toList();
        print('   🎯 Multiple direct matches found: ${allMatches.join(', ')}');
        print('   ✅ Selected highest priority: "${bestCategory.name}" (priority: ${sortedMatches.first.value})');
      } else {
        print('   ✅ Direct match found: "${bestCategory.name}"');
      }
      return bestCategoryId;
    }
    
    // Step 2: Mapping-based match - use predefined mappings with priority
    final mappingMatches = <String, int>{}; // categoryId -> priority
    for (final entry in _placeTypeToCategoryMapping.entries) {
      final categoryName = entry.key.toLowerCase();
      final matchingTypes = entry.value;
      
      // Check if any of the location's placeTypes match this category's types
      for (final type in placeTypes) {
        final normalizedType = type.toLowerCase();
        if (matchingTypes.any((t) => normalizedType.contains(t) || t.contains(normalizedType))) {
          // Found a mapping match, now check if user has this category
          if (categoryLookup.containsKey(categoryName)) {
            final categoryId = categoryLookup[categoryName]!;
            final priority = _placeTypePriority[type.toLowerCase()] ?? 50;
            if (!mappingMatches.containsKey(categoryId) || priority < mappingMatches[categoryId]!) {
              mappingMatches[categoryId] = priority;
            }
          }
        }
      }
    }
    
    if (mappingMatches.isNotEmpty) {
      final sortedMatches = mappingMatches.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final bestCategoryId = sortedMatches.first.key;
      final bestCategory = userCategories.firstWhere((c) => c.id == bestCategoryId);
      
      if (mappingMatches.length > 1) {
        final allMatches = mappingMatches.keys.map((id) => 
          userCategories.firstWhere((c) => c.id == id).name).toList();
        print('   🎯 Multiple mapping matches found: ${allMatches.join(', ')}');
        print('   ✅ Selected highest priority: "${bestCategory.name}" (priority: ${sortedMatches.first.value})');
      } else {
        print('   ✅ Mapping match found: "${bestCategory.name}"');
      }
      return bestCategoryId;
    }
    
    // Fall back to location name matching if no placeType match found
    print('   ℹ️ No placeType match, falling back to location name matching');
    return determineBestCategoryByLocationName(locationName, userCategories, useAiFallback: useAiFallback);
  }
}

