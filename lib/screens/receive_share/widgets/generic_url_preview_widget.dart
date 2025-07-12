import 'package:flutter/material.dart';
import 'package:any_link_preview/any_link_preview.dart';

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
    return Column(
      children: [
        SizedBox(
          height: 220,
          width: double.infinity,
          child: AnyLinkPreview(
            link: url,
            displayDirection: UIDirection.uiDirectionVertical,
            cache: const Duration(hours: 1),
            backgroundColor: Colors.white,
            errorWidget: Container(
              color: Colors.grey[200],
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.link, size: 50, color: Colors.blue),
                  const SizedBox(height: 8),
                  Text(
                    url,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.blue),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "(Preview not available)",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            onTap: () => launchUrlCallback(url),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Text(
            url,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
