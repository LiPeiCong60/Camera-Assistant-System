part of '../device_link_page.dart';

extension _DeviceHudPanels on _DeviceLinkPageState {
  Widget _buildHudTextField({
    required String label,
    required String hintText,
    required TextEditingController controller,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      cursorColor: const Color(0xFFBDF6EF),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.68)),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
        isDense: true,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFBDF6EF)),
        ),
      ),
    );
  }

  Widget _buildHudDevicePanel(BuildContext context) {
    final lastFrame = _lastMobilePushFrameAt == null
        ? '-'
        : _formatClock(_lastMobilePushFrameAt!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _HudPanelHeader(
          title: '设置',
          subtitle:
              '设备 ${_status?.deviceStatus ?? _health?.status ?? '未知'} · 手机画面为主预览',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _HudStatusBadge(
              label: '会话 ${_status?.sessionOpened == true ? '已开' : '未开'}',
              active: _status?.sessionOpened == true,
            ),
            _HudStatusBadge(
              label: 'AI 锁 ${_status?.aiLockEnabled == true ? '开' : '关'}',
              active: _status?.aiLockEnabled == true,
            ),
            _HudStatusBadge(
              label: _webRtcSession != null
                  ? 'WebRTC 推流'
                  : 'WebSocket $_mobilePushFrameCount 帧',
              active: _isMobilePushEnabled,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            _HudActionChip(
              icon: Icons.manage_search_outlined,
              label: '详细设置',
              onTap: () => unawaited(_openDetailedSettingsFromDeviceLink()),
            ),
            _HudActionChip(
              icon: Icons.health_and_safety_outlined,
              label: '健康',
              onTap: _isBusy ? null : _checkHealth,
            ),
            _HudActionChip(
              icon: Icons.radar_outlined,
              label: '刷新',
              onTap: _isBusy ? null : _fetchStatus,
            ),
            _HudActionChip(
              icon: Icons.camera_alt_outlined,
              label: '返回拍摄',
              onTap: _returnToCameraPage,
            ),
            _HudActionChip(
              icon: _isMobilePushEnabled
                  ? Icons.videocam_outlined
                  : Icons.mobile_screen_share_outlined,
              label: _isMobilePushEnabled ? '停止推流' : '手机推流',
              onTap: _isBusy || _isStartingMobilePush
                  ? null
                  : () {
                      if (_isMobilePushEnabled) {
                        unawaited(_stopMobilePush());
                      } else {
                        unawaited(_startMobilePush());
                      }
                    },
            ),
            _HudActionChip(
              icon: Icons.cameraswitch_outlined,
              label: _mobilePushSwitchTargetLabel(),
              onTap:
                  _isBusy ||
                      _isStartingMobilePush ||
                      _isHandlingMobilePushOrientationChange ||
                      _isDeviceLinkRecordingVideo ||
                      _isFinalizingDeviceLinkVideo
                  ? null
                  : () => unawaited(_switchMobilePushCamera()),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildHudSettingsExpansion(
          context,
          title: '画面辅助',
          subtitle: '人体框、骨架线、模板框和锁定位框。',
          child: _buildHudOverlayOptions(context, showTitle: false),
        ),
        const SizedBox(height: 12),
        _buildHudSettingsExpansion(
          context,
          title: '手势抓拍',
          subtitle: '张手握拳、OK 手势和抓拍后 AI 分析。',
          child: _buildHudGestureOptions(context),
        ),
        const SizedBox(height: 12),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            initiallyExpanded: false,
            title: Text(
              '连接与高级',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: Text(
              '地址、会话码、诊断和横屏习惯收在这里。',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.62)),
            ),
            children: <Widget>[
              const SizedBox(height: 8),
              _buildHudTextField(
                label: '树莓派 API 地址',
                hintText: 'http://192.168.1.100:8001',
                controller: _baseUrlController,
              ),
              const SizedBox(height: 10),
              _buildHudTextField(
                label: '视频流地址',
                hintText: 'mobile_push / rtsp://...',
                controller: _streamUrlController,
              ),
              const SizedBox(height: 10),
              _buildHudTextField(
                label: '会话码',
                hintText: 'MOBILE_20260425_011000',
                controller: _sessionCodeController,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    _HudActionChip(
                      icon: Icons.fact_check_outlined,
                      label: '诊断',
                      onTap: _isBusy ? null : _runConnectionDiagnostics,
                    ),
                    _HudActionChip(
                      icon: Icons.video_settings_outlined,
                      label: '设备预览源',
                      onTap: _isBusy ? null : _restartDeviceStream,
                    ),
                    _HudActionChip(
                      icon: Icons.swap_horiz_outlined,
                      label: _landscapeControlsOnLeft ? '横屏左手' : '横屏右手',
                      onTap: () =>
                          _setLandscapeControlsSide(!_landscapeControlsOnLeft),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_diagnosticMessage != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            _diagnosticMessage!,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              height: 1.35,
            ),
          ),
        ],
        if (_recentConnections.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            '最近连接',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _recentConnections
                .map(
                  (preset) => _HudActionChip(
                    icon: Icons.history_outlined,
                    label: preset.baseUrl,
                    onTap: _isBusy
                        ? null
                        : () => _applyConnectionPreset(preset),
                  ),
                )
                .toList(growable: false),
          ),
        ],
        if (_mobilePushErrorMessage != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            _mobilePushErrorMessage!,
            style: const TextStyle(
              color: Color(0xFFFFB7A8),
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ] else if (_isMobilePushEnabled) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            '最近推流帧：$lastFrame',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
          ),
        ],
      ],
    );
  }

  Widget _buildHudSettingsExpansion(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        initiallyExpanded: false,
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.62)),
        ),
        children: <Widget>[const SizedBox(height: 8), child],
      ),
    );
  }

  Widget _buildHudOverlayOptions(
    BuildContext context, {
    bool showTitle = true,
  }) {
    final overlay =
        _status?.overlayStatus ?? const DeviceOverlayStatusSummary();
    final canUpdate = _status?.sessionOpened == true && !_isBusy;

    Widget option({
      required IconData icon,
      required String label,
      required String key,
      required bool selected,
    }) {
      return _HudActionChip(
        icon: icon,
        label: label,
        selected: selected,
        onTap: canUpdate ? () => _setOverlayOption(key, !selected) : null,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (showTitle) ...<Widget>[
          Text(
            '画面辅助',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            option(
              icon: Icons.layers_outlined,
              label: '总开关',
              key: 'enabled',
              selected: overlay.enabled,
            ),
            option(
              icon: Icons.accessibility_new_outlined,
              label: '人体框',
              key: 'show_live_person_bbox',
              selected: overlay.showLivePersonBbox,
            ),
            option(
              icon: Icons.account_tree_outlined,
              label: '人体骨骼',
              key: 'show_live_body_skeleton',
              selected: overlay.showLiveBodySkeleton,
            ),
            option(
              icon: Icons.back_hand_outlined,
              label: '手部骨骼',
              key: 'show_live_hands',
              selected: overlay.showLiveHands,
            ),
            option(
              icon: Icons.crop_free_outlined,
              label: '模板框',
              key: 'show_template_bbox',
              selected: overlay.showTemplateBbox,
            ),
            option(
              icon: Icons.schema_outlined,
              label: '模板骨骼',
              key: 'show_template_skeleton',
              selected: overlay.showTemplateSkeleton,
            ),
            option(
              icon: Icons.center_focus_weak_outlined,
              label: '锁定位框',
              key: 'show_ai_lock_box',
              selected: overlay.showAiLockBox,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          canUpdate ? '这些开关会直接影响树莓派返回的预览叠加。' : '打开设备会话后可以调整画面辅助显示。',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.62),
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}
