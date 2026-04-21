import 'dart:convert';

import 'package:flutter/material.dart';

class TemplateDraft {
  const TemplateDraft({
    required this.name,
    required this.templateType,
    required this.templateData,
  });

  final String name;
  final String templateType;
  final Map<String, dynamic> templateData;
}

class _TemplatePreset {
  const _TemplatePreset({
    required this.key,
    required this.label,
    required this.suggestedName,
    required this.templateData,
  });

  final String key;
  final String label;
  final String suggestedName;
  final Map<String, dynamic> templateData;
}

const List<_TemplatePreset> _presets = <_TemplatePreset>[
  _TemplatePreset(
    key: 'half_body',
    label: '半身人像',
    suggestedName: '半身人像模板',
    templateData: <String, dynamic>{
      'bbox_norm': <double>[0.30, 0.12, 0.38, 0.72],
      'pose_points': <String, List<double>>{
        '00': <double>[0.49, 0.16],
        '01': <double>[0.43, 0.26],
        '02': <double>[0.55, 0.26],
        '03': <double>[0.39, 0.38],
        '04': <double>[0.59, 0.38],
        '05': <double>[0.45, 0.50],
        '06': <double>[0.53, 0.50],
        '07': <double>[0.44, 0.66],
        '08': <double>[0.56, 0.66],
      },
    },
  ),
  _TemplatePreset(
    key: 'full_body',
    label: '全身站姿',
    suggestedName: '全身站姿模板',
    templateData: <String, dynamic>{
      'bbox_norm': <double>[0.28, 0.06, 0.42, 0.86],
      'pose_points': <String, List<double>>{
        '00': <double>[0.49, 0.10],
        '01': <double>[0.43, 0.21],
        '02': <double>[0.55, 0.21],
        '03': <double>[0.39, 0.34],
        '04': <double>[0.59, 0.34],
        '05': <double>[0.45, 0.48],
        '06': <double>[0.53, 0.48],
        '07': <double>[0.45, 0.72],
        '08': <double>[0.53, 0.72],
        '09': <double>[0.45, 0.90],
        '10': <double>[0.53, 0.90],
      },
    },
  ),
  _TemplatePreset(
    key: 'close_up',
    label: '近景构图',
    suggestedName: '近景构图模板',
    templateData: <String, dynamic>{
      'bbox_norm': <double>[0.24, 0.08, 0.52, 0.54],
      'pose_points': <String, List<double>>{
        '00': <double>[0.50, 0.14],
        '01': <double>[0.40, 0.24],
        '02': <double>[0.60, 0.24],
        '03': <double>[0.37, 0.38],
        '04': <double>[0.63, 0.38],
      },
    },
  ),
];

Future<TemplateDraft?> showTemplatePresetDialog(
  BuildContext context, {
  String title = '新增模板',
}) {
  return showDialog<TemplateDraft>(
    context: context,
    builder: (context) => _TemplatePresetDialog(title: title),
  );
}

class _TemplatePresetDialog extends StatefulWidget {
  const _TemplatePresetDialog({required this.title});

  final String title;

  @override
  State<_TemplatePresetDialog> createState() => _TemplatePresetDialogState();
}

class _TemplatePresetDialogState extends State<_TemplatePresetDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  String _selectedPresetKey = _presets.first.key;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: _presets.first.suggestedName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  _TemplatePreset get _selectedPreset =>
      _presets.firstWhere((item) => item.key == _selectedPresetKey);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            DropdownButtonFormField<String>(
              initialValue: _selectedPresetKey,
              decoration: const InputDecoration(labelText: '模板预设'),
              items: _presets
                  .map(
                    (preset) => DropdownMenuItem<String>(
                      value: preset.key,
                      child: Text(preset.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                final preset = _presets.firstWhere((item) => item.key == value);
                setState(() {
                  _selectedPresetKey = value;
                  if (_nameController.text.trim().isEmpty ||
                      _nameController.text == _selectedPreset.suggestedName) {
                    _nameController.text = preset.suggestedName;
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '创建后可在拍照页和设备联动页直接选中并继续使用。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
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
            Navigator.of(context).pop(
              TemplateDraft(
                name: _nameController.text.trim(),
                templateType: 'pose',
                templateData: jsonDecode(
                      jsonEncode(_selectedPreset.templateData),
                    )
                    as Map<String, dynamic>,
              ),
            );
          },
          child: const Text('创建'),
        ),
      ],
    );
  }
}
