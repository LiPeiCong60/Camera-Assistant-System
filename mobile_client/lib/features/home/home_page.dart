import 'package:flutter/material.dart';

import '../../models/auth_session.dart';
import '../../models/plan_summary.dart';
import '../../models/template_summary.dart';
import '../../services/api_client.dart';
import '../../services/gallery_save_service.dart';
import '../auth/auth_controller.dart';
import '../camera/camera_capture_page.dart';
import '../device_link/device_link_page.dart';
import '../history/history_page.dart';
import '../settings/detailed_settings_page.dart';
import '../template/template_photo_dialog.dart';
import 'plan_detail_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});

  final AuthController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final profile = controller.profile;
        final session = controller.session;
        final currentPlan = _currentPlan(controller);

        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/branding/app_logo.png',
                    width: 28,
                    height: 28,
                  ),
                ),
                const SizedBox(width: 10),
                const Text('云影随行'),
              ],
            ),
            actions: <Widget>[
              IconButton(
                tooltip: '刷新基础数据',
                onPressed: controller.isRefreshing
                    ? null
                    : controller.refreshDashboard,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: '退出登录',
                onPressed: () async {
                  await controller.logout();
                },
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: controller.refreshDashboard,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: <Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: <Color>[Color(0xFF0D5C63), Color(0xFF3A7D44)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '欢迎回来',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.88),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2.8,
                              ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '你好，${profile?.displayName ?? session?.user.displayName ?? '用户'}',
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                height: 0.98,
                              ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: _InfoChip(
                                label: '用户编号',
                                value:
                                    profile?.userCode ??
                                    (session == null
                                        ? '-'
                                        : 'USER_${session.user.id}'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _InfoChip(
                                label: '角色',
                                value:
                                    profile?.role ?? session?.user.role ?? '-',
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _InfoChip(
                                label: '状态',
                                value:
                                    profile?.status ??
                                    session?.user.status ??
                                    '-',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _QuickActionSection(controller: controller, session: session),
                const SizedBox(height: 20),
                if (controller.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      controller.errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFF9E2A2B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: _StatusCard(
                        title: '当前订阅',
                        value: _subscriptionStatusLabel(controller),
                        note: _subscriptionNoteLabel(controller, currentPlan),
                        onTap: session == null
                            ? null
                            : () => _openPlanDetails(
                                context,
                                controller: controller,
                                accessToken: session.accessToken,
                                initialPlanId: controller.subscription?.planId,
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _StatusCard(
                        title: '详细设置',
                        value: '设置',
                        note: '模板、拍摄、设备、AI',
                        onTap: session == null
                            ? null
                            : () => _openDetailedSettings(
                                context,
                                controller: controller,
                                session: session,
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  '服务连接：${_serviceStatusLabel(controller)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF7A8588),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _subscriptionStatusLabel(AuthController controller) {
    final subscription = controller.subscription;
    if (subscription == null) {
      return '未开通';
    }
    if (subscription.status == 'active') {
      return '生效中';
    }
    return subscription.status;
  }

  String _subscriptionNoteLabel(
    AuthController controller,
    PlanSummary? currentPlan,
  ) {
    if (currentPlan == null) {
      final count = controller.plans.length;
      return count == 0 ? '点击查看套餐详情' : '未开通 · 共 $count 个套餐';
    }
    final subscription = controller.subscription;
    final captureQuota = subscription?.captureQuota ?? currentPlan.captureQuota;
    final aiQuota = subscription?.aiTaskQuota ?? currentPlan.aiTaskQuota;
    final quotaLabel = <String>[
      if (captureQuota != null) '拍摄 $captureQuota',
      if (aiQuota != null) 'AI $aiQuota',
    ].join(' · ');
    return quotaLabel.isEmpty
        ? '${currentPlan.name} · 点击查看详情'
        : '${currentPlan.name} · $quotaLabel';
  }

  String _serviceStatusLabel(AuthController controller) {
    if (controller.isRefreshing) {
      return '同步中';
    }
    if (controller.errorMessage != null) {
      return '需要检查';
    }
    return '已接通';
  }

  PlanSummary? _currentPlan(AuthController controller) {
    final subscription = controller.subscription;
    if (subscription == null) {
      return null;
    }
    for (final plan in controller.plans) {
      if (plan.id == subscription.planId) {
        return plan;
      }
    }
    return null;
  }

  Future<void> _openPlanDetails(
    BuildContext context, {
    required AuthController controller,
    required String accessToken,
    int? initialPlanId,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PlanDetailPage(
          controller: controller,
          accessToken: accessToken,
          initialPlanId: initialPlanId,
        ),
      ),
    );
  }

  Future<void> _openDetailedSettings(
    BuildContext context, {
    required AuthController controller,
    required AuthSession session,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DetailedSettingsPage(
          controller: controller,
          session: session,
          serviceStatus: _serviceStatusLabel(controller),
        ),
      ),
    );
  }
}

class _MoreOptionsSheet extends StatefulWidget {
  const _MoreOptionsSheet({
    required this.controller,
    required this.session,
    required this.serviceStatus,
  });

  final AuthController controller;
  final AuthSession session;
  final String serviceStatus;

  @override
  State<_MoreOptionsSheet> createState() => _MoreOptionsSheetState();
}

class _MoreOptionsSheetState extends State<_MoreOptionsSheet> {
  List<TemplateSummary> _templates = const <TemplateSummary>[];
  bool _isLoadingTemplates = true;
  bool _isBusy = false;
  String? _message;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _isLoadingTemplates = true;
      _errorMessage = null;
    });

    try {
      final templates = await widget.controller.apiService.listTemplates(
        accessToken: widget.session.accessToken,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _templates = templates;
      });
    } on ApiException catch (error) {
      final cached = await widget.controller.apiService.getCachedTemplates();
      if (!mounted) {
        return;
      }
      setState(() {
        _templates = cached;
        _errorMessage = cached.isEmpty ? error.message : '模板列表刷新失败，已显示本地缓存。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTemplates = false;
        });
      }
    }
  }

  Future<void> _createTemplate() async {
    if (_isBusy) {
      return;
    }
    final draft = await showTemplatePhotoDialog(
      context,
      title: '新增模板',
      enabledRecognitionModes: const <TemplateRecognitionMode>{
        TemplateRecognitionMode.backend,
      },
    );
    if (!mounted || draft == null) {
      return;
    }

    setState(() {
      _isBusy = true;
      _message = null;
      _errorMessage = null;
    });

    try {
      final template = await widget.controller.apiService
          .createTemplateFromPhoto(
            accessToken: widget.session.accessToken,
            name: draft.name,
            filePath: draft.filePath,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _templates = <TemplateSummary>[
          template,
          ..._templates.where((item) => item.id != template.id),
        ];
        _message = '已创建模板：${template.name}';
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '模板创建失败，请稍后重试。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _deleteTemplate(TemplateSummary template) async {
    if (_isBusy) {
      return;
    }
    if (template.isRecommendedDefault) {
      setState(() {
        _message = null;
        _errorMessage = '后台推荐模板不能在手机端删除。';
      });
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除模板'),
        content: Text('确认删除模板“${template.name}”吗？删除后无法继续选中它。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }

    setState(() {
      _isBusy = true;
      _message = null;
      _errorMessage = null;
    });

    try {
      await widget.controller.apiService.deleteTemplate(
        accessToken: widget.session.accessToken,
        templateId: template.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _templates = _templates
            .where((item) => item.id != template.id)
            .toList(growable: false);
        _message = '已删除模板：${template.name}';
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '模板删除失败，请稍后重试。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        initialChildSize: 0.82,
        minChildSize: 0.48,
        maxChildSize: 0.94,
        expand: false,
        builder: (context, scrollController) {
          return DecoratedBox(
            decoration: const BoxDecoration(
              color: Color(0xFFF8F4EA),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
              children: <Widget>[
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFB8C3C4),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '模板列表',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: const Color(0xFF17313A),
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _OptionTile(
                        icon: Icons.add_photo_alternate_outlined,
                        title: '创建模板',
                        subtitle: '上传人物照片生成模板',
                        onTap: _isBusy ? null : _createTemplate,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _OptionTile(
                        icon: Icons.refresh,
                        title: '刷新模板',
                        subtitle: '同步模板列表',
                        onTap: _isBusy ? null : _loadTemplates,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '模板管理',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: const Color(0xFF17313A),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '刷新模板',
                      onPressed: _isLoadingTemplates ? null : _loadTemplates,
                      icon: const Icon(Icons.sync),
                    ),
                  ],
                ),
                if (_isBusy || _isLoadingTemplates) ...<Widget>[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(minHeight: 3),
                ],
                if (_message != null) ...<Widget>[
                  const SizedBox(height: 10),
                  _SheetMessage(text: _message!, isError: false),
                ],
                if (_errorMessage != null) ...<Widget>[
                  const SizedBox(height: 10),
                  _SheetMessage(text: _errorMessage!, isError: true),
                ],
                const SizedBox(height: 10),
                if (!_isLoadingTemplates && _templates.isEmpty)
                  const _EmptyBlock(
                    title: '暂无模板',
                    subtitle: '点击上方“创建模板”，上传一张人物照片后生成模板。',
                  )
                else
                  ..._templates.map(
                    (template) => _TemplateManageRow(
                      template: template,
                      onDelete: _isBusy
                          ? null
                          : () => _deleteTemplate(template),
                    ),
                  ),
                const SizedBox(height: 18),
                Text(
                  '服务连接：${widget.serviceStatus}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF7A8588),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFDCE5E7)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(icon, color: const Color(0xFF0D5C63), size: 24),
                const SizedBox(height: 10),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF17313A),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF5A6B70),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TemplateManageRow extends StatelessWidget {
  const _TemplateManageRow({required this.template, required this.onDelete});

  final TemplateSummary template;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFDCE5E7)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2F4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.layers_outlined,
                  color: Color(0xFF0D5C63),
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      template.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF17313A),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      template.isRecommendedDefault
                          ? '后台推荐模板'
                          : '${template.templateType} · ${template.status}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF5A6B70),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: template.isRecommendedDefault ? '推荐模板不能删除' : '删除模板',
                onPressed: template.isRecommendedDefault ? null : onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetMessage extends StatelessWidget {
  const _SheetMessage({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFFF0F0) : const Color(0xFFE9F6F1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isError ? const Color(0xFFF0B7B7) : const Color(0xFFB9DED1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          text,
          style: TextStyle(
            color: isError ? const Color(0xFF9E2A2B) : const Color(0xFF0D5C63),
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _QuickActionSection extends StatelessWidget {
  const _QuickActionSection({required this.controller, required this.session});

  final AuthController controller;
  final AuthSession? session;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '快捷入口',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        _QuickActionCard(
          title: '开始拍摄',
          subtitle: '进入拍摄工作台',
          icon: Icons.camera_alt_outlined,
          highlighted: true,
          compact: false,
          onTap: session == null
              ? null
              : () async {
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => CameraCapturePage(
                        apiService: controller.apiService,
                        accessToken: session!.accessToken,
                        detailedSettingsBuilder: (_) => DetailedSettingsPage(
                          controller: controller,
                          session: session!,
                          serviceStatus: '已接通',
                        ),
                      ),
                    ),
                  );
                },
        ),
        const SizedBox(height: 12),
        _QuickActionCard(
          title: '进入设备联动',
          subtitle: '连接树莓派云台，使用手机画面自动跟随',
          icon: Icons.router_outlined,
          compact: false,
          onTap: session == null
              ? null
              : () async {
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => DeviceLinkPage(
                        mobileApiService: controller.apiService,
                        accessToken: session!.accessToken,
                        initialDeviceApiBaseUrl:
                            controller.serverConfig.deviceApiBaseUrl,
                        detailedSettingsBuilder: (_) => DetailedSettingsPage(
                          controller: controller,
                          session: session!,
                          serviceStatus: '已接通',
                        ),
                      ),
                    ),
                  );
                },
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: _QuickActionCard(
                title: '查看历史记录',
                subtitle: '查看历史会话与抓拍',
                icon: Icons.history_outlined,
                compact: true,
                onTap: session == null
                    ? null
                    : () async {
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => HistoryPage(
                              apiService: controller.apiService,
                              accessToken: session!.accessToken,
                            ),
                          ),
                        );
                      },
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _QuickActionCard(
                title: '本机相册',
                subtitle: '查看已保存照片和视频',
                icon: Icons.photo_library_outlined,
                compact: true,
                onTap: () async {
                  final opened = await const GallerySaveService().openGallery();
                  if (!context.mounted) {
                    return;
                  }
                  if (!opened) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('无法打开本机相册，请从系统图库进入。')),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.highlighted = false,
    required this.compact,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Future<void> Function()? onTap;
  final bool highlighted;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          decoration: BoxDecoration(
            color: highlighted ? const Color(0xFF17313A) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: highlighted
                  ? const Color(0xFF17313A)
                  : const Color(0xFFDCE5E7),
            ),
            boxShadow: compact
                ? const <BoxShadow>[]
                : const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x0F000000),
                      blurRadius: 14,
                      offset: Offset(0, 6),
                    ),
                  ],
          ),
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: EdgeInsets.all(compact ? 18 : 20),
              child: compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          icon,
                          color: highlighted
                              ? const Color(0xFFE0A458)
                              : const Color(0xFF0D5C63),
                          size: 26,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: highlighted
                                ? Colors.white
                                : const Color(0xFF17313A),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: highlighted
                                ? Colors.white.withValues(alpha: 0.78)
                                : const Color(0xFF4B5563),
                            height: 1.45,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: <Widget>[
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: highlighted
                                ? Colors.white.withValues(alpha: 0.08)
                                : const Color(0xFFEAF2F4),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Icon(
                              icon,
                              color: highlighted
                                  ? const Color(0xFFE0A458)
                                  : const Color(0xFF0D5C63),
                              size: 30,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                title,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: highlighted
                                      ? Colors.white
                                      : const Color(0xFF17313A),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  color: highlighted
                                      ? Colors.white.withValues(alpha: 0.78)
                                      : const Color(0xFF4B5563),
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.value,
    this.note,
    this.onTap,
  });

  final String title;
  final String value;
  final String? note;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFDCE5E7)),
      ),
      child: SizedBox(
        height: 156,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF17313A),
                      ),
                    ),
                  ),
                  if (onTap != null)
                    const Icon(Icons.chevron_right, color: Color(0xFF5A6B70)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF17313A),
                ),
              ),
              if (note != null && note!.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  note!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF4B5563),
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (onTap == null) {
      return content;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: content,
    );
  }
}

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F1E8),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF17313A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(color: Color(0xFF4B5563), height: 1.55),
            ),
          ],
        ),
      ),
    );
  }
}
