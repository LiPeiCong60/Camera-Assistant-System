import 'package:flutter/material.dart';

import '../../models/auth_session.dart';
import '../../models/plan_summary.dart';
import '../../models/subscription_info.dart';
import '../auth/auth_controller.dart';
import '../camera/camera_capture_page.dart';
import '../device_link/device_link_page.dart';
import '../history/history_page.dart';
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
            title: const Text('Camera Assistant'),
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
                        note: currentPlan == null
                            ? '点击查看套餐详情'
                            : '${currentPlan.name} · 点击查看详情',
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
                        title: '服务连接',
                        value: controller.isRefreshing ? '同步中' : '已接通',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _PlanSection(
                  plans: controller.plans,
                  subscription: controller.subscription,
                  onPlanTap: session == null
                      ? null
                      : (plan) => _openPlanDetails(
                          context,
                          controller: controller,
                          accessToken: session.accessToken,
                          initialPlanId: plan.id,
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
                title: '进入设备联动',
                subtitle: '连接设备并执行控制',
                icon: Icons.router_outlined,
                compact: true,
                onTap: session == null
                    ? null
                    : () async {
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => DeviceLinkPage(
                              mobileApiService: controller.apiService,
                              accessToken: session!.accessToken,
                            ),
                          ),
                        );
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
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 18,
                offset: Offset(0, 10),
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

class _PlanSection extends StatelessWidget {
  const _PlanSection({
    required this.plans,
    required this.subscription,
    this.onPlanTap,
  });

  final List<PlanSummary> plans;
  final SubscriptionInfo? subscription;
  final ValueChanged<PlanSummary>? onPlanTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDCE5E7)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          title: Text(
            '可用套餐',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            plans.isEmpty
                ? '暂无套餐数据'
                : subscription == null
                ? '共 ${plans.length} 个套餐'
                : '已开通 1 个套餐，可切换查看其余套餐',
            style: const TextStyle(color: Color(0xFF5A6B70)),
          ),
          children: <Widget>[
            if (plans.isEmpty)
              const _EmptyBlock(
                title: '暂无套餐数据',
                subtitle: '确认 backend 中已有计划数据，或者点击右上角刷新。',
              )
            else
              ...plans.map(_buildPlanCard),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(PlanSummary plan) {
    final isCurrentPlan = subscription?.planId == plan.id;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPlanTap == null ? null : () => onPlanTap!(plan),
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAF8),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          plan.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF17313A),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: isCurrentPlan
                              ? const Color(0xFF17313A)
                              : const Color(0xFFE7F1EC),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          child: Text(
                            isCurrentPlan ? '当前订阅' : '可购买',
                            style: TextStyle(
                              color: isCurrentPlan
                                  ? Colors.white
                                  : const Color(0xFF2C6E49),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    plan.priceLabel,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2C6E49),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '套餐编码：${plan.planCode}  ·  状态：${plan.status}',
                    style: const TextStyle(
                      color: Color(0xFF4B5563),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          isCurrentPlan ? '点击查看续费与额度信息' : '点击查看套餐详情与购买信息',
                          style: const TextStyle(
                            color: Color(0xFF5A6B70),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right, color: Color(0xFF5A6B70)),
                    ],
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
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
                        const Icon(
                          Icons.chevron_right,
                          color: Color(0xFF5A6B70),
                        ),
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
        ),
      ),
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
