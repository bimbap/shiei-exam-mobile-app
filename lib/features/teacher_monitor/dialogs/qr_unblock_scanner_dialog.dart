import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../shared/widgets/app_notification.dart';
import '../teacher_portal_controller.dart';

class QrUnblockScannerDialog extends StatefulWidget {
  final TeacherPortalController controller;

  const QrUnblockScannerDialog({super.key, required this.controller});

  static Future<bool?> show({
    required BuildContext context,
    required TeacherPortalController controller,
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => QrUnblockScannerDialog(controller: controller),
      ),
    );
  }

  @override
  State<QrUnblockScannerDialog> createState() => _QrUnblockScannerDialogState();
}

class _QrUnblockScannerDialogState extends State<QrUnblockScannerDialog> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _isProcessing = false;
  bool _isTorchOn = false;
  String? _statusMessage;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final rawValue = barcodes.first.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Memverifikasi QR Code...';
    });

    try {
      final Map<String, dynamic> data = jsonDecode(rawValue);
      if (data['app'] != 'shiei' || data['action'] != 'unblock') {
        _handleInvalidQr('Format QR tidak cocok untuk Project SHIEI.');
        return;
      }

      final examId = data['exam_id'];
      final studentId = data['student_id'];
      final studentName = data['name']?.toString() ?? 'Siswa';

      final intExamId = examId is int ? examId : int.tryParse(examId.toString()) ?? 0;
      final intStudentId = studentId is int ? studentId : int.tryParse(studentId.toString()) ?? 0;

      if (intExamId <= 0 || intStudentId <= 0) {
        _handleInvalidQr('Data ID Ujian atau ID Siswa tidak valid.');
        return;
      }

      if (!widget.controller.isAdmin && !widget.controller.canUnlockStudentForExam(intExamId)) {
        _handleInvalidQr('Akses Ditolak: Anda bukan pengawas atau pembuat ujian ini.');
        return;
      }

      setState(() {
        _statusMessage = 'Membuka kunci: $studentName...';
      });

      // Execute unblock via controller
      final success = await widget.controller.unlockStudent(intExamId, intStudentId);

      if (!mounted) return;

      if (success) {
        try {
          HapticFeedback.mediumImpact();
        } catch (_) {}

        AppNotification.showSuccess(
          context,
          'Kunci Berhasil Dibuka!',
          subtitle: '$studentName sekarang dapat melanjutkan ujian.',
        );

        Navigator.of(context).pop(true);
      } else {
        _handleInvalidQr('Gagal membuka kunci dari server. Periksa koneksi.');
      }
    } catch (e) {
      _handleInvalidQr('Gagal membaca data QR. Pastikan QR valid.');
    }
  }

  void _handleInvalidQr(String message) {
    if (!mounted) return;
    setState(() {
      _statusMessage = message;
    });

    try {
      HapticFeedback.vibrate();
    } catch (_) {}

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Camera Viewfinder
          MobileScanner(
            controller: _scannerController,
            onDetect: _handleBarcode,
          ),

          // 2. Dark Overlay with Cutout Mask
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 0.65),
              BlendMode.srcOut,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    backgroundBlendMode: BlendMode.dstOut,
                  ),
                ),
                Center(
                  child: Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3. Glowing Viewfinder Frame
          Center(
            child: Container(
              width: 264,
              height: 264,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFF8B5CF6),
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Corner Guides
                  Positioned(
                    top: -2,
                    left: -2,
                    child: _buildCorner(isTop: true, isLeft: true),
                  ),
                  Positioned(
                    top: -2,
                    right: -2,
                    child: _buildCorner(isTop: true, isLeft: false),
                  ),
                  Positioned(
                    bottom: -2,
                    left: -2,
                    child: _buildCorner(isTop: false, isLeft: true),
                  ),
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: _buildCorner(isTop: false, isLeft: false),
                  ),
                ],
              ),
            ),
          ),

          // 4. Top Action Bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black45,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.qr_code_scanner_rounded, size: 16, color: Color(0xFF8B5CF6)),
                        SizedBox(width: 6),
                        Text(
                          'Scan QR Siswa',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black45,
                      foregroundColor: _isTorchOn ? const Color(0xFFF59E0B) : Colors.white,
                    ),
                    icon: Icon(_isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded),
                    onPressed: () async {
                      await _scannerController.toggleTorch();
                      setState(() => _isTorchOn = !_isTorchOn);
                    },
                  ),
                ],
              ),
            ),
          ),

          // 5. Bottom Instructions & Status Banner
          Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: Column(
              children: [
                if (_statusMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: _isProcessing ? const Color(0xFF8B5CF6) : const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isProcessing)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        else
                          const Icon(Icons.error_outline_rounded, color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _statusMessage!,
                            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: Color(0xFF94A3B8), size: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Arahkan kamera ke QR Code di layar HP siswa yang terkunci untuk membuka blokir seketika.',
                          style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCorner({required bool isTop, required bool isLeft}) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        border: Border(
          top: isTop ? const BorderSide(color: Colors.white, width: 4) : BorderSide.none,
          bottom: !isTop ? const BorderSide(color: Colors.white, width: 4) : BorderSide.none,
          left: isLeft ? const BorderSide(color: Colors.white, width: 4) : BorderSide.none,
          right: !isLeft ? const BorderSide(color: Colors.white, width: 4) : BorderSide.none,
        ),
      ),
    );
  }
}
