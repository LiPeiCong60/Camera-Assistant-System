import 'package:flutter/material.dart';

import 'auth_controller.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.controller,
    required this.onOpenServerSettings,
  });

  final AuthController controller;
  final VoidCallback onOpenServerSettings;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phoneController;
  late final TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    await widget.controller.login(
      phone: _phoneController.text.trim(),
      password: _passwordController.text,
    );
  }

  Future<void> _openRegisterPage() async {
    widget.controller.clearError();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RegisterPage(controller: widget.controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Color(0xFFF7F1E3),
              Color(0xFFDDE8D5),
              Color(0xFFC0D6DF),
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
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: AnimatedBuilder(
                        animation: widget.controller,
                        builder: (context, _) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              const _LoginBrandHeader(),
                              const SizedBox(height: 28),
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Form(
                                    key: _formKey,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: <Widget>[
                                                  Text(
                                                    '账号登录',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleLarge
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    widget
                                                        .controller
                                                        .serverConfig
                                                        .apiBaseUrl,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Color(0xFF5A6B70),
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: '后台连接设置',
                                              onPressed:
                                                  widget.onOpenServerSettings,
                                              icon: const Icon(
                                                Icons.settings_ethernet,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 18),
                                        TextFormField(
                                          controller: _phoneController,
                                          keyboardType: TextInputType.phone,
                                          decoration: const InputDecoration(
                                            labelText: '手机号',
                                            hintText: '请输入手机号',
                                          ),
                                          validator: (value) {
                                            if (value == null ||
                                                value.trim().isEmpty) {
                                              return '请输入手机号';
                                            }
                                            return null;
                                          },
                                        ),
                                        const SizedBox(height: 14),
                                        TextFormField(
                                          controller: _passwordController,
                                          obscureText: true,
                                          decoration: const InputDecoration(
                                            labelText: '密码',
                                            hintText: '请输入密码',
                                          ),
                                          validator: (value) {
                                            if (value == null ||
                                                value.isEmpty) {
                                              return '请输入密码';
                                            }
                                            return null;
                                          },
                                        ),
                                        if (widget.controller.errorMessage !=
                                            null) ...<Widget>[
                                          const SizedBox(height: 14),
                                          Text(
                                            widget.controller.errorMessage!,
                                            style: const TextStyle(
                                              color: Color(0xFF9E2A2B),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 20),
                                        SizedBox(
                                          width: double.infinity,
                                          child: FilledButton(
                                            onPressed:
                                                widget.controller.isLoggingIn
                                                ? null
                                                : _submit,
                                            style: FilledButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 16,
                                                  ),
                                              backgroundColor: const Color(
                                                0xFF0D5C63,
                                              ),
                                            ),
                                            child: widget.controller.isLoggingIn
                                                ? const SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  )
                                                : const Text('登录'),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton(
                                            onPressed: _openRegisterPage,
                                            style: OutlinedButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 16,
                                                  ),
                                            ),
                                            child: const Text('没有账号？去注册'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
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

class _LoginBrandHeader extends StatelessWidget {
  const _LoginBrandHeader();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 104,
          height: 104,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0x1A0D5C63)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x1F17313A),
                blurRadius: 26,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.asset(
              'assets/branding/app_logo.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'USER LOGIN',
          textAlign: TextAlign.center,
          style: textTheme.labelLarge?.copyWith(
            color: const Color(0xFF32535F),
            fontWeight: FontWeight.w700,
            letterSpacing: 3.2,
          ),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '云影随行',
              maxLines: 1,
              textAlign: TextAlign.center,
              style: textTheme.displayMedium?.copyWith(
                color: const Color(0xFF17313A),
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '用户端登录',
          textAlign: TextAlign.center,
          style: textTheme.titleMedium?.copyWith(
            color: const Color(0xFF17313A),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
