import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'dart:io';
import 'package:any_link_preview/any_link_preview.dart';
import 'package:url_launcher/url_launcher.dart';

class ReceiveShareScreen extends StatefulWidget {
  final List<SharedMediaFile> sharedFiles;
  final VoidCallback onCancel;

  const ReceiveShareScreen({
    Key? key,
    required this.sharedFiles,
    required this.onCancel,
  }) : super(key: key);

  @override
  _ReceiveShareScreenState createState() => _ReceiveShareScreenState();
}

class _ReceiveShareScreenState extends State<ReceiveShareScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Shared Content'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: Icon(Icons.close),
            onPressed: widget.onCancel,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: widget.sharedFiles.isEmpty
                  ? Center(child: Text('No shared content received'))
                  : ListView.builder(
                      padding: EdgeInsets.all(16),
                      itemCount: widget.sharedFiles.length,
                      itemBuilder: (context, index) {
                        final file = widget.sharedFiles[index];
                        return Card(
                          margin: EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Display media content or appropriate icon
                              _buildMediaPreview(file),
                                
                              // Display metadata (only for non-URL content)
                              if (!(file.type == SharedMediaType.text && _isValidUrl(file.path)))
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
                                      if (file.type != SharedMediaType.text)
                                        Text('Path: ${file.path}'),
                                      if (file.type == SharedMediaType.text && !_isValidUrl(file.path))
                                        Text('Content: ${file.path}'),
                                      if (file.thumbnail != null) ...[
                                        SizedBox(height: 8),
                                        Text('Thumbnail: ${file.thumbnail}'),
                                      ],
                                    ],
                                  ),
                                ),
                              
                              // For URLs, we'll only show the preview and open button
                              if (file.type == SharedMediaType.text && _isValidUrl(file.path))
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Type: ${_getMediaTypeString(file.type)}',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
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
                      onPressed: widget.onCancel,
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
                        widget.onCancel(); // Return to main screen after saving
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

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }
  
  bool _isValidUrl(String text) {
    // Simple URL validation
    try {
      final uri = Uri.parse(text);
      return uri.hasScheme && uri.hasAuthority;
    } catch (e) {
      return false;
    }
  }

  String _getMediaTypeString(SharedMediaType type) {
    switch (type) {
      case SharedMediaType.image:
        return 'Image';
      case SharedMediaType.video:
        return 'Video';
      case SharedMediaType.file:
        return 'File';
      case SharedMediaType.text:
        return 'Text';
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
      case SharedMediaType.text:
        return _buildTextPreview(file);
      case SharedMediaType.file:
      default:
        return _buildFilePreview(file);
    }
  }

  Widget _buildTextPreview(SharedMediaFile file) {
    // Check if it's a URL
    if (_isValidUrl(file.path)) {
      return _buildUrlPreview(file.path);
    } else {
      // Regular text
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(16),
        color: Colors.grey[200],
        child: Text(
          file.path,
          style: TextStyle(fontSize: 16),
        ),
      );
    }
  }

  Widget _buildUrlPreview(String url) {
    // Special handling for Instagram URLs
    if (url.contains('instagram.com')) {
      return _buildInstagramPreview(url);
    }

    return Container(
      height: 250,
      width: double.infinity,
      child: AnyLinkPreview(
        link: url,
        displayDirection: UIDirection.uiDirectionVertical,
        cache: Duration(hours: 1),
        backgroundColor: Colors.white,
        errorWidget: Container(
          color: Colors.grey[200],
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.link, size: 50, color: Colors.blue),
              SizedBox(height: 8),
              Text(
                url,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.blue),
              ),
            ],
          ),
        ),
        onTap: () => _launchUrl(url),
      ),
    );
  }

  Widget _buildInstagramPreview(String url) {
    // Extract the content ID from Instagram URL
    final String contentId = _extractInstagramId(url);
    
    return InkWell(
      onTap: () => _launchUrl(url),
      child: Container(
        height: 280,
        width: double.infinity,
        color: Colors.white,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Instagram logo or icon
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    Color(0xFFE1306C),
                    Color(0xFFF77737),
                    Color(0xFFFCAF45),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.camera_alt,
                color: Colors.white,
                size: 40,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Instagram Reel',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 4),
            Text(
              contentId,
              style: TextStyle(
                color: Colors.grey[600],
                fontFamily: 'Courier',
                letterSpacing: -0.5,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Tap to open in Instagram app',
              style: TextStyle(
                color: Colors.grey[700],
              ),
            ),
            SizedBox(height: 16),
            OutlinedButton.icon(
              icon: Icon(Icons.open_in_new),
              label: Text('Open Instagram'),
              onPressed: () => _launchUrl(url),
              style: OutlinedButton.styleFrom(
                foregroundColor: Color(0xFFE1306C),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _extractInstagramId(String url) {
    // Try to extract the content ID from the URL
    try {
      // Remove query parameters if present
      String cleanUrl = url;
      if (url.contains('?')) {
        cleanUrl = url.split('?')[0];
      }
      
      // Split the URL by slashes
      List<String> pathSegments = cleanUrl.split('/');
      
      // Instagram URLs usually have the content ID as one of the last segments
      // For reels: instagram.com/reel/{content_id}
      if (pathSegments.length > 2) {
        for (int i = pathSegments.length - 1; i >= 0; i--) {
          if (pathSegments[i].isNotEmpty && 
              pathSegments[i] != 'instagram.com' && 
              pathSegments[i] != 'reel' &&
              pathSegments[i] != 'p' &&
              !pathSegments[i].startsWith('http')) {
            return pathSegments[i];
          }
        }
      }
      
      return 'Instagram Content';
    } catch (e) {
      return 'Instagram Content';
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
