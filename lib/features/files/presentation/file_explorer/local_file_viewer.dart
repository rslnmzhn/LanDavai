part of '../file_explorer_page.dart';

class LocalFileViewerPage extends StatelessWidget {
  const LocalFileViewerPage({required this.filePath, super.key});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    final fileName = p.basename(filePath);
    final fileKind = _resolveFileKind(filePath);

    Widget body;
    switch (fileKind) {
      case _LocalFileKind.image:
        body = _ImageFileViewer(filePath: filePath);
      case _LocalFileKind.video:
        body = _useMediaKitForPlayback
            ? _MediaKitVideoFileViewer(filePath: filePath)
            : _VideoFileViewer(filePath: filePath);
      case _LocalFileKind.audio:
        body = _useMediaKitForPlayback
            ? _MediaKitAudioFileViewer(filePath: filePath)
            : _AudioFileViewer(filePath: filePath);
      case _LocalFileKind.text:
        body = _TextFileViewer(filePath: filePath);
      case _LocalFileKind.pdf:
        body = _PdfFileViewer(filePath: filePath);
      case _LocalFileKind.other:
        body = _UnsupportedFileViewer(filePath: filePath);
    }

    return Scaffold(
      appBar: AppBar(title: Text(fileName)),
      body: SafeArea(child: body),
    );
  }

  _LocalFileKind _resolveFileKind(String path) {
    final ext = p.extension(path).toLowerCase();
    if (_supportedImageExtensions.contains(ext)) {
      return _LocalFileKind.image;
    }
    if (_supportedVideoExtensions.contains(ext)) {
      return _LocalFileKind.video;
    }
    if (_supportedAudioExtensions.contains(ext)) {
      return _LocalFileKind.audio;
    }
    if (_supportedTextExtensions.contains(ext)) {
      return _LocalFileKind.text;
    }
    if (ext == '.pdf') {
      return _LocalFileKind.pdf;
    }
    return _LocalFileKind.other;
  }
}

class _ImageFileViewer extends StatelessWidget {
  const _ImageFileViewer({required this.filePath});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 0.2,
      maxScale: 4,
      child: Center(
        child: Image.file(
          File(filePath),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const _ViewerError(message: 'Cannot open image file.');
          },
        ),
      ),
    );
  }
}

class _MediaKitVideoFileViewer extends StatefulWidget {
  const _MediaKitVideoFileViewer({required this.filePath});

  final String filePath;

  @override
  State<_MediaKitVideoFileViewer> createState() =>
      _MediaKitVideoFileViewerState();
}

