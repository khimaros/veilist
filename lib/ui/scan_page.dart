// scan a share link's qr code with the device camera (R1, R2). the share
// dialog already shows a qr, so this closes the loop: point one phone at
// another and join, with nothing to type or paste.
//
// decoding is pure dart (a zxing port) running over the flutter camera plugin,
// so the apk carries no proprietary decoder - a hard requirement for f-droid
// and izzyondroid (see DISTRIBUTION.md).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_code_dart_scan/qr_code_dart_scan.dart';

import '../data/share_link.dart';

/// whether to offer the camera at all. the plugin covers android/ios and the
/// browser; desktop has no implementation, so the affordance stays hidden
/// there rather than opening a page that can only fail.
bool get canScanLinks =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// decode a scanned code into a share link, or null if it is some other qr.
ShareLink? shareLinkFromCode(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final uri = Uri.tryParse(raw.trim());
  return uri == null ? null : ShareLink.tryParse(uri);
}

/// open the scanner and resolve to the first share link it reads, or null if
/// the user backed out.
Future<ShareLink?> scanShareLink(BuildContext context) {
  return Navigator.of(context).push<ShareLink>(
    MaterialPageRoute<ShareLink>(builder: (_) => const ScanPage()),
  );
}

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final _controller = QRCodeDartScanController();

  // a code was read but was not a veilist link - keep scanning, and say so.
  bool _sawForeignCode = false;
  bool _done = false;
  bool _torch = false;
  // set once the torch turns out not to exist on this camera.
  bool _torchAvailable = !kIsWeb;
  String? _cameraError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onCapture(ScanResult result) {
    if (_done) return;
    final link = shareLinkFromCode(result.text);
    if (link != null) {
      _done = true;
      Navigator.of(context).pop(link);
      return;
    }
    if (!_sawForeignCode) setState(() => _sawForeignCode = true);
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleFlash();
      setState(() => _torch = !_torch);
    } catch (_) {
      // no flash unit on this camera; stop offering one.
      setState(() => _torchAvailable = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('scan a share link'),
        actions: [
          if (_torchAvailable && _cameraError == null)
            IconButton(
              key: const Key('scan_torch'),
              tooltip: _torch ? 'turn the torch off' : 'turn the torch on',
              icon: Icon(_torch ? Icons.flashlight_on : Icons.flashlight_off),
              onPressed: _toggleTorch,
            ),
        ],
      ),
      body: Stack(
        key: const Key('scan_page'),
        fit: StackFit.expand,
        children: [
          if (_cameraError case final error?)
            _Unavailable(message: error)
          else
            QRCodeDartScanView(
              controller: _controller,
              // the browser cannot stream camera frames to dart, so web scans a
              // still the user captures; native decodes the live preview.
              typeScan: kIsWeb ? TypeScan.takePicture : TypeScan.live,
              formats: const [BarcodeFormat.qrCode],
              onCapture: _onCapture,
              onCameraError: (message) =>
                  setState(() => _cameraError = message),
            ),
          if (_cameraError == null)
            Align(
              alignment: Alignment.bottomCenter,
              child: _Hint(
                text: _sawForeignCode
                    ? 'that qr code is not a veilist link'
                    : 'point the camera at a list qr code',
              ),
            ),
        ],
      ),
    );
  }
}

// the camera can be missing, refused, or (on web) withheld because the page is
// not served over https - all of which land here. pasting the link still works,
// so say that rather than leaving a black rectangle.
class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, size: 48),
            const SizedBox(height: 12),
            const Text(
              'no camera available - open the link by pasting it instead',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(message, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(text),
      ),
    );
  }
}
