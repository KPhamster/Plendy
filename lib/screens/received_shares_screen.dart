import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReceivedSharesScreen extends StatelessWidget {
  const ReceivedSharesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Shared with me'),
        ),
        body: const Center(
          child: Text('Please sign in to view shares.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared with me'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('received_shares')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No shares yet'));
          }
          final docs = snapshot.data!.docs;
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final snapshotData = (data['snapshot'] as Map<String, dynamic>?) ?? {};
              final title = snapshotData['name'] as String? ?? 'Experience';
              final subtitle = snapshotData['location']?['displayName'] as String?;
              return ListTile(
                title: Text(title),
                subtitle: subtitle != null ? Text(subtitle) : null,
                trailing: TextButton(
                  child: const Text('Save'),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Save to collections coming soon.')),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}


