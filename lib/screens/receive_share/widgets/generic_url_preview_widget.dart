import 'package:flutter/material.dart';
import 'package:any_link_preview/any_link_preview.dart';
import 'package:url_launcher/url_launcher.dart';

class GenericUrlPreviewWidget extends StatelessWidget {
  final String url;
  final Future<void> Function(String) launchUrlCallback;

  const GenericUrlPreviewWidget({
    super.key,
    required this.url,
    required this.launchUrlCallback,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
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
        onTap: () => launchUrlCallback(url),
      ),
    );
  }
}
