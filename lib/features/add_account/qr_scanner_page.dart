import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  late final MobileScannerController _controller;
  bool _handlingResult = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handlingResult) return;
    String? rawValue;
    for (final barcode in capture.barcodes) {
      final candidate = barcode.rawValue;
      if (candidate != null && candidate.isNotEmpty) {
        rawValue = candidate;
        break;
      }
    }
    if (rawValue == null) return;
    _handlingResult = true;
    await _controller.stop();
    if (mounted) Navigator.of(context).pop(rawValue);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Scan setup QR code')),
        body: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) => _ScannerError(error: error),
            ),
            IgnorePointer(
              child: Center(
                child: Container(
                  width: 260,
                  height: 220,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const Positioned(
              left: 24,
              right: 24,
              bottom: 32,
              child: Text(
                'Place the authenticator QR code inside the frame. The code is decoded on this device.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, backgroundColor: Colors.black54),
              ),
            ),
          ],
        ),
      );
}

class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final permissionDenied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(permissionDenied ? Icons.no_photography_outlined : Icons.camera_alt_outlined, size: 48),
              const SizedBox(height: 16),
              Text(
                permissionDenied
                    ? 'Camera access was denied. You can enable it in system settings, or return and enter the account manually.'
                    : 'The camera is unavailable. Return and enter the account manually.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back')),
            ],
          ),
        ),
      ),
    );
  }
}
