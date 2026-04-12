import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/feed_provider.dart';

const _channel = MethodChannel('com.omniverse/device_info');

class PerfOverlay extends ConsumerStatefulWidget {
  const PerfOverlay({super.key});

  @override
  ConsumerState<PerfOverlay> createState() => _PerfOverlayState();
}

class _PerfOverlayState extends ConsumerState<PerfOverlay> {
  Timer? _timer;
  int _rssBytes = 0;
  int _imageCacheCount = 0;
  int _imageCacheBytes = 0;
  double _fps = 0;
  double _temperature = -1;
  double _batteryPercent = -1;
  int _txBytes = 0;
  int _rxBytes = 0;
  int _prevTxBytes = -1;
  int _prevRxBytes = -1;
  int _txPerSec = 0;
  int _rxPerSec = 0;
  final List<double> _frameDurations = [];

  @override
  void initState() {
    super.initState();
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  @override
  void dispose() {
    _timer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final durationMs = t.totalSpan.inMicroseconds / 1000.0;
      _frameDurations.add(durationMs);
    }
    if (_frameDurations.length > 120) {
      _frameDurations.removeRange(0, _frameDurations.length - 120);
    }
  }

  Future<void> _update() async {
    if (!mounted) return;

    final rss = ProcessInfo.currentRss;
    final imageCache = PaintingBinding.instance.imageCache;

    double fps = 0;
    if (_frameDurations.isNotEmpty) {
      final avg = _frameDurations.reduce((a, b) => a + b) / _frameDurations.length;
      fps = avg > 0 ? (1000.0 / avg).clamp(0, 120) : 0;
    }

    double temp = _temperature;
    double battery = _batteryPercent;
    int txBytes = _txBytes;
    int rxBytes = _rxBytes;
    try {
      final info = await _channel.invokeMethod<Map>('getDeviceInfo');
      if (info != null) {
        temp = (info['temperature'] as num?)?.toDouble() ?? -1;
        battery = (info['batteryPercent'] as num?)?.toDouble() ?? -1;
        txBytes = (info['txBytes'] as num?)?.toInt() ?? 0;
        rxBytes = (info['rxBytes'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}

    // 通信速度 (bytes/sec)
    int txSec = 0;
    int rxSec = 0;
    if (_prevTxBytes >= 0) {
      txSec = txBytes - _prevTxBytes;
      rxSec = rxBytes - _prevRxBytes;
    }

    if (!mounted) return;
    setState(() {
      _rssBytes = rss;
      _imageCacheCount = imageCache.currentSize;
      _imageCacheBytes = imageCache.currentSizeBytes;
      _fps = fps;
      _temperature = temp;
      _batteryPercent = battery;
      _prevTxBytes = txBytes;
      _prevRxBytes = rxBytes;
      _txBytes = txBytes;
      _rxBytes = rxBytes;
      _txPerSec = txSec;
      _rxPerSec = rxSec;
    });
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatSpeed(int bytesPerSec) {
    if (bytesPerSec < 1024) return '$bytesPerSec B/s';
    if (bytesPerSec < 1024 * 1024) return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider);
    final postCount = feed.posts.length;
    final pendingCount = feed.pendingCount;

    final tempColor = _temperature >= 40
        ? Colors.redAccent
        : _temperature >= 35
            ? Colors.orangeAccent
            : Colors.greenAccent;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 48,
      right: 8,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(180),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DefaultTextStyle(
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: Colors.greenAccent,
              height: 1.4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('RSS  ${_formatBytes(_rssBytes)}'),
                Text('IMG  $_imageCacheCount (${_formatBytes(_imageCacheBytes)})'),
                Text('POST $postCount  Q:$pendingCount'),
                Text('FPS  ${_fps.toStringAsFixed(1)}'),
                if (_temperature >= 0)
                  Text(
                    'TEMP ${_temperature.toStringAsFixed(1)}°C',
                    style: TextStyle(color: tempColor),
                  ),
                if (_batteryPercent >= 0)
                  Text('BAT  ${_batteryPercent.toStringAsFixed(0)}%'),
                Text('NET  ${_formatBytes(_rxBytes + _txBytes)}'),
                Text('  ↓${_formatSpeed(_rxPerSec)} ↑${_formatSpeed(_txPerSec)}'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
