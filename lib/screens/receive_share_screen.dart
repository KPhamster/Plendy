import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'dart:io';

class ReceiveShareScreen extends StatelessWidget {
  final List<SharedMediaFile> sharedFiles;
  final VoidCallback onCancel;

  const ReceiveShareScreen({
    Key? key,
    required this.sharedFiles,
    required this.onCancel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Shared Content'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: Icon(Icons.close),
            onPressed: onCancel,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: sharedFiles.isEmpty
                  ? Center(child: Text('No shared content received'))
                  : ListView.builder(
                      padding: EdgeInsets.all(16),
                      itemCount: sharedFiles.length,
                      itemBuilder: (context, index) {
                        final file = sharedFiles[index];
                        return Card(
                          margin: EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Display media content or appropriate icon
                              _buildMediaPreview(file),
                                
                              // Display metadata
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Type: ${_getMediaTypeString(file.type)}',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    SizedBox(height: 8),
                                    Text('Path: ${file.path}'),
                                    if (file.thumbnail != null) ...[
                                      SizedBox(height: 8),
                                      Text('Thumbnail: ${file.thumbnail}'),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: onCancel,
                      child: Text('Cancel'),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () {
                        // TODO: Implement logic to save or process the shared content
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Content saved')),
                        );
                        onCancel(); // Return to main screen after saving
                      },
                      child: Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getMediaTypeString(SharedMediaType type) {
    switch (type) {
      case SharedMediaType.image:
        return 'Image';
      case SharedMediaType.video:
        return 'Video';
      case SharedMediaType.file:
        return 'File';
      default:
        return type.toString();
    }
  }

  Widget _buildMediaPreview(SharedMediaFile file) {
    switch (file.type) {
      case SharedMediaType.image:
        return _buildImagePreview(file);
      case SharedMediaType.video:
        return _buildVideoPreview(file);
      case SharedMediaType.file:
      default:
        return _buildFilePreview(file);
    }
  }

  Widget _buildImagePreview(SharedMediaFile file) {
    try {
      return Container(
        height: 200,
        width: double.infinity,
        child: Image.file(
          File(file.path),
          fit: BoxFit.cover,
        ),
      );
    } catch (e) {
      return Container(
        height: 200,
        width: double.infinity,
        color: Colors.grey[300],
        child: Center(
          child: Icon(Icons.image_not_supported, size: 50),
        ),
      );
    }
  }

  Widget _buildVideoPreview(SharedMediaFile file) {
    return Container(
      height: 200,
      width: double.infinity,
      color: Colors.black87,
      child: Center(
        child: Icon(
          Icons.play_circle_outline,
          size: 70,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildFilePreview(SharedMediaFile file) {
    IconData iconData;
    Color iconColor;
    
    // Determine file type from path extension
    final String extension = file.path.split('.').last.toLowerCase();
    
    if (['pdf'].contains(extension)) {
      iconData = Icons.picture_as_pdf;
      iconColor = Colors.red;
    } else if (['doc', 'docx'].contains(extension)) {
      iconData = Icons.description;
      iconColor = Colors.blue;
    } else if (['xls', 'xlsx'].contains(extension)) {
      iconData = Icons.table_chart;
      iconColor = Colors.green;
    } else if (['ppt', 'pptx'].contains(extension)) {
      iconData = Icons.slideshow;
      iconColor = Colors.orange;
    } else if (['txt', 'rtf'].contains(extension)) {
      iconData = Icons.text_snippet;
      iconColor = Colors.blueGrey;
    } else if (['zip', 'rar', '7z'].contains(extension)) {
      iconData = Icons.folder_zip;
      iconColor = Colors.amber;
    } else {
      iconData = Icons.insert_drive_file;
      iconColor = Colors.grey;
    }
    
    return Container(
      height: 150,
      width: double.infinity,
      color: Colors.grey[200],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(iconData, size: 70, color: iconColor),
            SizedBox(height: 8),
            Text(
              extension.toUpperCase(),
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
