import 'package:flutter/material.dart';
import 'package:any_link_preview/any_link_preview.dart';
import 'package:plendy/utils/haptic_feedback.dart';
import 'package:plendy/models/receive_share_help_target.dart';

class GenericUrlPreviewWidget extends StatefulWidget {
  final String url;
  final Future<void> Function(String) launchUrlCallback;
  final bool isHelpMode;
  final bool Function(ReceiveShareHelpTargetId id, BuildContext ctx)? onHelpTap;

  const GenericUrlPreviewWidget({
    super.key,
    required this.url,
    required this.launchUrlCallback,
    this.isHelpMode = false,
    this.onHelpTap,
  });

  @override
  State<GenericUrlPreviewWidget> createState() =>
      _GenericUrlPreviewWidgetState();
}

class _GenericUrlPreviewWidgetState extends State<GenericUrlPreviewWidget> {
  bool _helpTap(ReceiveShareHelpTargetId id, BuildContext ctx) {
    if (widget.onHelpTap != null) return widget.onHelpTap!(id, ctx);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 220,
          width: double.infinity,
          child: Builder(builder: (ctx) => AnyLinkPreview(
            link: widget.url,
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
                    widget.url,
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
            onTap: withHeavyTap(() {
              if (_helpTap(ReceiveShareHelpTargetId.previewLinkRow, ctx)) return;
              widget.launchUrlCallback(widget.url);
            }),
          )),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Text(
            widget.url,
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
