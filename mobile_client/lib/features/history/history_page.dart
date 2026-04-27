import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/capture_record.dart';
import '../../models/capture_session_summary.dart';
import '../../services/api_client.dart';
import '../../services/gallery_save_service.dart';
import '../../services/local_image_resolver.dart';
import '../../services/mobile_api_service.dart';
import '../../utils/score_formatter.dart';

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
  final Set<int> _savingCaptureIds = <int>{};
  final Set<int> _savedCaptureIds = <int>{};
  final Set<int> _analyzingCaptureIds = <int>{};
  final Set<int> _selectedBatchPickCaptureIds = <int>{};
  final GallerySaveService _gallerySaveService = const GallerySaveService();
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
        _syncBatchPickSelectionWithCaptures();
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
          _syncBatchPickSelectionWithCaptures();
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
          _syncBatchPickSelectionWithCaptures();
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

  void _syncBatchPickSelectionWithCaptures() {
    final availableIds = _captures.map((capture) => capture.id).toSet();
    _selectedBatchPickCaptureIds.removeWhere(
      (captureId) => !availableIds.contains(captureId),
    );
  }

  List<CaptureRecord> _selectedBatchPickCaptures() {
    final selected = _captures
        .where((capture) => _selectedBatchPickCaptureIds.contains(capture.id))
        .toList(growable: false);
    selected.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return selected;
  }

  void _toggleBatchPickCapture(CaptureRecord capture) {
    setState(() {
      _errorMessage = null;
      _noticeMessage = null;
      if (_selectedBatchPickCaptureIds.contains(capture.id)) {
        _selectedBatchPickCaptureIds.remove(capture.id);
        return;
      }
      if (_selectedBatchPickCaptureIds.length >= 9) {
        _errorMessage = 'AI 优选最多选择 9 张照片。';
        return;
      }
      _selectedBatchPickCaptureIds.add(capture.id);
    });
  }

  void _clearBatchPickSelection() {
    setState(() {
      _selectedBatchPickCaptureIds.clear();
      _errorMessage = null;
      _noticeMessage = null;
    });
  }

  Future<void> _runBatchPickForSelectedCaptures() async {
    final selectedCaptures = _selectedBatchPickCaptures();
    if (selectedCaptures.length < 2 || selectedCaptures.length > 9) {
      setState(() {
        _errorMessage = '请选择 2 到 9 张照片后再执行 AI 优选。';
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
        sessionId: selectedCaptures.first.sessionId,
        captureIds: selectedCaptures.map((capture) => capture.id).toList(),
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
        _selectedBatchPickCaptureIds.clear();
        _noticeMessage =
            'AI 优选完成，已从 ${selectedCaptures.length} 张照片中选出 #${result.bestCaptureId ?? '-'}。';
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

  Future<void> _saveCaptureToGallery(CaptureRecord capture) async {
    final source = LocalImageResolver.resolveCaptureRecordSource(capture);
    if (source == null) {
      setState(() {
        _errorMessage = '这张抓拍没有可保存的图片地址。';
      });
      return;
    }

    setState(() {
      _savingCaptureIds.add(capture.id);
      _errorMessage = null;
      _noticeMessage = null;
    });

    try {
      await _gallerySaveService.saveImageSource(
        source: source,
        fileName: _galleryFileName(capture),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _savedCaptureIds.add(capture.id);
        _noticeMessage = '抓拍 #${capture.id} 已保存到手机相册。';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '保存到手机相册失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _savingCaptureIds.remove(capture.id);
        });
      }
    }
  }

  Future<void> _analyzeCapture(CaptureRecord capture) async {
    setState(() {
      _analyzingCaptureIds.add(capture.id);
      _errorMessage = null;
      _noticeMessage = null;
    });

    try {
      final task = capture.captureType == 'background'
          ? await widget.apiService.analyzeBackground(
              accessToken: widget.accessToken,
              sessionId: capture.sessionId,
              captureId: capture.id,
            )
          : await widget.apiService.analyzePhoto(
              accessToken: widget.accessToken,
              sessionId: capture.sessionId,
              captureId: capture.id,
            );
      if (!mounted) {
        return;
      }
      await _loadHistory();
      if (!mounted) {
        return;
      }
      setState(() {
        _noticeMessage = task.status == 'succeeded'
            ? '抓拍 #${capture.id} 已完成 AI 分析。'
            : '抓拍 #${capture.id} 已创建 AI 分析记录，但本次未成功完成。';
        if (task.status != 'succeeded') {
          _errorMessage = task.errorMessage ?? 'AI 分析失败，请检查管理端 AI 配置后重试。';
        }
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
        _errorMessage = 'AI 分析失败，请稍后重试。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _analyzingCaptureIds.remove(capture.id);
        });
      }
    }
  }

  String _galleryFileName(CaptureRecord capture) {
    final extension = _fileExtension(capture.fileUrl) ?? 'jpg';
    return 'cloud_shadow_capture_${capture.id}.$extension';
  }

  String? _fileExtension(String rawPath) {
    final path = Uri.tryParse(rawPath)?.path ?? rawPath;
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == path.length - 1) {
      return null;
    }
    final extension = path.substring(dotIndex + 1).toLowerCase();
    return RegExp(r'^[a-z0-9]{2,5}$').hasMatch(extension) ? extension : null;
  }

  Widget _buildSummaryCard(BuildContext context) {
    final selectedCount = _captures
        .where((capture) => capture.isAiSelected)
        .length;
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
                child: _HistoryMetric(label: 'AI 已选', value: '$selectedCount'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBatchPickCard(BuildContext context) {
    final selectedCount = _selectedBatchPickCaptureIds.length;
    final canRun = selectedCount >= 2 && selectedCount <= 9;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'AI 优选',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _StatusBadge(label: '已选 $selectedCount/9'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '从历史照片中选择 2 到 9 张，AI 会从你选中的照片里挑出最好的一张。',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: _isBatchPicking || !canRun
                      ? null
                      : _runBatchPickForSelectedCaptures,
                  icon: _isBatchPicking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_outlined),
                  label: Text(_isBatchPicking ? '优选中' : '执行 AI 优选'),
                ),
                if (selectedCount > 0)
                  TextButton.icon(
                    onPressed: _isBatchPicking
                        ? null
                        : _clearBatchPickSelection,
                    icon: const Icon(Icons.clear_outlined),
                    label: const Text('清空选择'),
                  ),
              ],
            ),
          ],
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
                            _buildBatchPickCard(context),
                            const SizedBox(height: 12),
                            ..._captures.map(
                              (capture) => _HistoryCaptureCard(
                                capture: capture,
                                selectedForBatchPick:
                                    _selectedBatchPickCaptureIds.contains(
                                      capture.id,
                                    ),
                                isSaving: _savingCaptureIds.contains(
                                  capture.id,
                                ),
                                isSaved: _savedCaptureIds.contains(capture.id),
                                isAnalyzing: _analyzingCaptureIds.contains(
                                  capture.id,
                                ),
                                onSaveToGallery: () =>
                                    _saveCaptureToGallery(capture),
                                onAnalyze: () => _analyzeCapture(capture),
                                onToggleBatchPick: () =>
                                    _toggleBatchPickCapture(capture),
                              ),
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
  const _HistoryCaptureCard({
    required this.capture,
    required this.selectedForBatchPick,
    required this.isSaving,
    required this.isSaved,
    required this.isAnalyzing,
    required this.onSaveToGallery,
    required this.onAnalyze,
    required this.onToggleBatchPick,
  });

  final CaptureRecord capture;
  final bool selectedForBatchPick;
  final bool isSaving;
  final bool isSaved;
  final bool isAnalyzing;
  final VoidCallback onSaveToGallery;
  final VoidCallback onAnalyze;
  final VoidCallback onToggleBatchPick;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('yyyy-MM-dd HH:mm');
    final previewSource = LocalImageResolver.resolveCaptureRecordSource(
      capture,
    );

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
                  if (capture.latestAiTask != null)
                    _StatusBadge(label: _aiTaskBadgeLabel(capture)),
                  if (capture.isAiSelected) ...<Widget>[
                    const SizedBox(width: 6),
                    const _StatusBadge(label: 'AI 已选'),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '所属会话：#${capture.sessionId} · ${_captureTypeLabel(capture.captureType)}',
              ),
              const SizedBox(height: 6),
              Text('来源：${_storageLabel(capture.storageProvider)}'),
              if (capture.width != null && capture.height != null) ...<Widget>[
                const SizedBox(height: 6),
                Text('尺寸：${capture.width} x ${capture.height}'),
              ],
              if (capture.score != null) ...<Widget>[
                const SizedBox(height: 6),
                Text('评分：${ScoreFormatter.formatHundred(capture.score)}'),
              ],
              const SizedBox(height: 6),
              Text('时间：${formatter.format(capture.createdAt.toLocal())}'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: onToggleBatchPick,
                    icon: Icon(
                      selectedForBatchPick
                          ? Icons.check_box_outlined
                          : Icons.check_box_outline_blank_outlined,
                    ),
                    label: Text(selectedForBatchPick ? '已加入优选' : '加入优选'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: isSaving || isSaved ? null : onSaveToGallery,
                    icon: isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            isSaved
                                ? Icons.check_circle_outline
                                : Icons.download_outlined,
                          ),
                    label: Text(isSaved ? '已保存到相册' : '保存到手机相册'),
                  ),
                  if (capture.latestAiTask == null)
                    FilledButton.icon(
                      onPressed: isAnalyzing ? null : onAnalyze,
                      icon: isAnalyzing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome_outlined),
                      label: Text(isAnalyzing ? 'AI 分析中' : 'AI 分析'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
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
                            if (capture.latestAiTask != null) ...<Widget>[
                              const SizedBox(height: 12),
                              _AiReviewBlock(capture: capture),
                            ],
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

  String _aiTaskBadgeLabel(CaptureRecord capture) {
    final status = capture.latestAiTask?.status;
    if (status == 'succeeded') {
      return 'AI 已分析';
    }
    if (status == 'failed') {
      return 'AI 失败';
    }
    return 'AI 处理中';
  }
}

class _AiReviewBlock extends StatelessWidget {
  const _AiReviewBlock({required this.capture});

  final CaptureRecord capture;

  @override
  Widget build(BuildContext context) {
    final task = capture.latestAiTask;
    if (task == null) {
      return const SizedBox.shrink();
    }
    final scoreLabel = ScoreFormatter.formatHundred(task.resultScore);
    final summary = task.resultSummary?.trim();
    final error = task.errorMessage?.trim();
    final suggestions = _readSuggestions(task.responsePayload);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x0F0D5C63),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.auto_awesome_outlined,
                  size: 18,
                  color: Color(0xFF0D5C63),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AI 评价',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (scoreLabel != null) _StatusBadge(label: '评分 $scoreLabel'),
              ],
            ),
            const SizedBox(height: 10),
            if (summary != null && summary.isNotEmpty)
              Text(summary, style: const TextStyle(height: 1.45))
            else if (error != null && error.isNotEmpty)
              Text(
                error,
                style: const TextStyle(
                  height: 1.45,
                  color: Color(0xFF9E2A2B),
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              const Text('AI 暂无文字评价。', style: TextStyle(height: 1.45)),
            if (suggestions.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              for (final suggestion in suggestions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $suggestion'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  List<String> _readSuggestions(Map<String, dynamic> payload) {
    final raw = payload['suggestions'];
    if (raw is! List) {
      return const <String>[];
    }
    return raw
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
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
        child: Icon(Icons.broken_image_outlined, color: Color(0xFF6A6258)),
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
