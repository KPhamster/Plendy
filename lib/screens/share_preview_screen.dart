import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_app_check/firebase_app_check.dart';
import '../../firebase_options.dart';
import 'package:flutter/material.dart';

class SharePreviewScreen extends StatelessWidget {
  final String token;

  const SharePreviewScreen({super.key, required this.token});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shared Experience')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _fetchPublicShareFromFirestore(token),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: Text('This share isn\'t available.'));
          }
          final data = snapshot.data!;
          final snapshotData = (data['snapshot'] as Map<String, dynamic>?) ?? {};
          final title = snapshotData['name'] as String? ?? 'Experience';
          final desc = snapshotData['description'] as String?;
          final image = snapshotData['image'] as String?;
          final location = (snapshotData['location'] as Map<String, dynamic>?) ?? {};
          final locName = location['displayName'] as String?;

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (image != null && image.isNotEmpty)
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(image, fit: BoxFit.cover),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.headlineSmall),
                      if (locName != null && locName.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(locName, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54)),
                        ),
                      if (desc != null && desc.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: Text(desc),
                        ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Save to collections coming soon.')),
                              );
                            },
                            child: const Text('Save to my collection'),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<Map<String, dynamic>> _fetchPublicShareFromFirestore(String token) async {
    // Use Firestore REST with explicit App Check header to avoid SDK listen flow
    final appCheckToken = await FirebaseAppCheck.instance.getToken(true);
    final apiKey = DefaultFirebaseOptions.currentPlatform.apiKey;
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      // Move API key to header instead of URL param
      if (apiKey.isNotEmpty) 'x-goog-api-key': apiKey,
      if (appCheckToken != null && appCheckToken.isNotEmpty)
        'X-Firebase-AppCheck': appCheckToken,
    };

    final projectId = 'plendy-7df50';
    final idParam = Uri.base.queryParameters['id'];

    if (idParam != null && idParam.isNotEmpty) {
      final docUrl = Uri.parse(
          'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/experience_shares/$idParam');
      final resp = await http.get(docUrl, headers: headers);
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body) as Map<String, dynamic>;
        return _mapRestDoc(body);
      }
      // fall through to token query
    }

    final runQueryUrl = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents:runQuery');
    final payload = {
      'structuredQuery': {
        'from': [
          {'collectionId': 'experience_shares'}
        ],
        'where': {
          'compositeFilter': {
            'op': 'AND',
            'filters': [
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'token'},
                  'op': 'EQUAL',
                  'value': {'stringValue': token}
                }
              },
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'visibility'},
                  'op': 'IN',
                  'value': {
                    'arrayValue': {
                      'values': [
                        {'stringValue': 'public'},
                        {'stringValue': 'unlisted'}
                      ]
                    }
                  }
                }
              }
            ]
          }
        },
        'limit': 1
      }
    };
    final resp = await http.post(runQueryUrl, headers: headers, body: json.encode(payload));
    if (resp.statusCode != 200) {
      throw Exception('Share lookup failed (${resp.statusCode})');
    }
    final List results = json.decode(resp.body) as List;
    final Map<String, dynamic>? first = results.cast<Map<String, dynamic>?>().firstWhere(
        (e) => e != null && e.containsKey('document'),
        orElse: () => null);
    if (first == null) {
      throw Exception('Share not found');
    }
    return _mapRestDoc(first['document'] as Map<String, dynamic>);
  }

  Map<String, dynamic> _mapRestDoc(Map<String, dynamic> docJson) {
    // Firestore REST returns fields under document.fields as typed values
    final name = docJson['name'] as String?; // projects/.../documents/experience_shares/{id}
    final shareId = name != null ? name.split('/').last : '';
    final fields = (docJson['fields'] ?? {}) as Map<String, dynamic>;

    dynamic _decodeValue(dynamic value) {
      if (value is! Map<String, dynamic>) return value;
      if (value.containsKey('nullValue')) return null;
      if (value.containsKey('stringValue')) return value['stringValue'];
      if (value.containsKey('booleanValue')) return value['booleanValue'] as bool;
      if (value.containsKey('integerValue')) return int.tryParse(value['integerValue'] as String);
      if (value.containsKey('doubleValue')) return (value['doubleValue'] as num).toDouble();
      if (value.containsKey('timestampValue')) return value['timestampValue'];
      if (value.containsKey('geoPointValue')) return value['geoPointValue'];
      if (value.containsKey('arrayValue')) {
        final list = (value['arrayValue']['values'] as List?) ?? const [];
        return list.map(_decodeValue).toList();
      }
      if (value.containsKey('mapValue')) {
        final m = (value['mapValue']['fields'] as Map<String, dynamic>?) ?? const {};
        return m.map((k, v) => MapEntry(k, _decodeValue(v)));
      }
      return value;
    }

    Map<String, dynamic> _decodeFields(Map<String, dynamic> raw) {
      return raw.map((k, v) => MapEntry(k, _decodeValue(v)));
    }

    final decoded = _decodeFields(fields);

    return {
      'shareId': shareId,
      'experienceId': decoded['experienceId'],
      'visibility': decoded['visibility'],
      'snapshot': decoded['snapshot'],
      'message': decoded['message'],
      'createdAt': decoded['createdAt'],
    };
  }
}



