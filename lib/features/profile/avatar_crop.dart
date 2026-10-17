import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';

import '../../models/forum_account_models.dart';
import '../../theme/app_theme.dart';
import '../common/native_form_fields.dart';

/// Lets the user choose the square that becomes the avatar. Null: cancelled,
/// nothing changes. The result is the picked file itself (animated pictures
/// the user chose to keep) or a new PNG.
typedef AvatarCropper = Future<ForumAccountUpload?> Function(
  BuildContext context,
  ForumAccountUpload source,
  NativeFormController form,
);

/// The longest side of the uploaded PNG; smaller crops are never enlarged.
const avatarOutputEdge = 512;

/// The decoded copy used for cropping stays within this edge, whatever the file.
const _decodeEdge = 2048;

/// Pictures with more pixels than this are refused before any decoding.
const _maxSourcePixels = 100 * 1000 * 1000;

const _maxZoom = 8.0;

Future<ForumAccountUpload?> cropAvatar(
  BuildContext context,
  ForumAccountUpload source,
  NativeFormController form,
) =>
    Navigator.of(context).push<ForumAccountUpload>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => NativeFormOverlay(
        controller: form,
        child: AvatarCropScreen(source: source),
      ),
    ));

class _Decoded {
  _Decoded(this.image, this.frames);
  final ui.Image image;
  final int frames;
}

/// Decodes at most [_decodeEdge] pixels per side, after checking the size
/// from the file header; every native handle is released on all paths.
Future<_Decoded> _decode(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final w = descriptor.width, h = descriptor.height;
    if (w <= 0 || h <= 0 || w * h > _maxSourcePixels) {
      throw const FormatException('图片尺寸过大');
    }
    final long = math.max(w, h);
    final scale = long > _decodeEdge ? _decodeEdge / long : 1.0;
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (w * scale).round()),
      targetHeight: math.max(1, (h * scale).round()),
    );
    final frame = await codec.getNextFrame();
    return _Decoded(frame.image, codec.frameCount);
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

/// The [side] x [side] square of [image] around [center], as the avatar PNG.
Future<ForumAccountUpload> renderAvatarCrop(
    ui.Image image, Offset center, double side) async {
  final out = math.max(1, math.min(avatarOutputEdge, side.floor()));
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
    image,
    Rect.fromCenter(center: center, width: side, height: side),
    Rect.fromLTWH(0, 0, out.toDouble(), out.toDouble()),
    Paint()
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true,
  );
  final picture = recorder.endRecording();
  ui.Image? rendered;
  try {
    rendered = await picture.toImage(out, out);
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw const FormatException('无法生成头像图片');
    return ForumAccountUpload(
      bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      fileName: 'avatar.png',
      mimeType: 'image/png',
    );
  } finally {
    rendered?.dispose();
    picture.dispose();
  }
}

class AvatarCropScreen extends StatefulWidget {
  const AvatarCropScreen({super.key, required this.source});

  final ForumAccountUpload source;

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  ui.Image? _image;
  int _frames = 1;
  String? _error;

