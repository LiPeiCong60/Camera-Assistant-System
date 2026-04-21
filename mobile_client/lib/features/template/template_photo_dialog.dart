import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class TemplatePhotoDraft {
  const TemplatePhotoDraft({
    required this.name,
    required this.filePath,
  });

  final String name;
  final String filePath;
}

Future<TemplatePhotoDraft?> showTemplatePhotoDialog(
  BuildContext context, {
  String title = '新增模板',
}) {
  return showDialog<TemplatePhotoDraft>(
    context: context,
    builder: (context) => _TemplatePhotoDialog(title: title),
  );
}

class _TemplatePhotoDialog extends StatefulWidget {
  const _TemplatePhotoDialog({required this.title});

  final String title;

  @override
  State<_TemplatePhotoDialog> createState() => _TemplatePhotoDialogState();
}

class _TemplatePhotoDialogState extends State<_TemplatePhotoDialog> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();
  late final TextEditingController _nameController;

  String? _selectedImagePath;
  bool _isPickingImage = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
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
                '上传后会自动识别照片中的人物姿势与位置，并生成可用于拍照页和设备联动页的模板。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              if (previewPath != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 4 / 5,
                    child: Image.file(
                      File(previewPath),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3EEE3),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Center(
                            child: Text('照片预览加载失败'),
                          ),
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
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE5D8C5)),
                  ),
                  child: const Text(
                    '请先选择一张包含人物的照片。\n建议人物主体清晰、无遮挡，并尽量完整出现在画面内。',
                  ),
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
            if (_selectedImagePath == null || _selectedImagePath!.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请先选择模板照片')),
              );
              return;
            }
            Navigator.of(context).pop(
              TemplatePhotoDraft(
                name: _nameController.text.trim(),
                filePath: _selectedImagePath!,
              ),
            );
          },
          child: const Text('开始识别'),
        ),
      ],
    );
  }
}
