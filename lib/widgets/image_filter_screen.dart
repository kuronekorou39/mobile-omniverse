import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../services/image_filter_service.dart';

/// 画像にフィルタを適用するための画面。
/// 適用後は新しい一時ファイルの XFile を pop で返す。キャンセルは null。
class ImageFilterScreen extends StatefulWidget {
  const ImageFilterScreen({super.key, required this.file});

  final XFile file;

  @override
  State<ImageFilterScreen> createState() => _ImageFilterScreenState();
}

class _ImageFilterScreenState extends State<ImageFilterScreen> {
  ImageFilter _selectedFilter = ImageFilter.none;
  Uint8List? _originalBytes;
  Uint8List? _previewBytes;
  bool _processing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadBytes();
  }

  Future<void> _loadBytes() async {
    final bytes = await widget.file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _originalBytes = bytes;
      _previewBytes = bytes;
    });
  }

  Future<void> _selectFilter(ImageFilter filter) async {
    if (_originalBytes == null || _processing) return;
    setState(() {
      _selectedFilter = filter;
      _processing = true;
    });
    final result =
        await ImageFilterService.instance.apply(_originalBytes!, filter);
    if (!mounted) return;
    setState(() {
      _previewBytes = result;
      _processing = false;
    });
  }

  Future<void> _apply() async {
    if (_saving) return;
    if (_selectedFilter == ImageFilter.none || _previewBytes == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/filter_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final file = File(path);
      await file.writeAsBytes(_previewBytes!);
      if (!mounted) return;
      Navigator.of(context).pop(XFile(path));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存に失敗: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('フィルタ'),
        actions: [
          TextButton(
            onPressed: _processing || _saving ? null : _apply,
            child: const Text('適用'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.black,
              child: Center(
                child: _previewBytes != null
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.memory(
                            _previewBytes!,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                          if (_processing)
                            const CircularProgressIndicator(),
                        ],
                      )
                    : const CircularProgressIndicator(),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                itemCount: ImageFilter.values.length,
                itemBuilder: (context, i) {
                  final filter = ImageFilter.values[i];
                  final selected = filter == _selectedFilter;
                  final primary = Theme.of(context).colorScheme.primary;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      onTap: () => _selectFilter(filter),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 76,
                        decoration: BoxDecoration(
                          color: selected
                              ? primary.withValues(alpha: 0.18)
                              : null,
                          border: Border.all(
                            color: selected
                                ? primary
                                : Theme.of(context).dividerColor,
                            width: selected ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            filter.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
