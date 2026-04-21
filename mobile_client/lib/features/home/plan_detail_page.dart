import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/capture_record.dart';
import '../../models/plan_summary.dart';
import '../../models/subscription_info.dart';
import '../auth/auth_controller.dart';

enum _PlanActionType { purchase, renew, resetQuota }

class PlanDetailPage extends StatefulWidget {
  const PlanDetailPage({
    super.key,
    required this.controller,
    required this.accessToken,
    this.initialPlanId,
  });

  final AuthController controller;
  final String accessToken;
  final int? initialPlanId;

  @override
  State<PlanDetailPage> createState() => _PlanDetailPageState();
}

class _PlanDetailPageState extends State<PlanDetailPage> {
  late int? _selectedPlanId;
  _PlanActionType? _selectedAction;
  bool _isLoadingUsage = false;
  String? _usageError;
  List<CaptureRecord> _captures = const <CaptureRecord>[];

  @override
  void initState() {
    super.initState();
    _selectedPlanId =
        widget.initialPlanId ??
        widget.controller.subscription?.planId ??
        (widget.controller.plans.isEmpty
            ? null
            : widget.controller.plans.first.id);
    _syncSelectedAction();
    _loadUsage();
  }

  PlanSummary? get _selectedPlan {
    final selectedPlanId = _selectedPlanId;
    if (selectedPlanId == null) {
      return null;
    }
    for (final plan in widget.controller.plans) {
      if (plan.id == selectedPlanId) {
        return plan;
      }
    }
    return null;
  }

  SubscriptionInfo? get _subscription => widget.controller.subscription;

  bool get _isCurrentPlan {
    final selectedPlan = _selectedPlan;
    final subscription = _subscription;
    return selectedPlan != null &&
        subscription != null &&
        subscription.planId == selectedPlan.id;
  }

