part of '../device_link_page.dart';

class _InputBlock extends StatelessWidget {
  const _InputBlock({
    required this.label,
    required this.hintText,
    required this.controller,
  });

  final String label;
  final String hintText;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hintText,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ],
    );
  }
}

class _ManualMoveHoldButton extends StatelessWidget {
  const _ManualMoveHoldButton({
    required this.enabled,
    required this.onStart,
    required this.onStop,
    required this.icon,
    required this.label,
  });

  final bool enabled;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: enabled ? (_) => onStart() : null,
      onPointerUp: enabled ? (_) => onStop() : null,
      onPointerCancel: enabled ? (_) => onStop() : null,
      child: FilledButton.tonalIcon(
        onPressed: enabled ? () {} : null,
        icon: icon,
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0D5C63) : Colors.white10,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFF0D5C63) : Colors.black12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF17313A),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.value,
    required this.active,
  });

  final String label;
  final String value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final maxPillWidth = math.max(
      140.0,
      math.min(240.0, MediaQuery.sizeOf(context).width - 56),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxPillWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0x140D5C63) : const Color(0xFFF4F1EA),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? const Color(0xFF0D5C63) : const Color(0xFFD3C7B8),
          ),
        ),
        child: Text(
          '$label: $value',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: active ? const Color(0xFF0D5C63) : const Color(0xFF6A6258),
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}

class _PreviewEmptyState extends StatelessWidget {
  const _PreviewEmptyState({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 34, color: const Color(0xFF0D5C63)),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF17313A),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF5A6B70),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _HudEmptyPreview extends StatelessWidget {
  const _HudEmptyPreview({
    this.icon = Icons.videocam_off_outlined,
    this.title = '等待打开设备会话',
    this.description = '会话打开后，这里会显示设备返回的画面。',
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF080D0F),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 42, color: Colors.white.withValues(alpha: 0.72)),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.68),
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

class _HudGlass extends StatelessWidget {
  const _HudGlass({
    required this.child,
    this.compact = false,
    this.tint = const Color(0xA8141D20),
  });

  final Widget child;
  final bool compact;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(compact ? 18 : 24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 16,
          vertical: compact ? 8 : 14,
        ),
        child: child,
      ),
    );
  }
}

class _HudCircleButton extends StatelessWidget {
  const _HudCircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _HudStatusBadge extends StatelessWidget {
  const _HudStatusBadge({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 360) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: active
            ? const Color(0x883BC8A4)
            : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? const Color(0xFF9BE7DD)
              : Colors.white.withValues(alpha: 0.2),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _GestureCountdownBanner extends StatelessWidget {
  const _GestureCountdownBanner({required this.countdown});

  final int countdown;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xCC10181C),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBDF6EF), width: 1.2),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFBDF6EF),
            ),
            child: Text(
              '$countdown',
              style: const TextStyle(
                color: Color(0xFF0D3F43),
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '手势已识别，准备抓拍',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.95),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskCountdownBanner extends StatelessWidget {
  const _TaskCountdownBanner({required this.countdown, required this.message});

  final int countdown;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xCC10181C),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBDF6EF), width: 1.2),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFBDF6EF),
            ),
            child: Text(
              '$countdown',
              style: const TextStyle(
                color: Color(0xFF0D3F43),
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.95),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HudNavButton extends StatelessWidget {
  const _HudNavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0x773BC8A4)
                : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 21,
                color: selected ? const Color(0xFFBDF6EF) : Colors.white,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected
                      ? const Color(0xFFBDF6EF)
                      : Colors.white.withValues(alpha: 0.78),
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HudPanelHeader extends StatelessWidget {
  const _HudPanelHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.68),
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _HudActionChip extends StatelessWidget {
  const _HudActionChip({
    required this.label,
    required this.onTap,
    this.icon,
    this.selected = false,
  });

  final IconData? icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final maxChipWidth = math.max(
      128.0,
      math.min(220.0, MediaQuery.sizeOf(context).width - 56),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxChipWidth),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0x8847D7B4)
                : Colors.white.withValues(alpha: enabled ? 0.13 : 0.06),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? const Color(0xFFBDF6EF)
                  : Colors.white.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(
                  icon,
                  size: 17,
                  color: Colors.white.withValues(alpha: enabled ? 0.94 : 0.42),
                ),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(
                      alpha: enabled ? 0.94 : 0.42,
                    ),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplatePreviewCard extends StatelessWidget {
  const _TemplatePreviewCard({
    required this.name,
    required this.selected,
    required this.onTap,
    this.imageUrl,
    this.meta,
    this.dark = false,
    this.onDelete,
  });

  final String name;
  final String? imageUrl;
  final String? meta;
  final bool selected;
  final bool dark;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final foreground = dark ? Colors.white : const Color(0xFF17313A);
    final muted = dark
        ? Colors.white.withValues(alpha: enabled ? 0.66 : 0.38)
        : const Color(0xFF607178);
    final borderColor = selected
        ? (dark ? const Color(0xFFBDF6EF) : const Color(0xFF0D5C63))
        : (dark
              ? Colors.white.withValues(alpha: 0.18)
              : const Color(0xFFD8E0DE));
    final background = selected
        ? (dark ? const Color(0x3347D7B4) : const Color(0x140D5C63))
        : (dark
              ? Colors.white.withValues(alpha: enabled ? 0.08 : 0.04)
              : Colors.white);
    final url = imageUrl?.trim();

    return Tooltip(
      message: name,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: selected ? 1.4 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Stack(
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: url == null || url.isEmpty
                          ? _TemplatePreviewPlaceholder(dark: dark)
                          : Image.network(
                              url,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              errorBuilder: (context, error, stackTrace) =>
                                  _TemplatePreviewPlaceholder(dark: dark),
                            ),
                    ),
                  ),
                  if (selected)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: dark
                              ? const Color(0xFF0D5C63)
                              : const Color(0xFF0D5C63),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.74),
                          ),
                        ),
                        child: const Icon(
                          Icons.check,
                          size: 15,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  if (onDelete != null)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: _TemplateDeleteButton(
                        dark: dark,
                        onPressed: onDelete!,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground.withValues(alpha: enabled ? 1 : 0.46),
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
              if (meta != null && meta!.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  meta!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateDeleteButton extends StatelessWidget {
  const _TemplateDeleteButton({required this.dark, required this.onPressed});

  final bool dark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '删除模板',
      child: Material(
        color: dark
            ? Colors.black.withValues(alpha: 0.52)
            : Colors.white.withValues(alpha: 0.90),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(
              Icons.delete_outline,
              size: 15,
              color: dark ? Colors.white : const Color(0xFFB42318),
            ),
          ),
        ),
      ),
    );
  }
}

