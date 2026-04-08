import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/api/api_client.dart';
import '../../../providers.dart';

class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});
  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _processing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    setState(() => _processing = true);
    await _controller.stop();

    await _processRaw(barcode.rawValue!);
  }

  Future<void> _processRaw(String raw) async {
    debugPrint('[QR] raw=$raw');

    // Detect registration QR (reg_xxx or /register/reg_xxx URL)
    final regToken = _extractRegToken(raw);
    if (regToken != null) {
      await _handleRegistration(regToken);
      return;
    }

    final token = _extractToken(raw);
    debugPrint('[QR] token=$token');
    if (token.isEmpty) {
      _retry('无效的二维码');
      return;
    }

    try {
      await ref.read(authProvider.notifier).enterPortal(token);
      if (!mounted) return;
      final auth = ref.read(authProvider);
      final needsProfile = auth.portalData?['needs_profile'] == true;
      if (needsProfile) {
        context.go('/portal/complete-profile');
      } else {
        context.go('/portal/home');
      }
    } on DioException catch (e) {
      debugPrint('[QR] DioError: status=${e.response?.statusCode} body=${e.response?.data} type=${e.type}');
      final status = e.response?.statusCode;
      final body = e.response?.data;
      String detail = '';
      if (body is Map && body['error'] is Map) {
        detail = body['error']['message'] ?? '';
      } else if (status != null) {
        detail = 'HTTP $status';
      } else {
        detail = e.type.name;
      }
      _retry('扫码失败: $detail\n(raw=${raw.length > 80 ? '${raw.substring(0, 80)}...' : raw})');
    } catch (e) {
      debugPrint('[QR] error=$e');
      _retry('扫码失败: $e');
    }
  }

  /// Extract registration token (reg_xxx) from raw QR data, or null if not a registration QR.
  String? _extractRegToken(String raw) {
    raw = raw.trim();
    if (raw.startsWith('reg_')) return raw;
    if (raw.contains('/register/')) {
      // URL like http://host/register/reg_xxx
      try {
        final uri = Uri.parse(raw);
        final segments = uri.pathSegments;
        final idx = segments.indexOf('register');
        if (idx != -1 && idx + 1 < segments.length) {
          return segments[idx + 1];
        }
      } catch (_) {}
      // Fallback
      return raw.split('/register/').last.split('?').first;
    }
    return null;
  }

  /// Handle registration QR: check session status; if submitted → auto-login, otherwise → form.
  Future<void> _handleRegistration(String regToken) async {
    debugPrint('[QR] regToken=$regToken');
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.get('/api/public/register/$regToken');
      final data = resp['data'] as Map<String, dynamic>? ?? {};
      final status = data['status'] as String? ?? '';
      final patient = data['patient'] as Map<String, dynamic>?;

      if (status == 'submitted' && patient != null) {
        // Already submitted — extract portal_token and auto-login
        final portalToken = patient['portal_token'] as String?;
        if (portalToken != null && portalToken.isNotEmpty) {
          await ref.read(authProvider.notifier).enterPortal(portalToken);
          if (!mounted) return;
          context.go('/portal/home');
          return;
        }
      }

      // Active session — navigate to registration form
      if (!mounted) return;
      context.go('/register-form', extra: regToken);
    } on DioException catch (e) {
      final body = e.response?.data;
      String detail = '';
      if (body is Map && body['error'] is Map) {
        detail = body['error']['message'] ?? '';
      } else {
        detail = 'HTTP ${e.response?.statusCode ?? e.type.name}';
      }
      _retry('登记码验证失败: $detail');
    } catch (e) {
      _retry('登记码验证失败: $e');
    }
  }

  /// Extract portal token from QR data — handles raw token or various URL formats.
  String _extractToken(String raw) {
    raw = raw.trim();

    // If it looks like a URL, parse it to find the token
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      try {
        final uri = Uri.parse(raw);
        final segments = uri.pathSegments;
        // Look for 'portal' in path segments and take the next one
        final portalIdx = segments.indexOf('portal');
        if (portalIdx != -1 && portalIdx + 1 < segments.length) {
          return segments[portalIdx + 1];
        }
        // Fallback: look for a segment starting with 'pt_'
        for (final seg in segments.reversed) {
          if (seg.startsWith('pt_')) return seg;
        }
      } catch (_) {
        // Uri.parse failed, try simple string split
      }
      // Legacy simple split
      if (raw.contains('/portal/')) {
        return raw.split('/portal/').last.split('?').first;
      }
      return ''; // URL but no token found
    }

    // Non-URL: check for /portal/ substring
    if (raw.contains('/portal/')) {
      return raw.split('/portal/').last.split('?').first;
    }

    // Assume it's a raw token (pt_xxx or similar)
    return raw;
  }

  void _retry(String message) {
    if (!mounted) return;
    setState(() => _processing = false);
    _controller.start();
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() => _processing = true);
    await _controller.stop();

    try {
      final capture = await _controller.analyzeImage(picked.path);
      if (capture != null) {
        final barcode = capture.barcodes.firstOrNull;
        if (barcode != null && barcode.rawValue != null) {
          await _processRaw(barcode.rawValue!);
          return;
        }
      }
      _retry('图片中未识别到二维码');
    } catch (e) {
      debugPrint('[QR] gallery error=$e');
      _retry('图片识别失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('扫码登录')),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // Scan overlay
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.primary, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          // Bottom hint
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Text(
              _processing ? '正在验证...' : '将二维码对准框内',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16, shadows: [Shadow(blurRadius: 4)]),
            ),
          ),
          // Gallery button
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: TextButton.icon(
                onPressed: _processing ? null : _pickFromGallery,
                icon: const Icon(Icons.photo_library, color: Colors.white),
                label: const Text('从相册选择', style: TextStyle(color: Colors.white)),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.black38,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
              ),
            ),
          ),
          if (_processing)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
