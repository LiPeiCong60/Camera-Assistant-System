part of '../device_link_page.dart';

class _AiScanConfig {
  const _AiScanConfig({
    required this.panRange,
    required this.tiltRange,
    required this.panStep,
    required this.tiltStep,
    required this.maxCandidates,
    required this.settleSeconds,
    required this.delaySeconds,
  });

  final double panRange;
  final double tiltRange;
  final double panStep;
  final double tiltStep;
  final int maxCandidates;
  final double settleSeconds;
  final double delaySeconds;
}

class _AiScanConfigDialog extends StatefulWidget {
  const _AiScanConfigDialog({required this.title, required this.includeDelay});

  final String title;
  final bool includeDelay;

  @override
  State<_AiScanConfigDialog> createState() => _AiScanConfigDialogState();
}

class _AiScanConfigDialogState extends State<_AiScanConfigDialog> {
  late final TextEditingController _panRangeController;
  late final TextEditingController _tiltRangeController;
  late final TextEditingController _panStepController;
  late final TextEditingController _tiltStepController;
  late final TextEditingController _maxCandidatesController;
  late final TextEditingController _settleController;
  late final TextEditingController _delayController;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _panRangeController = TextEditingController(text: '6');
    _tiltRangeController = TextEditingController(text: '3');
    _panStepController = TextEditingController(text: '4');
    _tiltStepController = TextEditingController(text: '3');
    _maxCandidatesController = TextEditingController(text: '5');
    _settleController = TextEditingController(text: '0.5');
    _delayController = TextEditingController(text: '0');
  }

  @override
  void dispose() {
    _panRangeController.dispose();
    _tiltRangeController.dispose();
    _panStepController.dispose();
    _tiltStepController.dispose();
    _maxCandidatesController.dispose();
    _settleController.dispose();
    _delayController.dispose();
    super.dispose();
  }

  void _submit() {
    final panRange = double.tryParse(_panRangeController.text.trim());
    final tiltRange = double.tryParse(_tiltRangeController.text.trim());
    final panStep = double.tryParse(_panStepController.text.trim());
    final tiltStep = double.tryParse(_tiltStepController.text.trim());
    final maxCandidates = int.tryParse(_maxCandidatesController.text.trim());
    final settleSeconds = double.tryParse(_settleController.text.trim());
    final delaySeconds = double.tryParse(_delayController.text.trim()) ?? 0;

    if (panRange == null ||
        tiltRange == null ||
        panStep == null ||
        tiltStep == null ||
        maxCandidates == null ||
        settleSeconds == null) {
      setState(() {
        _errorMessage = '请填写有效数字。';
      });
      return;
    }
    if (panRange < 1 ||
        tiltRange < 1 ||
        panStep < 0.8 ||
        tiltStep < 0.8 ||
        maxCandidates < 2 ||
        maxCandidates > 9 ||
        settleSeconds < 0.1 ||
        delaySeconds < 0) {
      setState(() {
        _errorMessage = '参数超出树莓派允许范围，请调小或恢复默认值。';
      });
      return;
    }

    Navigator.of(context).pop(
      _AiScanConfig(
        panRange: panRange,
        tiltRange: tiltRange,
        panStep: panStep,
        tiltStep: tiltStep,
        maxCandidates: maxCandidates,
        settleSeconds: settleSeconds,
        delaySeconds: delaySeconds,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: _numberField('横向范围', _panRangeController)),
                const SizedBox(width: 10),
                Expanded(child: _numberField('纵向范围', _tiltRangeController)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(child: _numberField('横向步长', _panStepController)),
                const SizedBox(width: 10),
                Expanded(child: _numberField('纵向步长', _tiltStepController)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(child: _numberField('拍摄数量', _maxCandidatesController)),
                const SizedBox(width: 10),
                Expanded(child: _numberField('稳定等待', _settleController)),
              ],
            ),
            if (widget.includeDelay) ...<Widget>[
              const SizedBox(height: 10),
              _numberField('延迟秒数', _delayController),
            ],
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: Color(0xFFB9442F),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('启动')),
      ],
    );
  }

  Widget _numberField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
