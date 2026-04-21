import 'package:flutter/material.dart';

import '../../models/plan_summary.dart';
import '../auth/auth_controller.dart';
import '../camera/camera_capture_page.dart';
import '../device_link/device_link_page.dart';
import '../history/history_page.dart';

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
                          profile?.displayName ??
                              session?.user.displayName ??
                              '未命名用户',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '从这里开始拍摄、查看历史记录或进入设备联动。当前账号的套餐、订阅与 AI 能力会自动同步到移动端。',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.88),
                                height: 1.5,
                              ),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: <Widget>[
                            _InfoChip(
                              label: '用户编码',
                              value:
                                  profile?.userCode ??
                                  (session == null
                                      ? '-'
                                      : 'USER_${session.user.id}'),
                            ),
                            _InfoChip(
                              label: '角色',
                              value: profile?.role ?? session?.user.role ?? '-',
                            ),
                            _InfoChip(
                              label: '状态',
                              value:
                                  profile?.status ??
                                  session?.user.status ??
                                  '-',
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: session == null
                              ? null
                              : () async {
                                  await Navigator.of(context).push<void>(
                                    MaterialPageRoute<void>(
                                      builder: (_) => CameraCapturePage(
                                        apiService: controller.apiService,
                                        accessToken: session.accessToken,
                                      ),
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('开始拍摄'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFE0A458),
                            foregroundColor: const Color(0xFF17313A),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: session == null
                              ? null
                              : () async {
                                  await Navigator.of(context).push<void>(
                                    MaterialPageRoute<void>(
                                      builder: (_) => HistoryPage(
                                        apiService: controller.apiService,
                                        accessToken: session.accessToken,
                                      ),
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.history_outlined),
                          label: const Text('查看历史记录'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: session == null
                              ? null
                              : () async {
                                  await Navigator.of(context).push<void>(
                                    MaterialPageRoute<void>(
                                      builder: (_) => DeviceLinkPage(
                                        mobileApiService: controller.apiService,
                                        accessToken: session.accessToken,
                                      ),
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.router_outlined),
                          label: const Text('进入设备联动'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
                  children: <Widget>[
                    Expanded(
                      child: _StatusCard(
                        title: '当前订阅',
                        value: controller.subscription?.status ?? '未开通',
                        note: controller.subscription == null
                            ? '当前账号还没有激活中的套餐订阅'
                            : 'plan_id: ${controller.subscription!.planId}',
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _StatusCard(
                        title: '服务连接',
                        value: controller.isRefreshing ? '同步中' : '已接通',
                        note: '账号、套餐与订阅数据已同步',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const _FeatureCallout(
                  icon: Icons.photo_camera_back_outlined,
                  title: '拍摄主链已经就绪',
                  subtitle:
                      '支持打开摄像头、切换前后摄、拍照、上传分析，并查看最近一次拍摄回显结果。',
                ),
                const SizedBox(height: 20),
                Text(
                  '套餐预览',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (controller.plans.isEmpty)
                  const _EmptyBlock(
                    title: '暂无套餐数据',
                    subtitle: '确认 backend 中已有计划数据，或者点击右上角刷新。',
                  )
                else
                  ...controller.plans.map(_buildPlanCard),
                const SizedBox(height: 20),
                Text(
                  '常用入口',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const _EmptyBlock(
                  title: '历史记录与设备联动',
                  subtitle:
                      '建议先从拍摄页完成一次上传分析，再进入历史记录和设备联动页查看结果与设备状态。',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlanCard(PlanSummary plan) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 18,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                plan.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF17313A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                plan.priceLabel,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2C6E49),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '套餐编码：${plan.planCode}  ·  状态：${plan.status}',
                style: const TextStyle(color: Color(0xFF4B5563), height: 1.5),
              ),
            ],
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          '$label：$value',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.value,
    required this.note,
  });

  final String title;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFDCE5E7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF17313A),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Color(0xFF17313A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              note,
              style: const TextStyle(color: Color(0xFF4B5563), height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureCallout extends StatelessWidget {
  const _FeatureCallout({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFDCE5E7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2F4),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Icon(icon, color: const Color(0xFF0D5C63), size: 28),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
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
                    style: const TextStyle(
                      color: Color(0xFF4B5563),
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