class _MediaKitVideoFileViewerState extends State<_MediaKitVideoFileViewer> {
  late final Player _player;
  late final VideoController _videoController;
  late final Future<Uint8List?> _previewFuture;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  String? _errorMessage;
  bool _opened = false;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _previewFuture = _MediaPreviewCache.loadVideoPreview(
      filePath: widget.filePath,
      maxExtent: 1280,
      quality: 82,
      timeMs: 700,
    );
    _player = Player();
    _videoController = VideoController(_player);
    _playingSubscription = _player.stream.playing.listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPlaying = event;
      });
    });
    _positionSubscription = _player.stream.position.listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {
        _position = event;
      });
    });
    _durationSubscription = _player.stream.duration.listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {
        _duration = event;
      });
    });
    _initialize();
  }

  @override
  void dispose() {
    _playingSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await _player.open(
        Media(_mediaUriFromFilePath(widget.filePath)),
        play: false,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _opened = true;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Cannot open video in built-in player.\n$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return _UnsupportedFileViewer(
        filePath: widget.filePath,
        hintMessage: _errorMessage,
      );
    }

    final totalMs = _duration.inMilliseconds;
    final positionMs = _position.inMilliseconds.clamp(0, math.max(totalMs, 0));
    final sliderMax = math.max(totalMs, 1).toDouble();
    final aspect = _resolveVideoAspectRatio(_player.state);

    return Column(
      children: [
        Expanded(
          child: Center(
            child: !_opened
                ? FutureBuilder<Uint8List?>(
                    future: _previewFuture,
                    builder: (context, snapshot) {
                      final bytes = snapshot.data;
                      if (bytes != null && bytes.isNotEmpty) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.lg,
                                ),
                                child: Image.memory(bytes, fit: BoxFit.contain),
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.32),
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(AppSpacing.xs),
                              child: const Icon(
                                Icons.play_circle_fill_rounded,
                                color: Colors.white,
                                size: 46,
                              ),
                            ),
                          ],
                        );
                      }
                      return const CircularProgressIndicator();
                    },
                  )
                : AspectRatio(
                    aspectRatio: aspect,
                    child: Video(
                      controller: _videoController,
                      controls: null,
                      fit: BoxFit.contain,
                    ),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Slider(
            value: positionMs.toDouble().clamp(0, sliderMax),
            min: 0,
            max: sliderMax,
            onChanged: _duration == Duration.zero
                ? null
                : (value) {
                    _player.seek(Duration(milliseconds: value.round()));
                  },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: [
              Text(
                '${_formatPlaybackDuration(_position)} / ${_formatPlaybackDuration(_duration)}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Back 10s',
                onPressed: () {
                  final target = _position - const Duration(seconds: 10);
                  _player.seek(target.isNegative ? Duration.zero : target);
                },
                icon: const Icon(Icons.replay_10_rounded),
              ),
              IconButton(
                tooltip: _isPlaying ? 'Pause' : 'Play',
                onPressed: () {
                  if (_isPlaying) {
                    _player.pause();
                  } else {
                    _player.play();
                  }
                },
                icon: Icon(
                  _isPlaying
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_fill_rounded,
                  size: 36,
                ),
              ),
              IconButton(
                tooltip: 'Forward 10s',
                onPressed: () {
                  final target = _position + const Duration(seconds: 10);
                  final bounded =
                      _duration == Duration.zero || target < _duration
                      ? target
                      : _duration;
                  _player.seek(bounded);
                },
                icon: const Icon(Icons.forward_10_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}

class _MediaKitAudioFileViewer extends StatefulWidget {
  const _MediaKitAudioFileViewer({required this.filePath});

  final String filePath;

  @override
  State<_MediaKitAudioFileViewer> createState() =>
      _MediaKitAudioFileViewerState();
}

class _MediaKitAudioFileViewerState extends State<_MediaKitAudioFileViewer> {
  late final Player _player;
  late final Future<Uint8List?> _coverFuture;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  String? _errorMessage;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _coverFuture = _MediaPreviewCache.loadAudioCover(
      filePath: widget.filePath,
      maxExtent: 1200,
      quality: 86,
    );
    _player = Player();
    _playingSubscription = _player.stream.playing.listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPlaying = event;
      });
    });
    _positionSubscription = _player.stream.position.listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {
        _position = event;
      });
    });
    _durationSubscription = _player.stream.duration.listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {
        _duration = event;
      });
    });
    _initialize();
  }

  @override
  void dispose() {
    _playingSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await _player.open(
        Media(_mediaUriFromFilePath(widget.filePath)),
        play: false,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Cannot open audio in built-in player.\n$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return _UnsupportedFileViewer(
        filePath: widget.filePath,
        hintMessage: _errorMessage,
      );
    }

    final totalMs = _duration.inMilliseconds;
    final positionMs = _position.inMilliseconds.clamp(0, math.max(totalMs, 0));
    final sliderMax = math.max(totalMs, 1).toDouble();

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 540,
                  maxHeight: 540,
                ),
                child: FutureBuilder<Uint8List?>(
                  future: _coverFuture,
                  builder: (context, snapshot) {
                    final cover = snapshot.data;
                    if (cover != null && cover.isNotEmpty) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        child: Image.memory(cover, fit: BoxFit.contain),
                      );
                    }
                    return Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSoft,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: AppColors.mutedBorder),
                      ),
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: const Icon(
                        Icons.audiotrack_rounded,
                        color: AppColors.mutedIcon,
                        size: 64,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Slider(
            value: positionMs.toDouble().clamp(0, sliderMax),
            min: 0,
            max: sliderMax,
            onChanged: _duration == Duration.zero
                ? null
                : (value) {
                    _player.seek(Duration(milliseconds: value.round()));
                  },
          ),
          Row(
            children: [
              Text(
                '${_formatPlaybackDuration(_position)} / ${_formatPlaybackDuration(_duration)}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Back 10s',
                onPressed: () {
                  final target = _position - const Duration(seconds: 10);
                  _player.seek(target.isNegative ? Duration.zero : target);
                },
                icon: const Icon(Icons.replay_10_rounded),
              ),
              IconButton(
                tooltip: _isPlaying ? 'Pause' : 'Play',
                onPressed: () {
                  if (_isPlaying) {
                    _player.pause();
                  } else {
                    _player.play();
                  }
                },
                icon: Icon(
                  _isPlaying
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_fill_rounded,
                  size: 36,
                ),
              ),
              IconButton(
                tooltip: 'Forward 10s',
                onPressed: () {
                  final target = _position + const Duration(seconds: 10);
                  final bounded =
                      _duration == Duration.zero || target < _duration
                      ? target
                      : _duration;
                  _player.seek(bounded);
                },
                icon: const Icon(Icons.forward_10_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VideoFileViewer extends StatefulWidget {
  const _VideoFileViewer({required this.filePath});

  final String filePath;

  @override
  State<_VideoFileViewer> createState() => _VideoFileViewerState();
}

class _VideoFileViewerState extends State<_VideoFileViewer> {
  VideoPlayerController? _controller;
  String? _errorMessage;
  late final Future<Uint8List?> _previewFuture;

  @override
  void initState() {
    super.initState();
    _previewFuture = _MediaPreviewCache.loadVideoPreview(
      filePath: widget.filePath,
      maxExtent: 1280,
      quality: 82,
      timeMs: 700,
    );
    _initialize();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final controller = VideoPlayerController.file(File(widget.filePath));
      await controller.initialize();
      await controller.setLooping(false);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage =
            'Cannot open video in built-in player on this platform.\n$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return _UnsupportedFileViewer(
        filePath: widget.filePath,
        hintMessage: _errorMessage,
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return Center(
        child: FutureBuilder<Uint8List?>(
          future: _previewFuture,
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes != null && bytes.isNotEmpty) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.32),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: const Icon(
                      Icons.play_circle_fill_rounded,
                      color: Colors.white,
                      size: 46,
                    ),
                  ),
                ],
              );
            }
            return const CircularProgressIndicator();
          },
        ),
      );
    }

    final isPlaying = controller.value.isPlaying;

    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
        ),
        VideoProgressIndicator(
          controller,
          allowScrubbing: true,
          colors: const VideoProgressColors(
            playedColor: AppColors.brandPrimary,
            bufferedColor: AppColors.brandAccent,
            backgroundColor: AppColors.mutedBorder,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: isPlaying ? 'Pause' : 'Play',
              onPressed: () async {
                if (isPlaying) {
                  await controller.pause();
                } else {
                  await controller.play();
                }
                if (mounted) {
                  setState(() {});
                }
              },
              icon: Icon(
                isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                size: 34,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}

class _AudioFileViewer extends StatefulWidget {
  const _AudioFileViewer({required this.filePath});

  final String filePath;

  @override
  State<_AudioFileViewer> createState() => _AudioFileViewerState();
}

class _AudioFileViewerState extends State<_AudioFileViewer> {
  VideoPlayerController? _controller;
  String? _errorMessage;
  late final Future<Uint8List?> _coverFuture;

  @override
  void initState() {
    super.initState();
    _coverFuture = _MediaPreviewCache.loadAudioCover(
      filePath: widget.filePath,
      maxExtent: 1200,
      quality: 86,
    );
    _initialize();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final controller = VideoPlayerController.file(File(widget.filePath));
      await controller.initialize();
      await controller.setLooping(false);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Cannot open audio in built-in player.\n$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return _UnsupportedFileViewer(
        filePath: widget.filePath,
        hintMessage: _errorMessage,
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 540,
                  maxHeight: 540,
                ),
                child: FutureBuilder<Uint8List?>(
                  future: _coverFuture,
                  builder: (context, snapshot) {
                    final cover = snapshot.data;
                    if (cover != null && cover.isNotEmpty) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        child: Image.memory(cover, fit: BoxFit.contain),
                      );
                    }
                    return Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSoft,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: AppColors.mutedBorder),
                      ),
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: const Icon(
                        Icons.audiotrack_rounded,
                        color: AppColors.mutedIcon,
                        size: 64,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          VideoProgressIndicator(
            controller,
            allowScrubbing: true,
            colors: const VideoProgressColors(
              playedColor: AppColors.brandPrimary,
              bufferedColor: AppColors.brandAccent,
              backgroundColor: AppColors.mutedBorder,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final isPlaying = value.isPlaying;
              final position = value.position;
              final duration = value.duration;
              return Row(
                children: [
                  Text(
                    '${_formatDuration(position)} / ${_formatDuration(duration)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Back 10s',
                    onPressed: () async {
                      final target = position - const Duration(seconds: 10);
                      await controller.seekTo(
                        target.isNegative ? Duration.zero : target,
                      );
                    },
                    icon: const Icon(Icons.replay_10_rounded),
                  ),
                  IconButton(
                    tooltip: isPlaying ? 'Pause' : 'Play',
                    onPressed: () async {
                      if (isPlaying) {
                        await controller.pause();
                      } else {
                        await controller.play();
                      }
                    },
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                      size: 36,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Forward 10s',
                    onPressed: () async {
                      final target = position + const Duration(seconds: 10);
                      final bounded =
                          duration == Duration.zero || target < duration
                          ? target
                          : duration;
                      await controller.seekTo(bounded);
                    },
                    icon: const Icon(Icons.forward_10_rounded),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration value) {
    final totalSeconds = value.inSeconds.clamp(0, 359999);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class _TextFileViewer extends StatefulWidget {
  const _TextFileViewer({required this.filePath});

  final String filePath;

  @override
  State<_TextFileViewer> createState() => _TextFileViewerState();
}

class _TextFileViewerState extends State<_TextFileViewer> {
  static const int _previewLimitBytes = 2 * 1024 * 1024;

  bool _isLoading = true;
  String? _errorMessage;
  String _content = '';
  bool _truncated = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final file = File(widget.filePath);
      final bytes = await file.readAsBytes();
      final previewBytes = bytes.length > _previewLimitBytes
          ? bytes.sublist(0, _previewLimitBytes)
          : bytes;

      if (!mounted) {
        return;
      }
      setState(() {
        _content = utf8.decode(previewBytes, allowMalformed: true);
        _truncated = bytes.length > _previewLimitBytes;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Cannot read text file: $error';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return _ViewerError(message: _errorMessage!);
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_truncated)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Text(
                'Preview is truncated to 2 MB.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          if (_truncated) const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                _content,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFamily: 'JetBrainsMono',
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PdfFileViewer extends StatelessWidget {
  const _PdfFileViewer({required this.filePath});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    final file = File(filePath);
    return SfPdfViewer.file(
      file,
      canShowScrollHead: true,
      canShowScrollStatus: true,
      onDocumentLoadFailed: (details) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF load failed: ${details.error}')),
        );
      },
    );
  }
}

class _UnsupportedFileViewer extends StatelessWidget {
  const _UnsupportedFileViewer({required this.filePath, this.hintMessage});

  final String filePath;
  final String? hintMessage;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file_rounded, size: 42),
            const SizedBox(height: AppSpacing.sm),
            Text(
              hintMessage ??
                  'This file type is not supported by the built-in viewer yet.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: () async {
                await OpenFilex.open(filePath);
              },
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open externally'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerError extends StatelessWidget {
  const _ViewerError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.error),
        ),
      ),
    );
  }
}

String _mediaUriFromFilePath(String filePath) {
  return Uri.file(filePath).toString();
}

String _formatPlaybackDuration(Duration value) {
  final totalSeconds = value.inSeconds.clamp(0, 359999);
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

double _resolveVideoAspectRatio(PlayerState state) {
  final width = state.width ?? state.videoParams.dw ?? state.videoParams.w;
  final height = state.height ?? state.videoParams.dh ?? state.videoParams.h;
  if (width == null || height == null || width <= 0 || height <= 0) {
    return 16 / 9;
  }
  return width / height;
}
