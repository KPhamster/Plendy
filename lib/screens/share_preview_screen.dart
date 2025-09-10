import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

class SharePreviewScreen extends StatelessWidget {
  final String token;

  const SharePreviewScreen({super.key, required this.token});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shared Experience')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _fetchPublicShare(token),
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

  Future<Map<String, dynamic>> _fetchPublicShare(String token) async {
    final uri = Uri.parse('https://us-central1-plendy-7df50.cloudfunctions.net/publicShare?token=$token');
    final resp = await http.get(uri, headers: { 'Accept': 'application/json' });
    if (resp.statusCode == 200) {
      return json.decode(resp.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to load share (${resp.statusCode})');
  }
}



