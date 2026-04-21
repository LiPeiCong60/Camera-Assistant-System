import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/capture_record.dart';
import '../../models/capture_session_summary.dart';
import '../../services/api_client.dart';
import '../../services/local_image_resolver.dart';
import '../../services/mobile_api_service.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    required this.apiService,
    required this.accessToken,
  });

  final MobileApiService apiService;
  final String accessToken;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<CaptureSessionSummary> _sessions = const <CaptureSessionSummary>[];
  List<CaptureRecord> _captures = const <CaptureRecord>[];
  bool _isLoading = true;
  bool _isBatchPicking = false;
  String? _errorMessage;
  String? _noticeMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _noticeMessage = null;
    });

    try {
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        widget.apiService.getHistorySessions(accessToken: widget.accessToken),
        widget.apiService.getHistoryCaptures(accessToken: widget.accessToken),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _sessions = results[0] as List<CaptureSessionSummary>;
        _captures = results[1] as List<CaptureRecord>;
        _isLoading = false;
      });
    } on ApiException catch (error) {
      final cachedSessions = await widget.apiService.getCachedHistorySessions();
      final cachedCaptures = await widget.apiService.getCachedHistoryCaptures();
      if (!mounted) {
        return;
      }
      if (cachedSessions.isNotEmpty || cachedCaptures.isNotEmpty) {
        setState(() {
          _sessions = cachedSessions;
          _captures = cachedCaptures;
          _noticeMessage = '当前网络不可用，已展示本地缓存历史记录。';
          _isLoading = false;
        });
        return;
      }
      setState(() {
        _errorMessage = error.message;
        _isLoading = false;
      });
    } catch (_) {
      final cachedSessions = await widget.apiService.getCachedHistorySessions();
      final cachedCaptures = await widget.apiService.getCachedHistoryCaptures();
      if (!mounted) {
        return;
      }
      if (cachedSessions.isNotEmpty || cachedCaptures.isNotEmpty) {
        setState(() {
          _sessions = cachedSessions;
          _captures = cachedCaptures;
          _noticeMessage = '历史接口暂时不可用，当前显示本地缓存。';
          _isLoading = false;
        });
        return;
      }
      setState(() {
        _errorMessage = '历史记录加载失败，请稍后重试。';
        _isLoading = false;
      });
    }
  }

  Future<void> _runBatchPickForLatestGroup() async {
    final targetGroup = _findLatestBatchPickGroup();
    if (targetGroup == null) {
      setState(() {
        _errorMessage = '当前没有可用于 AI 选优的一组抓拍，至少需要同一会话下两张图片。';
      });
      return;
    }

    setState(() {
      _isBatchPicking = true;
      _errorMessage = null;
      _noticeMessage = null;
    });

    try {
      final result = await widget.apiService.batchPick(
        accessToken: widget.accessToken,
        sessionId: targetGroup.sessionId,
        captureIds: targetGroup.captureIds,
      );
      if (!mounted) {
        return;
      }

      if (result.task.status != 'succeeded') {
        setState(() {
          _errorMessage =
              result.task.errorMessage ?? 'AI 选优失败，请检查管理端 AI 配置后重试。';
          _isBatchPicking = false;
        });
        return;
      }

      await _loadHistory();
      if (!mounted) {
        return;
      }

      setState(() {
        _noticeMessage =
            'AI 选优完成，会话 #${targetGroup.sessionId} 的最佳图片为 #${result.bestCaptureId ?? '-'}。';
        _isBatchPicking = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
        _isBatchPicking = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'AI 选优失败，请稍后重试。';
        _isBatchPicking = false;
      });
    }
  }

  _BatchPickGroup? _findLatestBatchPickGroup() {
    final grouped = <int, List<CaptureRecord>>{};
    for (final capture in _captures) {
      grouped
          .putIfAbsent(capture.sessionId, () => <CaptureRecord>[])
          .add(capture);
    }
    final candidates = grouped.entries
        .where((entry) => entry.value.length >= 2)
        .map(
          (entry) => _BatchPickGroup(
            sessionId: entry.key,
            captureIds: entry.value
                .map((capture) => capture.id)
                .toList(growable: false),
            latestCreatedAt: entry.value
                .map((capture) => capture.createdAt)
                .reduce((left, right) => left.isAfter(right) ? left : right),
          ),
        )
        .toList(growable: false);
    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort((a, b) => b.latestCreatedAt.compareTo(a.latestCreatedAt));
    return candidates.first;
  }

  Widget _buildSummaryCard(BuildContext context) {
    final selectedCount = _captures.where((capture) => capture.isAiSelected).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: <Widget>[
              Expanded(
                child: _HistoryMetric(
                  label: '拍摄会话',
                  value: '${_sessions.length}',
                ),
              ),
              Expanded(
                child: _HistoryMetric(
                  label: '抓拍记录',
                  value: '${_captures.length}',
                ),
              ),
              Expanded(
                child: _HistoryMetric(
                  label: 'AI 已选',
                  value: '$selectedCount',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('拍摄历史'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const <Widget>[
            Tab(text: '历史会话'),
            Tab(text: '历史抓拍'),
          ],
        ),
      ),
      body: Column(
        children: <Widget>[
          if (_isLoading) const LinearProgressIndicator(minHeight: 3),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: Color(0xFF9E2A2B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          if (_noticeMessage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0x140D5C63),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.cloud_off_outlined,
                        size: 18,
                        color: Color(0xFF0D5C63),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _noticeMessage!,
                          style: const TextStyle(
                            color: Color(0xFF0D5C63),
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (!_isLoading) _buildSummaryCard(context),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: <Widget>[
                RefreshIndicator(
                  onRefresh: _loadHistory,
                  child: _sessions.isEmpty && !_isLoading
                      ? const _HistoryEmptyBlock(
                          title: '暂无历史会话',
                          subtitle: '每次开始正式拍摄后，这里都会沉淀对应的会话记录。',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                          itemCount: _sessions.length,
                          itemBuilder: (context, index) {
                            return _HistorySessionCard(
                              session: _sessions[index],
                            );
                          },
                        ),
                ),
                RefreshIndicator(
                  onRefresh: _loadHistory,
                  child: _captures.isEmpty && !_isLoading
                      ? const _HistoryEmptyBlock(
                          title: '暂无历史抓拍',
                          subtitle: '完成拍照上传后，这里会显示抓拍记录和 AI 选优结果。',
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                          children: <Widget>[
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      'AI 连拍选优',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      '对最近一组同会话抓拍执行 AI 选优，并把最佳图片标记为已选中。',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(height: 1.5),
                                    ),
                                    const SizedBox(height: 12),
                                    FilledButton.icon(
                                      onPressed: _isBatchPicking
                                          ? null
                                          : _runBatchPickForLatestGroup,
                                      icon: _isBatchPicking
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.auto_awesome_outlined,
                                            ),
                                      label: const Text('对最近一组执行 AI 选优'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ..._captures.map(
                              (capture) =>
                                  _HistoryCaptureCard(capture: capture),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BatchPickGroup {
  const _BatchPickGroup({
    required this.sessionId,
    required this.captureIds,
    required this.latestCreatedAt,
  });

  final int sessionId;
  final List<int> captureIds;
  final DateTime latestCreatedAt;
}

class _HistorySessionCard extends StatelessWidget {
  const _HistorySessionCard({required this.session});

  final CaptureSessionSummary session;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('yyyy-MM-dd HH:mm');
    final metadataPlatform = session.metadata['mobile_platform'] as String?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      session.sessionCode,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _StatusBadge(label: session.status),
                ],
              ),
              const SizedBox(height: 12),
              Text('模式：${_modeLabel(session.mode)}'),
              const SizedBox(height: 6),
              Text('开始时间：${formatter.format(session.startedAt.toLocal())}'),
              if (session.endedAt != null) ...<Widget>[
                const SizedBox(height: 6),
                Text('结束时间：${formatter.format(session.endedAt!.toLocal())}'),
              ],
              const SizedBox(height: 6),
              Text(
                '模板：${session.templateId == null ? '未绑定模板' : '模板 #${session.templateId}'}',
              ),
              if (metadataPlatform != null) ...<Widget>[
                const SizedBox(height: 6),
                Text('平台：$metadataPlatform'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _modeLabel(String raw) {
    switch (raw) {
      case 'device_link':
        return '设备联动';
      case 'mobile_only':
        return '手机拍摄';
      default:
        return raw;
    }
  }
}

class _HistoryCaptureCard extends StatelessWidget {
  const _HistoryCaptureCard({required this.capture});

  final CaptureRecord capture;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('yyyy-MM-dd HH:mm');
    final previewSource = LocalImageResolver.resolveCaptureRecordSource(capture);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _HistoryCaptureThumbnail(source: previewSource),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '抓拍 #${capture.id}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (capture.isAiSelected) const _StatusBadge(label: 'AI 已选'),
                ],
              ),
              const SizedBox(height: 12),
              Text('所属会话：#${capture.sessionId} · ${_captureTypeLabel(capture.captureType)}'),
              const SizedBox(height: 6),
              Text('来源：${_storageLabel(capture.storageProvider)}'),
              if (capture.width != null && capture.height != null) ...<Widget>[
                const SizedBox(height: 6),
                Text('尺寸：${capture.width} x ${capture.height}'),
              ],
              if (capture.score != null) ...<Widget>[
                const SizedBox(height: 6),
                Text('评分：${capture.score}'),
              ],
              const SizedBox(height: 6),
              Text('时间：${formatter.format(capture.createdAt.toLocal())}'),
              const SizedBox(height: 8),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: const Text('查看详细信息'),
                  children: <Widget>[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('存储标识：${capture.storageProvider}'),
                            const SizedBox(height: 6),
                            Text('文件地址：${capture.fileUrl}'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _captureTypeLabel(String raw) {
    switch (raw) {
      case 'single':
      case 'photo':
        return '单张拍摄';
      case 'burst':
        return '连拍';
      case 'best':
        return '最佳图';
      case 'background':
        return '背景分析图';
      default:
        return raw;
    }
  }

  String _storageLabel(String raw) {
    switch (raw) {
      case 'local':
      case 'local_static':
        return '后端存储';
      default:
        return raw;
    }
  }
}

class _HistoryCaptureThumbnail extends StatelessWidget {
  const _HistoryCaptureThumbnail({required this.source});

  final ResolvedImageSource? source;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: double.infinity,
        height: 160,
        child: source == null
            ? Container(
                color: const Color(0xFFF1ECE2),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      Icons.photo_outlined,
                      color: Color(0xFF6A6258),
                      size: 30,
                    ),
                    SizedBox(height: 8),
                    Text(
                      '暂无本地缩略预览',
                      style: TextStyle(
                        color: Color(0xFF6A6258),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            : _buildImage(),
      ),
    );
  }

  Widget _buildImage() {
    if (source!.type == ResolvedImageSourceType.file) {
      return Image.file(
        source!.file!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildBrokenImage();
        },
      );
    }

    return Image.network(
      source!.url!,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return _buildBrokenImage();
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) {
          return child;
        }
        return Container(
          color: const Color(0xFFF1ECE2),
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
    );
  }

  Widget _buildBrokenImage() {
    return Container(
      color: const Color(0xFFF1ECE2),
      child: const Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: Color(0xFF6A6258),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x140D5C63),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF0D5C63),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _HistoryMetric extends StatelessWidget {
  const _HistoryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF17313A),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: const Color(0xFF5A6B70)),
        ),
      ],
    );
  }
}

class _HistoryEmptyBlock extends StatelessWidget {
  const _HistoryEmptyBlock({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
