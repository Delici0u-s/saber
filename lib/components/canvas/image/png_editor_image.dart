part of 'editor_image.dart';

class PngEditorImage extends EditorImage {
  ImageProvider? imageProvider;

  Size thumbnailSize = .zero;

  /// The maximum image size allowed for this image.
  /// If null, Prefs.maxImageSize will be used instead.
  Size? maxSize;

  new({
    required super.id,
    required super.assetCache,
    required super.extension,
    required this.imageProvider,
    required super.pageIndex,
    required super.pageSize,
    this.maxSize,
    super.invertible,
    super.backgroundFit,
    required super.onMoveImage,
    required super.onDeleteImage,
    required super.onMiscChange,
    super.onLoad,
    super.newImage,
    super.dstRect,
    super.srcRect,
    super.naturalSize,
    super.isThumbnail,
  });

  factory fromJson(
    Map<String, dynamic> json, {
    required List<Uint8List>? inlineAssets,
    bool isThumbnail = false,
    required String sbnPath,
    required AssetCache assetCache,
  }) {
    final assetIndex = json['a'] as int?;
    final Uint8List? bytes;
    File? imageFile;
    if (assetIndex != null) {
      if (inlineAssets == null) {
        imageFile = FileManager.getFile(
          '$sbnPath${Editor.extension}.$assetIndex',
        );
        bytes = assetCache.get(imageFile);
      } else {
        bytes = inlineAssets[assetIndex];
      }
    } else if (json['b'] != null) {
      bytes = Uint8List.fromList((json['b'] as List<dynamic>).cast<int>());
    } else {
      if (kDebugMode) {
        throw Exception('EditorImage.fromJson: image bytes not found');
      }
      bytes = Uint8List(0);
    }
    assert(
      bytes != null || imageFile != null,
      'Either bytes or imageFile must be non-null',
    );

    return PngEditorImage(
      // -1 will be replaced by [EditorCoreInfo._handleEmptyImageIds()]
      id: json['id'] ?? -1,
      assetCache: assetCache,
      extension: json['e'] ?? '.jpg',
      imageProvider: bytes != null
          ? MemoryImage(bytes) as ImageProvider
          : FileImage(imageFile!),
      pageIndex: json['i'] ?? 0,
      pageSize: .infinite,
      invertible: json['v'] ?? true,
      backgroundFit: json['f'] != null ? .values[json['f']] : .contain,
      onMoveImage: null,
      onDeleteImage: null,
      onMiscChange: null,
      onLoad: null,
      newImage: false,
      dstRect: .fromLTWH(
        json['x'] ?? 0,
        json['y'] ?? 0,
        json['w'] ?? 0,
        json['h'] ?? 0,
      ),
      srcRect: .fromLTWH(
        json['sx'] ?? 0,
        json['sy'] ?? 0,
        json['sw'] ?? 0,
        json['sh'] ?? 0,
      ),
      naturalSize: Size(json['nw'] ?? 0, json['nh'] ?? 0),
      isThumbnail: isThumbnail,
    );
  }

  @override
  Map<String, dynamic> toJson(OrderedAssetCache assets) {
    final json = super.toJson(assets);
    assert(!json.containsKey('a'));
    if (imageProvider != null) {
      json['a'] = assets.addImage(imageProvider!);
    }
    return json;
  }

  @override
  Future<void> firstLoad() async {
    assert(Isolate.current.debugName == 'main');

    if (srcRect.shortestSide == 0 || dstRect.shortestSide == 0) {
      final bytes = await getBytes();

      naturalSize = await ui.ImmutableBuffer.fromUint8List(bytes)
          .then((buffer) => ui.ImageDescriptor.encoded(buffer))
          .then(
            (descriptor) =>
                Size(descriptor.width.toDouble(), descriptor.height.toDouble()),
          );

      if (maxSize == null) {
        await stows.maxImageSize.waitUntilRead();
        maxSize = .square(stows.maxImageSize.value);
      }
      final Size reducedSize = EditorImage.resize(naturalSize, maxSize!);
      if (naturalSize.width != reducedSize.width && !isThumbnail) {
        await null; // wait for next event-loop iteration

        final resizedByteData = await resizeImage(
          bytes,
          width: reducedSize.width.toInt(),
          height: reducedSize.height.toInt(),
        );
        if (resizedByteData != null) {
          imageProvider = MemoryImage(resizedByteData.buffer.asUint8List());
        }

        naturalSize = reducedSize;
      }

      if (srcRect.shortestSide == 0) {
        srcRect = srcRect.topLeft & naturalSize;
      }
      if (dstRect.shortestSide == 0) {
        final Size dstSize = pageSize != null
            ? EditorImage.resize(naturalSize, pageSize!)
            : naturalSize;
        dstRect = dstRect.topLeft & dstSize;
      }
    }

    if (naturalSize.shortestSide == 0) {
      naturalSize = Size(srcRect.width, srcRect.height);
    }

    if (isThumbnail) {
      isThumbnail = true; // updates bytes and srcRect
    }
  }

