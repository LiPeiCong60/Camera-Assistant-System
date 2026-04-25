import 'package:flutter/material.dart';

import '../../services/app_config.dart';

class ServerConfigPage extends StatefulWidget {
  const ServerConfigPage({
    super.key,
    required this.initialConfig,
    required this.onSaved,
    this.onCancel,
  });

  final ServerConfig initialConfig;
  final Future<void> Function(ServerConfig config) onSaved;
  final VoidCallback? onCancel;

  @override
  State<ServerConfigPage> createState() => _ServerConfigPageState();
}

class _ServerConfigPageState extends State<ServerConfigPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _apiBaseUrlController;
  late final TextEditingController _deviceApiBaseUrlController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _apiBaseUrlController = TextEditingController(
      text: widget.initialConfig.apiBaseUrl,
    );
    _deviceApiBaseUrlController = TextEditingController(
      text: widget.initialConfig.deviceApiBaseUrl,
    );
  }

  @override
  void dispose() {
    _apiBaseUrlController.dispose();
    _deviceApiBaseUrlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isSaving = true;
    });
    final config = ServerConfig(
      apiBaseUrl: AppConfig.normalizeApiBaseUrl(_apiBaseUrlController.text),
      deviceApiBaseUrl: AppConfig.normalizeDeviceApiBaseUrl(
        _deviceApiBaseUrlController.text,
      ),
    );
    try {
      await widget.onSaved(config);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _syncDeviceHost() {
    final apiUri = Uri.tryParse(_apiBaseUrlController.text.trim());
    if (apiUri == null || !apiUri.hasScheme || apiUri.host.isEmpty) {
      return;
    }
    final deviceUri = apiUri.replace(
      port: apiUri.hasPort ? 8001 : null,
      path: '',
      query: '',
      fragment: '',
    );
    _deviceApiBaseUrlController.text = deviceUri.toString().replaceFirst(
      RegExp(r'/$'),
      '',
    );
  }

  String? _validateUrl(String? value, {required bool requireApiPath}) {
    final rawValue = value?.trim() ?? '';
    if (rawValue.isEmpty) {
      return '请输入地址';
    }
    final uri = Uri.tryParse(rawValue);
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return '请输入 http:// 或 https:// 开头的完整地址';
    }
    if (requireApiPath &&
        !AppConfig.normalizeApiBaseUrl(rawValue).endsWith('/api')) {
      return '业务后台地址需要指向 /api';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Color(0xFFF7F1E3),
              Color(0xFFEAF2F4),
              Color(0xFFDCE8D2),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 500),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0D5C63),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Icon(
                                    Icons.settings_ethernet,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  '后台连接设置',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                        color: const Color(0xFF17313A),
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            '先填写电脑或服务器在手机网络中能访问到的地址。换 Wi-Fi 后，只要回到这里改一次就行。',
                            style: TextStyle(
                              color: Color(0xFF4B5563),
                              height: 1.55,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(22),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    TextFormField(
                                      controller: _apiBaseUrlController,
                                      keyboardType: TextInputType.url,
                                      decoration: const InputDecoration(
                                        labelText: '业务后台地址',
                                        hintText: 'http://192.168.1.3:8000/api',
                                        prefixIcon: Icon(Icons.cloud_outlined),
                                      ),
                                      validator: (value) => _validateUrl(
                                        value,
                                        requireApiPath: true,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    TextFormField(
                                      controller: _deviceApiBaseUrlController,
                                      keyboardType: TextInputType.url,
                                      decoration: InputDecoration(
                                        labelText: '设备运行时地址',
                                        hintText: 'http://192.168.1.3:8001',
                                        prefixIcon: const Icon(
                                          Icons.router_outlined,
                                        ),
                                        suffixIcon: IconButton(
                                          tooltip: '使用业务后台同一台主机',
                                          onPressed: _syncDeviceHost,
                                          icon: const Icon(Icons.sync_alt),
                                        ),
                                      ),
                                      validator: (value) => _validateUrl(
                                        value,
                                        requireApiPath: false,
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEAF2F4),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: const Padding(
                                        padding: EdgeInsets.all(14),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Icon(
                                              Icons.info_outline,
                                              color: Color(0xFF0D5C63),
                                            ),
                                            SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                '真机不要用 127.0.0.1 或 10.0.2.2。请用电脑当前局域网 IP，例如 192.168.x.x。',
                                                style: TextStyle(
                                                  color: Color(0xFF32535F),
                                                  height: 1.45,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 22),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: _isSaving ? null : _save,
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 16,
                                          ),
                                          backgroundColor: const Color(
                                            0xFF0D5C63,
                                          ),
                                        ),
                                        icon: _isSaving
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(Icons.check),
                                        label: const Text('保存并继续'),
                                      ),
                                    ),
                                    if (widget.onCancel != null) ...<Widget>[
                                      const SizedBox(height: 10),
                                      SizedBox(
                                        width: double.infinity,
                                        child: TextButton(
                                          onPressed: _isSaving
                                              ? null
                                              : widget.onCancel,
                                          child: const Text('返回登录'),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