class _TemplatePreviewPlaceholder extends StatelessWidget {
  const _TemplatePreviewPlaceholder({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: dark
          ? Colors.white.withValues(alpha: 0.08)
          : const Color(0xFFE8EFEC),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 26,
          color: dark
              ? Colors.white.withValues(alpha: 0.54)
              : const Color(0xFF6E7C80),
        ),
      ),
    );
  }
}

class _HudJoystick extends StatelessWidget {
  const _HudJoystick({
    required this.size,
    required this.vector,
    required this.enabled,
    required this.onDragHandleUpdate,
    required this.onJoystickUpdate,
    required this.onJoystickEnd,
  });

  final double size;
  final Offset vector;
  final bool enabled;
  final ValueChanged<DragUpdateDetails> onDragHandleUpdate;
  final ValueChanged<Offset> onJoystickUpdate;
  final VoidCallback onJoystickEnd;

  @override
  Widget build(BuildContext context) {
    final knobTravel = size * 0.28;
    final knobSize = size * 0.36;
    final knobOffset = Offset(vector.dx * knobTravel, vector.dy * knobTravel);

    return _HudGlass(
      tint: const Color(0x9810181C),
      child: SizedBox(
        width: size,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: onDragHandleUpdate,
              child: Container(
                width: 54,
                height: 18,
                alignment: Alignment.center,
                child: Container(
                  width: 34,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.46),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: size,
              height: size,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanDown: enabled
                    ? (details) => onJoystickUpdate(details.localPosition)
                    : null,
                onPanUpdate: enabled
                    ? (details) => onJoystickUpdate(details.localPosition)
                    : null,
                onPanEnd: enabled ? (_) => onJoystickEnd() : null,
                onPanCancel: enabled ? onJoystickEnd : null,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Container(
                      width: size * 0.86,
                      height: size * 0.86,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1.5,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.add,
                      color: Colors.white.withValues(alpha: 0.20),
                      size: size * 0.42,
                    ),
                    Transform.translate(
                      offset: knobOffset,
                      child: Container(
                        width: knobSize,
                        height: knobSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: enabled
                              ? const Color(0xDDBDF6EF)
                              : Colors.white.withValues(alpha: 0.16),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.24),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.control_camera_outlined,
                          color: enabled
                              ? const Color(0xFF0D3F43)
                              : Colors.white.withValues(alpha: 0.36),
                          size: knobSize * 0.48,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFF6A6258),
          height: 1.35,
        ),
        children: <InlineSpan>[
          TextSpan(
            text: '$label：',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    required this.title,
    required this.subtitle,
    required this.accentColor,
  });

  final String title;
  final String subtitle;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6A6258),
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