  /// An animated picture waits for the user's choice between the still crop
  /// and the untouched original.
  var _stillAccepted = false;
  var _working = false;
  var _zoom = 1.0;
  Offset? _center;
  double _frame = 0;
  double _startZoom = 1;
  Offset _startCenter = Offset.zero;
  Offset _startFocal = Offset.zero;
  final _focus = FocusNode(debugLabel: 'avatar-crop');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _focus.dispose();
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final decoded = await _decode(widget.source.bytes);
      if (!mounted) {
        decoded.image.dispose();
        return;
      }
      setState(() {
        _image = decoded.image;
        _frames = decoded.frames;
        _center = Offset(decoded.image.width / 2, decoded.image.height / 2);
      });
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取这张图片');
    }
  }

  double get _minScale {
    final image = _image!;
    return _frame / math.min(image.width, image.height);
  }

  double get _scale => _minScale * _zoom;

  /// The side of the chosen square, in picture pixels.
  double get _side =>
      math.min(_image!.width, _image!.height).toDouble() / _zoom;

  int get _outEdge => math.max(1, math.min(avatarOutputEdge, _side.floor()));

  Offset _clamp(Offset c) {
    final image = _image!;
    final half = _side / 2;
    return Offset(
      c.dx.clamp(half, math.max(half, image.width - half)).toDouble(),
      c.dy.clamp(half, math.max(half, image.height - half)).toDouble(),
    );
  }

  void _setZoom(double zoom) => setState(() {
        _zoom = zoom.clamp(1.0, _maxZoom).toDouble();
        _center = _clamp(_center!);
      });

  void _pan(double dx, double dy) =>
      setState(() => _center = _clamp(_center! + Offset(dx, dy) / _scale));

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || _image == null || _frame <= 0) {
      return KeyEventResult.ignored;
    }
    final step = HardwareKeyboard.instance.isShiftPressed ? 64.0 : 16.0;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _pan(-step, 0);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _pan(step, 0);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _pan(0, -step);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _pan(0, step);
    } else if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      _setZoom(_zoom + 0.25);
    } else if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _setZoom(_zoom - 0.25);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Future<void> _confirm() async {
    if (_working || _image == null || _frame <= 0) return;
    setState(() => _working = true);
    try {
      final upload = await renderAvatarCrop(_image!, _center!, _side);
      if (mounted) Navigator.of(context).pop(upload);
    } catch (_) {
      if (mounted) {
        setState(() {
          _working = false;
          _error = '无法生成头像图片';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = _image;
    Widget body;
    if (_error != null) {
      body = _Notice(
        message: _error!,
        actions: [
          FilledButton(
            key: const Key('avatar-crop-cancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('返回'),
          ),
        ],
      );
    } else if (image == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_frames > 1 && !_stillAccepted) {
      body = _Notice(
        message: '这是一张动图。裁剪后只保留第一帧，成为静态头像；也可以不裁剪，直接上传原图。',
        actions: [
          FilledButton(
            key: const Key('avatar-crop-still'),
            onPressed: () => setState(() => _stillAccepted = true),
            child: const Text('裁剪为静态图'),
          ),
          OutlinedButton(
            key: const Key('avatar-crop-original'),
            onPressed: () => Navigator.of(context).pop(widget.source),
            child: const Text('上传原图，不裁剪'),
          ),
          TextButton(
            key: const Key('avatar-crop-cancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      );
    } else {
      body = Column(
        children: [
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              final frame = math.max(48.0,
                  math.min(box.maxWidth, box.maxHeight) - 2 * AppSpace.lg);
              if (frame != _frame) {
                // The frame follows the window; keep the chosen square valid.
                _frame = frame;
                _center = _clamp(_center!);
              }
              return Semantics(
                label: '裁剪区域。方向键移动，加减键缩放',
                customSemanticsActions: {
                  const CustomSemanticsAction(label: '向左移动'): () =>
                      _pan(-32, 0),
                  const CustomSemanticsAction(label: '向右移动'): () => _pan(32, 0),
                  const CustomSemanticsAction(label: '向上移动'): () =>
                      _pan(0, -32),
                  const CustomSemanticsAction(label: '向下移动'): () => _pan(0, 32),
                },
                child: Focus(
                  focusNode: _focus,
                  autofocus: true,
                  onKeyEvent: _key,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _focus.requestFocus,
                    onScaleStart: (d) {
                      _startZoom = _zoom;
                      _startCenter = _center!;
                      _startFocal = d.focalPoint;
                    },
                    onScaleUpdate: (d) => setState(() {
                      _zoom = (_startZoom * d.scale)
                          .clamp(1.0, _maxZoom)
                          .toDouble();
                      _center = _clamp(
                          _startCenter - (d.focalPoint - _startFocal) / _scale);
                    }),
                    child: CustomPaint(
                      key: const Key('avatar-crop-canvas'),
                      size: box.biggest,
                      painter: _CropPainter(
                        image: image,
                        center: _center!,
                        scale: _scale,
                        frame: _frame,
                        shade: theme.colorScheme.scrim.withValues(alpha: 0.55),
                        border: theme.colorScheme.surface,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.4),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '拖动移动范围，滑动缩放。头像以正方形上传'
                    '（$_outEdge × $_outEdge 像素 PNG）。',
                    style: theme.textTheme.bodySmall,
                  ),
                  Row(
                    children: [
                      const Icon(Icons.zoom_out, size: 20),
                      Expanded(
                        child: Slider(
                          key: const Key('avatar-crop-zoom'),
                          value: _zoom,
                          min: 1,
                          max: _maxZoom,
                          label: '缩放',
                          semanticFormatterCallback: (v) =>
                              '缩放 ${v.toStringAsFixed(1)} 倍',
                          onChanged: _setZoom,
                        ),
                      ),
                      const Icon(Icons.zoom_in, size: 20),
                    ],
                  ),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.sm,
                    children: [
                      TextButton(
                        key: const Key('avatar-crop-cancel'),
                        onPressed:
                            _working ? null : () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        key: const Key('avatar-crop-confirm'),
                        onPressed: _working ? null : _confirm,
                        child: Text(_working ? '正在生成…' : '使用此范围'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Scaffold(
      key: const Key('avatar-crop-screen'),
      appBar: AppBar(title: const Text('裁剪头像')),
      body: SafeArea(top: false, child: body),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.actions});

  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(message,
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
              const SizedBox(height: AppSpace.lg),
              for (final a in actions) ...[
                a,
                const SizedBox(height: AppSpace.sm),
              ],
            ],
          ),
        ),
      );
}

/// Draws the picture under a dimmed window with the crop square clear; the
/// square is exactly what [renderAvatarCrop] later cuts out.
class _CropPainter extends CustomPainter {
  _CropPainter({
    required this.image,
    required this.center,
    required this.scale,
    required this.frame,
    required this.shade,
    required this.border,
  });

  final ui.Image image;
  final Offset center;
  final double scale;
  final double frame;
  final Color shade;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final view = Offset.zero & size;
    final window =
        Rect.fromCenter(center: view.center, width: frame, height: frame);
    canvas.save();
    canvas.clipRect(view);
    canvas.translate(
        view.center.dx - center.dx * scale, view.center.dy - center.dy * scale);
    canvas.scale(scale);
    canvas.drawImage(
        image, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(view),
          Path()..addRect(window)),
      Paint()..color = shade,
    );
    canvas.drawRect(
      window,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = border,
    );
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.image != image ||
      old.center != center ||
      old.scale != scale ||
      old.frame != frame ||
      old.shade != shade ||
      old.border != border;
}
