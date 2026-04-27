import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

enum TemplateRecognitionMode { backend, local }

class TemplatePhotoDraft {
  const TemplatePhotoDraft({
    required this.name,
    required this.filePath,
    required this.recognitionMode,
  });

  final String name;
  final String filePath;
  final TemplateRecognitionMode recognitionMode;
}

Future<TemplatePhotoDraft?> showTemplatePhotoDialog(
  BuildContext context, {
  String title = '新增模板',
  Set<TemplateRecognitionMode> enabledRecognitionModes =
      const <TemplateRecognitionMode>{
        TemplateRecognitionMode.backend,
        TemplateRecognitionMode.local,
      },
}) {
  return showDialog<TemplatePhotoDraft>(
    context: context,
    builder: (context) => _TemplatePhotoDialog(
      title: title,
      enabledRecognitionModes: enabledRecognitionModes,
    ),
  );
}

class _TemplatePhotoDialog extends StatefulWidget {
  const _TemplatePhotoDialog({
    required this.title,
    required this.enabledRecognitionModes,
  });

  final String title;
  final Set<TemplateRecognitionMode> enabledRecognitionModes;

  @override
  State<_TemplatePhotoDialog> createState() => _TemplatePhotoDialogState();
}

class _TemplatePhotoDialogState extends State<_TemplatePhotoDialog> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();
  late final TextEditingController _nameController;

  String? _selectedImagePath;
  bool _isPickingImage = false;
  TemplateRecognitionMode _recognitionMode = TemplateRecognitionMode.backend;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    if (!widget.enabledRecognitionModes.contains(_recognitionMode)) {
      _recognitionMode = widget.enabledRecognitionModes.first;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_isPickingImage) {
      return;
    }

    setState(() {
      _isPickingImage = true;
    });

    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );
      if (!mounted || picked == null) {
        return;
      }

      final suggestedName = _buildSuggestedName(picked.path);
      setState(() {
        _selectedImagePath = picked.path;
        if (_nameController.text.trim().isEmpty) {
          _nameController.text = suggestedName;
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPickingImage = false;
        });
      }
    }
  }

  String _buildSuggestedName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final fileName = normalized.split('/').last;
    final dotIndex = fileName.lastIndexOf('.');
    final baseName = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    final safeName = baseName.trim();
    return safeName.isEmpty ? '新模板' : safeName;
  }

  @override
  Widget build(BuildContext context) {
    final previewPath = _selectedImagePath;

    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '模板名称',
                  hintText: '请输入模板名称',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入模板名称';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              if (widget.enabledRecognitionModes.length > 1) ...<Widget>[
                SegmentedButton<TemplateRecognitionMode>(
                  segments: const <ButtonSegment<TemplateRecognitionMode>>[
                    ButtonSegment<TemplateRecognitionMode>(
                      value: TemplateRecognitionMode.backend,
                      icon: Icon(Icons.cloud_upload_outlined),
                      label: Text('后端识别'),
                    ),
                    ButtonSegment<TemplateRecognitionMode>(
                      value: TemplateRecognitionMode.local,
                      icon: Icon(Icons.phone_android_outlined),
                      label: Text('本地识别'),
                    ),
                  ],
                  selected: <TemplateRecognitionMode>{_recognitionMode},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _recognitionMode = selection.first;
                    });
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  _recognitionMode == TemplateRecognitionMode.backend
                      ? '默认上传到后端识别，适合稳定保存和后续设备联动。'
                      : '本地识别会先在手机上提取人体姿态，再保存模板；后端识别不出来时可以试这条路。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
              ] else ...<Widget>[
                Text(
                  '将上传到后端识别人体姿态，并保存为可用于拍摄和设备联动的模板。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
              ],
              FilledButton.tonalIcon(
                onPressed: _isPickingImage ? null : _pickImage,
                icon: _isPickingImage
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_library_outlined),
                label: Text(previewPath == null ? '选择模板照片' : '重新选择照片'),
              ),
              const SizedBox(height: 10),
              Text(
                '建议选择人物主体清晰、遮挡少、身体尽量完整出现在画面内的照片。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              if (previewPath != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 4 / 5,
                    child: Image.file(
                      File(previewPath),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3EEE3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(child: Text('照片预览加载失败')),
                        );
                      },
                    ),
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F1E7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5D8C5)),
                  ),
                  child: const Text('请先选择一张包含人物的照片。'),
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }
            if (_selectedImagePath == null ||
                _selectedImagePath!.trim().isEmpty) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('请先选择模板照片')));
              return;
            }
            Navigator.of(context).pop(
              TemplatePhotoDraft(
                name: _nameController.text.trim(),
                filePath: _selectedImagePath!,
                recognitionMode: _recognitionMode,
              ),
            );
          },
          child: const Text('开始识别'),
        ),
      ],
    );
  }
}
