import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service for interacting with Google Knowledge Graph Search API
class GoogleKnowledgeGraphService {
  static const String _baseUrl = 'https://kgsearch.googleapis.com/v1/entities:search';
  
  final String? apiKey;
  
  GoogleKnowledgeGraphService({this.apiKey});
  
  /// Search for entities in the Google Knowledge Graph
  /// Returns a list of entity results with structured data
  Future<List<Map<String, dynamic>>> searchEntities(String query, {
    int limit = 10,
    List<String>? types,
    String? language,
  }) async {
    try {
      // Check if API key is configured
      if (apiKey == null || apiKey!.isEmpty || apiKey!.contains('YOUR_')) {
        print('🔍 KNOWLEDGE GRAPH WARNING: API key not configured. Please add your Google Knowledge Graph API key');
        return [];
      }
      
      final Map<String, String> queryParams = {
        'query': query,
        'key': apiKey!,
        'limit': limit.toString(),
        'indent': 'false',
      };
      
      if (types != null && types.isNotEmpty) {
        queryParams['types'] = types.join(',');
      }
      
      if (language != null && language.isNotEmpty) {
        queryParams['languages'] = language;
      }
      
      final uri = Uri.parse(_baseUrl).replace(queryParameters: queryParams);
      print('🔍 KNOWLEDGE GRAPH: Searching for "$query" with URL: ${uri.toString().replaceAll(apiKey!, 'API_KEY_HIDDEN')}');
      
      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final itemList = data['itemListElement'] as List<dynamic>? ?? [];
        
        print('🔍 KNOWLEDGE GRAPH: Found ${itemList.length} results for "$query"');
        
        return itemList.map((item) {
          final result = item['result'] as Map<String, dynamic>;
          return {
            'name': result['name'],
            'description': result['description'],
            'types': result['@type'] as List<dynamic>? ?? [],
            'detailedDescription': result['detailedDescription'],
            'image': result['image'],
            'url': result['url'],
            'id': result['@id'],
            'score': item['resultScore'],
          };
        }).toList();
      } else {
        print('🔍 KNOWLEDGE GRAPH ERROR: HTTP ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      print('🔍 KNOWLEDGE GRAPH ERROR: Exception during search: $e');
      return [];
    }
  }
  
  /// Check if an entity is a place based on its types
  bool isPlaceEntity(List<dynamic> types) {
    final placeTypes = [
      'Place',
      'LocalBusiness',
      'Restaurant',
      'Hotel',
      'TouristAttraction',
      'Museum',
      'Park',
      'Store',
      'LandmarksOrHistoricalBuildings',
      'CivicStructure',
      'EducationalOrganization',
      'GovernmentBuilding',
      'PlaceOfWorship',
      'Organization', // Some organizations are also places
    ];
    
    return types.any((type) => 
      placeTypes.contains(type) || 
      (type is String && placeTypes.any((placeType) => type.contains(placeType)))
    );
  }
  
  /// Extract the best available description from entity data
  String? extractDescription(Map<String, dynamic> entity) {
    // Try detailed description first
    if (entity['detailedDescription'] != null) {
      final detailed = entity['detailedDescription'] as Map<String, dynamic>;
      return detailed['articleBody'] as String?;
    }
    
    // Fall back to simple description
    return entity['description'] as String?;
  }
  
  /// Extract image URL from entity data
  String? extractImageUrl(Map<String, dynamic> entity) {
    if (entity['image'] != null) {
      final image = entity['image'] as Map<String, dynamic>;
      return image['contentUrl'] as String?;
    }
    return null;
  }
} 