  /// The encoded bytes of this image.
  Future<Uint8List> getBytes() async => switch (imageProvider) {
    MemoryImage(:final bytes) => bytes,
    FileImage(:final file) => await file.readAsBytes(),
    final provider => throw ArgumentError.value(
      provider,
      'imageProvider',
      'Unknown image provider type',
    ),
  };

  /// A copy of this image cropped to [crop], given as a fraction of the image
  /// (0 to 1 on each axis). The copy covers the area of the page that the
  /// cropped part did. Its [id] still needs to be set by the caller.
  Future<PngEditorImage> cropped(Rect crop) async {
    final (bytes, size) = await _cropBytes(await getBytes(), crop);
    return PngEditorImage(
      id: id,
      assetCache: assetCache,
      extension: '.png',
      imageProvider: MemoryImage(bytes),
      pageIndex: pageIndex,
      pageSize: pageSize,
      maxSize: maxSize,
      invertible: invertible,
      backgroundFit: backgroundFit,
      onMoveImage: onMoveImage,
      onDeleteImage: onDeleteImage,
      onMiscChange: onMiscChange,
      onLoad: onLoad,
      dstRect: .fromLTWH(
        dstRect.left + crop.left * dstRect.width,
        dstRect.top + crop.top * dstRect.height,
        crop.width * dstRect.width,
        crop.height * dstRect.height,
      ),
      srcRect: Offset.zero & size,
      naturalSize: size,
    )..onReplaceImage = onReplaceImage;
  }

  /// Crops encoded image [bytes] to [crop] (a fraction of the image)
  /// and returns the result as PNG bytes, with its size in pixels.
  static Future<(Uint8List, Size)> _cropBytes(
    Uint8List bytes,
    Rect crop,
  ) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final source = (await codec.getNextFrame()).image;
    codec.dispose();

    // Whole pixels (at least one), so the crop is an exact copy.
    final left = (crop.left * source.width).round().clamp(0, source.width - 1);
    final top = (crop.top * source.height).round().clamp(0, source.height - 1);
    final right = (crop.right * source.width).round().clamp(
      left + 1,
      source.width,
    );
    final bottom = (crop.bottom * source.height).round().clamp(
      top + 1,
      source.height,
    );
    final cropRect = Rect.fromLTRB(
      left.toDouble(),
      top.toDouble(),
      right.toDouble(),
      bottom.toDouble(),
    );
    final width = right - left;
    final height = bottom - top;

    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      source,
      cropRect,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint(),
    );
    final picture = recorder.endRecording();
    final result = await picture.toImage(width, height);
    final data = await result.toByteData(format: .png);
    picture.dispose();
    source.dispose();
    result.dispose();

    return (
      data!.buffer.asUint8List(),
      Size(width.toDouble(), height.toDouble()),
    );
  }

  @override
  Future<void> loadIn() async => await super.loadIn();
  @override
  Future<bool> loadOut() async => await super.loadOut();

  @override
  Future<void> precache(BuildContext context) async {
    if (imageProvider == null) return;
    return await precacheImage(imageProvider!, context);
  }

  @override
  Widget buildImageWidget({
    required BuildContext context,
    required BoxFit? overrideBoxFit,
    required bool isBackground,
    required bool invert,
  }) {
    final BoxFit boxFit;
    if (overrideBoxFit != null) {
      boxFit = overrideBoxFit;
    } else if (isBackground) {
      boxFit = backgroundFit;
    } else {
      boxFit = .fill;
    }

    return InvertWidget(
      invert: invert,
      child: Image(image: imageProvider!, fit: boxFit),
    );
  }

  @override
  PngEditorImage copy() => PngEditorImage(
    id: id,
    assetCache: assetCache,
    extension: extension,
    imageProvider: imageProvider,
    pageIndex: pageIndex,
    pageSize: .infinite,
    invertible: invertible,
    backgroundFit: backgroundFit,
    onMoveImage: onMoveImage,
    onDeleteImage: onDeleteImage,
    onMiscChange: onMiscChange,
    onLoad: onLoad,
    newImage: true,
    dstRect: dstRect,
    srcRect: srcRect,
    naturalSize: naturalSize,
    isThumbnail: isThumbnail,
  )..onReplaceImage = onReplaceImage;
}
