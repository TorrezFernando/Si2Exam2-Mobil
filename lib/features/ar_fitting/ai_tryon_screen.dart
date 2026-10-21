import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../core/widgets/product_image.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/theme.dart';

class AITryonScreen extends StatefulWidget {
  final int productId;
  final String productName;
  final String? productImageUrl;

  const AITryonScreen({
    super.key,
    required this.productId,
    required this.productName,
    this.productImageUrl,
  });

  @override
  State<AITryonScreen> createState() => _AITryonScreenState();
}

class _AITryonScreenState extends State<AITryonScreen> {
  CameraController? _cameraController;
  bool _isProcessing = false;
  String? _resultImageUrl;
  String? _error;
  bool _arMode = true;
  double _scale = 1;
  double _startScale = 1;
  Offset _offset = Offset.zero;
  double _opacity = 0.85;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('No hay cámara disponible');
      final frontCamera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
      final controller = CameraController(frontCamera, ResolutionPreset.high, enableAudio: false);
      _cameraController = controller;
      await controller.initialize();
      if (!mounted) { await controller.dispose(); return; }
      setState(() {});
    } catch (e) { if (mounted) setState(() => _error = 'No se pudo iniciar la cámara. Revisa los permisos.'); }
  }

  Future<void> _takePhotoAndProcess() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      final XFile photo = await _cameraController!.takePicture();
      
      final result = await ApiService.generateAiTryOn(widget.productId, photo.path);
      
      if (mounted) {
        setState(() {
          _resultImageUrl = result['result_url'];
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isProcessing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Widget _buildCameraPreview() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }

    final size = MediaQuery.of(context).size;
    var scale = size.aspectRatio * _cameraController!.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;

    return Stack(
      fit: StackFit.expand,
      children: [
        Transform.scale(
          scale: scale,
          child: Center(
            child: CameraPreview(_cameraController!),
          ),
        ),
        if (_arMode && widget.productImageUrl != null)
          Center(child: GestureDetector(
            onScaleStart: (_) => _startScale = _scale,
            onScaleUpdate: (details) => setState(() {
              _scale = (_startScale * details.scale).clamp(0.3, 3.0);
              _offset += details.focalPointDelta;
            }),
            child: Transform.translate(offset: _offset, child: Transform.scale(scale: _scale,
              child: Opacity(opacity: _opacity, child: ProductImage(imageUrl: widget.productImageUrl, width: 240, height: 320, fit: BoxFit.contain)))),
          )),
        Positioned(top: 110, left: 16, right: 16, child: Column(children: [
          SegmentedButton<bool>(segments: const [ButtonSegment(value: true, label: Text('AR 2D')), ButtonSegment(value: false, label: Text('Foto con IA'))],
            selected: {_arMode}, onSelectionChanged: (selection) => setState(() => _arMode = selection.first)),
          if (_arMode) ...[
            const Text('Arrastra y pellizca para ajustar la prenda. Vista orientativa.', style: TextStyle(color: Colors.white), textAlign: TextAlign.center),
            Slider(value: _opacity, min: 0.2, max: 1, onChanged: (value) => setState(() => _opacity = value)),
          ],
        ])),
        // Overlay guide
        if (!_arMode) Positioned.fill(
          child: CustomPaint(
            painter: SilhouettePainter(),
          ),
        ),
        if (!_arMode) Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 40.0),
            child: FloatingActionButton.large(
              onPressed: _takePhotoAndProcess,
              backgroundColor: AppTheme.primary,
              child: const Icon(Icons.camera_alt, color: Colors.white, size: 36),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultView() {
    final fullUrl = ApiService.getFullImageUrl(_resultImageUrl!);
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          fullUrl,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          },
          errorBuilder: (context, error, stackTrace) => const Center(
            child: Text('Error cargando la imagen generada', style: TextStyle(color: Colors.white)),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar', style: TextStyle(fontSize: 13)),
                      onPressed: () => setState(() => _resultImageUrl = null),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: const Icon(Icons.check),
                      label: const Text('¡Me encanta!', style: TextStyle(fontSize: 13)),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Probador: ${widget.productName}'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      extendBodyBehindAppBar: true,
      body: _isProcessing
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  CircularProgressIndicator(color: AppTheme.primary),
                  SizedBox(height: 24),
                  Text('✨ Gemini está ajustando la prenda...', 
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('Calculando luces y sombras...', 
                    style: TextStyle(color: Colors.grey, fontSize: 14)),
                ],
              ),
            )
          : _resultImageUrl != null
              ? _buildResultView()
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, color: AppTheme.danger, size: 64),
                            const SizedBox(height: 16),
                            Text('Ocurrió un error:\n$_error', 
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white)),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: () { setState(() => _error = null); if (_cameraController == null || !_cameraController!.value.isInitialized) _initializeCamera(); },
                              child: const Text('Reintentar'),
                            )
                          ],
                        ),
                      ),
                    )
                  : _buildCameraPreview(),
    );
  }
}

class SilhouettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    // Simple head and shoulders outline
    final headRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.3),
      width: size.width * 0.4,
      height: size.height * 0.25,
    );
    canvas.drawOval(headRect, paint);

    final path = Path();
    path.moveTo(size.width * 0.2, size.height * 0.5);
    path.quadraticBezierTo(size.width * 0.5, size.height * 0.4, size.width * 0.8, size.height * 0.5);
    path.lineTo(size.width * 0.9, size.height);
    path.lineTo(size.width * 0.1, size.height);
    path.close();
    
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