  Future<void> _loadUsage() async {
    if (_isLoadingUsage) {
      return;
    }
    setState(() {
      _isLoadingUsage = true;
      _usageError = null;
    });
    try {
      final captures = await widget.controller.apiService.getHistoryCaptures(
        accessToken: widget.accessToken,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _captures = captures;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _usageError = '暂时无法更新本周期额度，请稍后重试。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingUsage = false;
        });
      }
    }
  }

  void _syncSelectedAction() {
    _selectedAction = _isCurrentPlan
        ? _PlanActionType.renew
        : _PlanActionType.purchase;
  }

  void _selectPlan(int planId) {
    if (_selectedPlanId == planId) {
      return;
    }
    setState(() {
      _selectedPlanId = planId;
      _syncSelectedAction();
    });
  }

  void _selectAction(_PlanActionType action) {
    setState(() {
      _selectedAction = action;
    });
  }

  int? _cycleCaptureQuota(PlanSummary plan) {
    if (_isCurrentPlan) {
      return _subscription?.captureQuota ?? plan.captureQuota;
    }
    return plan.captureQuota;
  }

  int? _cycleAiQuota(PlanSummary plan) {
    if (_isCurrentPlan) {
      return _subscription?.aiTaskQuota ?? plan.aiTaskQuota;
    }
    return plan.aiTaskQuota;
  }

  int? _usedCaptureCount() {
    final subscription = _subscription;
    if (!_isCurrentPlan || subscription == null) {
      return null;
    }
    return _captures
        .where((capture) => !capture.createdAt.isBefore(subscription.startedAt))
        .length;
  }

  int? _remainingCaptureQuota(PlanSummary plan) {
    final totalQuota = _cycleCaptureQuota(plan);
    final usedCaptureCount = _usedCaptureCount();
    if (totalQuota == null || usedCaptureCount == null) {
      return null;
    }
    return math.max(totalQuota - usedCaptureCount, 0);
  }

  @override
  Widget build(BuildContext context) {
    final selectedPlan = _selectedPlan;
    final plans = widget.controller.plans;

    return Scaffold(
      appBar: AppBar(title: const Text('套餐详情')),
      body: selectedPlan == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('暂无可展示的套餐信息。'),
              ),
            )
          : RefreshIndicator(
              onRefresh: () async {
                await widget.controller.refreshDashboard();
                await _loadUsage();
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: <Widget>[
                  _PlanHeroCard(
                    plan: selectedPlan,
                    subscription: _subscription,
                    isCurrentPlan: _isCurrentPlan,
                  ),
                  const SizedBox(height: 20),
                  if (plans.length > 1) ...<Widget>[
                    Text(
                      '套餐选择',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: plans
                          .map((plan) {
                            final isSelected = plan.id == _selectedPlanId;
                            final isCurrentSubscription =
                                _subscription?.planId == plan.id;
                            return ChoiceChip(
                              label: Text(
                                isCurrentSubscription
                                    ? '${plan.name} · 当前订阅'
                                    : plan.name,
                              ),
                              selected: isSelected,
                              onSelected: (_) => _selectPlan(plan.id),
                            );
                          })
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Text(
                    _isCurrentPlan ? '当前订阅信息' : '套餐内容',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _MetricGrid(
                    children: <Widget>[
                      _MetricCard(
                        label: '计费周期',
                        value: selectedPlan.billingCycleLabel,
                        note: '套餐状态：${_statusLabel(selectedPlan.status)}',
                      ),
                      _MetricCard(
                        label: _isCurrentPlan ? '本周期已拍摄' : '拍摄额度',
                        value: _isCurrentPlan
                            ? _formatQuotaValue(
                                _usedCaptureCount(),
                                fallback: _isLoadingUsage ? '计算中' : '--',
                              )
                            : _formatQuotaValue(
                                _cycleCaptureQuota(selectedPlan),
                              ),
                        note: _isCurrentPlan ? '按当前订阅周期统计' : '单周期可用拍摄次数',
                      ),
                      _MetricCard(
                        label: _isCurrentPlan ? '剩余拍摄额度' : 'AI 额度',
                        value: _isCurrentPlan
                            ? _formatQuotaValue(
                                _remainingCaptureQuota(selectedPlan),
                                fallback: _isLoadingUsage ? '计算中' : '--',
                              )
                            : _formatQuotaValue(_cycleAiQuota(selectedPlan)),
                        note: _isCurrentPlan
                            ? (_isLoadingUsage ? '正在计算中' : '已按当前周期扣减')
                            : '单周期可用 AI 次数',
                      ),
                      _MetricCard(
                        label: _isCurrentPlan ? '到期时间' : '套餐编码',
                        value: _isCurrentPlan
                            ? _formatDate(_subscription?.expiresAt)
                            : selectedPlan.planCode,
                        note: _isCurrentPlan
                            ? '续费方式：${_subscription?.autoRenew == true ? '自动续费' : '手动续费'}'
                            : '可用于购买或切换办理',
                      ),
                    ],
                  ),
                  if (_usageError != null) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(
                      _usageError!,
                      style: const TextStyle(
                        color: Color(0xFF9E2A2B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if ((selectedPlan.description ?? '').trim().isNotEmpty)
                    _InfoPanel(
                      title: '套餐说明',
                      child: Text(
                        selectedPlan.description!.trim(),
                        style: const TextStyle(
                          color: Color(0xFF4B5563),
                          height: 1.6,
                        ),
                      ),
                    ),
                  if ((selectedPlan.description ?? '').trim().isNotEmpty)
                    const SizedBox(height: 16),
                  _InfoPanel(
                    title: '能力范围',
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _buildCapabilityLabels(selectedPlan)
                          .map((label) {
                            return DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F7F5),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Text(
                                  label,
                                  style: const TextStyle(
                                    color: Color(0xFF17313A),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            );
                          })
                          .toList(growable: false),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '办理操作',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ActionGrid(
                    columnCount: _isCurrentPlan ? 2 : 1,
                    children:
                        (_isCurrentPlan
                                ? const <_PlanActionType>[
                                    _PlanActionType.renew,
                                    _PlanActionType.resetQuota,
                                  ]
                                : const <_PlanActionType>[
                                    _PlanActionType.purchase,
                                  ])
                            .map((action) {
                              return _ActionOptionCard(
                                title: _actionTitle(action),
                                subtitle: _actionSubtitle(
                                  action,
                                  selectedPlan.name,
                                ),
                                selected: _selectedAction == action,
                                onTap: () => _selectAction(action),
                              );
                            })
                            .toList(growable: false),
                  ),
                  const SizedBox(height: 12),
                  _SelectionSummaryCard(
                    summary: _selectedAction == null
                        ? '请选择要办理的套餐操作。'
                        : _selectedAction == _PlanActionType.purchase
                        ? '已选中购买 ${selectedPlan.name}，可作为当前账号新的办理套餐。'
                        : _selectedAction == _PlanActionType.renew
                        ? '已选中续费 ${selectedPlan.name}，用于延长当前订阅有效期。'
                        : '已选中重置 ${selectedPlan.name} 的本周期额度，适用于当前订阅套餐。',
                  ),
                ],
              ),
            ),
    );
  }

  List<String> _buildCapabilityLabels(PlanSummary plan) {
    final labels = <String>[
      '套餐编码：${plan.planCode}',
      if (plan.captureQuota == null) '拍摄额度不限' else '拍摄额度 ${plan.captureQuota}',
      if (plan.aiTaskQuota == null) 'AI 额度不限' else 'AI 额度 ${plan.aiTaskQuota}',
    ];
    plan.featureFlags.forEach((key, value) {
      if (value == true) {
        labels.add(_featureFlagLabel(key));
      }
    });
    return labels;
  }

  String _featureFlagLabel(String key) {
    switch (key) {
      case 'background_lock':
        return '背景锁定';
      case 'batch_pick':
        return 'AI 连拍优选';
      default:
        return key.replaceAll('_', ' ');
    }
  }

  String _actionTitle(_PlanActionType action) {
    switch (action) {
      case _PlanActionType.purchase:
        return '购买套餐';
      case _PlanActionType.renew:
        return '续费套餐';
      case _PlanActionType.resetQuota:
        return '重置额度';
    }
  }

  String _actionSubtitle(_PlanActionType action, String planName) {
    switch (action) {
      case _PlanActionType.purchase:
        return '开通 $planName 并纳入当前账号套餐';
      case _PlanActionType.renew:
        return '继续使用 $planName 并延长有效期';
      case _PlanActionType.resetQuota:
        return '恢复 $planName 的当前周期拍摄额度';
    }
  }

  String _formatQuotaValue(int? value, {String fallback = '不限'}) {
    if (value == null) {
      return fallback;
    }
    return '$value 次';
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return '长期有效';
    }
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return '可用';
      case 'inactive':
        return '停用';
      default:
        return status;
    }
  }
}

class _PlanHeroCard extends StatelessWidget {
  const _PlanHeroCard({
    required this.plan,
    required this.subscription,
    required this.isCurrentPlan,
  });

  final PlanSummary plan;
  final SubscriptionInfo? subscription;
  final bool isCurrentPlan;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF17313A), Color(0xFF0D5C63)],
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
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  isCurrentPlan ? '当前订阅' : '可办理套餐',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              plan.name,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              plan.priceLabel,
              style: const TextStyle(
                color: Color(0xFFE0A458),
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isCurrentPlan
                  ? '订阅状态：${subscription?.status == 'active' ? '生效中' : subscription?.status ?? '未开通'}'
                  : '可直接查看套餐内容与办理操作',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = constraints.maxWidth >= 720
            ? 4
            : constraints.maxWidth >= 280
            ? 2
            : 1;
        final totalSpacing = 12.0 * (columnCount - 1);
        final cardWidth = (constraints.maxWidth - totalSpacing) / columnCount;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: children
              .map((child) {
                return SizedBox(width: cardWidth, child: child);
              })
              .toList(growable: false),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.note,
  });

  final String label;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCE5E7)),
      ),
      child: SizedBox(
        height: 112,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF5A6B70),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF17313A),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF4B5563),
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCE5E7)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
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
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({required this.columnCount, required this.children});

  final int columnCount;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final safeColumnCount = constraints.maxWidth >= 280 ? columnCount : 1;
        final totalSpacing = 12.0 * (safeColumnCount - 1);
        final cardWidth =
            (constraints.maxWidth - totalSpacing) / safeColumnCount;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: children
              .map((child) => SizedBox(width: cardWidth, child: child))
              .toList(growable: false),
        );
      },
    );
  }
}

class _ActionOptionCard extends StatelessWidget {
  const _ActionOptionCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF17313A) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? const Color(0xFF17313A)
                  : const Color(0xFFDCE5E7),
            ),
          ),
          child: SizedBox(
            height: 92,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : const Color(0xFF17313A),
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? Colors.white.withValues(alpha: 0.82)
                                : const Color(0xFF4B5563),
                            fontSize: 11.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected ? Colors.white : const Color(0xFF90A4AE),
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

class _SelectionSummaryCard extends StatelessWidget {
  const _SelectionSummaryCard({required this.summary});

  final String summary;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCE5E7)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.task_alt, size: 18, color: Color(0xFF0D5C63)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    '当前选择',
                    style: TextStyle(
                      color: Color(0xFF17313A),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    summary,
                    style: const TextStyle(
                      color: Color(0xFF4B5563),
                      fontSize: 13,
                      height: 1.5,
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
