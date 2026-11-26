import 'package:flutter/material.dart';
import '../../core/local_http_server.dart';
import '../theme.dart';

enum KimButtonVariant { primary, secondary, ghost, cyan }

class KimButton extends StatefulWidget {
  final String label;
  final Widget? child;
  final VoidCallback? onPressed;
  final KimButtonVariant variant;
  final EdgeInsetsGeometry padding;
  final double fontSize;
  final String? tooltip;
  final bool hasRedDot;

  const KimButton({
    super.key,
    this.label = '',
    this.child,
    required this.onPressed,
    this.variant = KimButtonVariant.primary,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    this.fontSize = 14,
    this.tooltip,
    this.hasRedDot = false,
  });

  @override
  State<KimButton> createState() => _KimButtonState();
}

class _KimButtonState extends State<KimButton> {
  bool _hovered = false;

  Color _bg() {
    switch (widget.variant) {
      case KimButtonVariant.primary:
        return _hovered ? KimTheme.accentHover : KimTheme.accent;
      case KimButtonVariant.secondary:
        return _hovered ? KimTheme.secondaryBtnHover : KimTheme.secondaryBtn;
      case KimButtonVariant.ghost:
        return _hovered ? KimTheme.ghostBtnHover : KimTheme.ghostBtn;
      case KimButtonVariant.cyan:
        return _hovered ? KimTheme.cyanLight : KimTheme.cyan;
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null;
    final fg = widget.variant == KimButtonVariant.cyan
        ? KimTheme.cyanTextDark
        : Colors.white;
    final btn = MouseRegion(
      cursor:
          disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: disabled ? _bg().withValues(alpha: 0.5) : _bg(),
            borderRadius: BorderRadius.circular(6),
            border: widget.variant == KimButtonVariant.cyan
                ? Border.all(color: KimTheme.cyan)
                : null,
          ),
          child: widget.child ??
              Text(
                widget.label,
                style: TextStyle(
                  color: disabled ? fg.withValues(alpha: 0.6) : fg,
                  fontSize: widget.fontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
        ),
      ),
    );

    final withDot = widget.hasRedDot
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              btn,
              Positioned(
                top: -3,
                right: -3,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF4D4F),
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(color: KimTheme.headerBg, spreadRadius: 2),
                    ],
                  ),
                ),
              ),
            ],
          )
        : btn;

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      return Tooltip(message: widget.tooltip!, child: withDot);
    }
    return withDot;
  }
}

class KimSelectItem<T> {
  final T value;
  final String label;
  final bool enabled;
  final String? tooltip;

  const KimSelectItem({
    required this.value,
    required this.label,
    this.enabled = true,
    this.tooltip,
  });
}

class KimDropdown<T> extends StatelessWidget {
  final T? value;
  final List<KimSelectItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final double? minWidth;
  final double? maxWidth;
  final double fontSize;
  final EdgeInsetsGeometry padding;
  final String? tooltip;
  final String emptyText;
  final VoidCallback? onTapOpen;

  const KimDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.minWidth,
    this.maxWidth,
    this.fontSize = 13,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    this.tooltip,
    this.emptyText = '',
    this.onTapOpen,
  });

  @override
  Widget build(BuildContext context) {
    final currentLabel = items
            .where((e) => e.value == value)
            .firstOrNull
            ?.label ??
        (items.isNotEmpty ? items.first.label : emptyText);

    final box = PopupMenuButton<T>(
      tooltip: '',
      color: KimTheme.cardBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: KimTheme.border),
      ),
      onOpened: onTapOpen,
      onSelected: (v) => onChanged?.call(v),
      itemBuilder: (ctx) {
        return items.map((item) {
          final selected = item.value == value;
          return PopupMenuItem<T>(
            value: item.value,
            enabled: item.enabled,
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? KimTheme.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: !item.enabled
                      ? const Color(0xFF7A8794)
                      : (selected ? Colors.white : const Color(0xFFE6EDF3)),
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        }).toList();
      },
      child: Container(
        constraints: BoxConstraints(
          minWidth: minWidth ?? 0,
          maxWidth: maxWidth ?? double.infinity,
        ),
        padding: padding,
        decoration: BoxDecoration(
          color: KimTheme.cardBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: KimTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                currentLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: KimTheme.text,
                  fontSize: fontSize,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down,
                size: 16, color: KimTheme.textMuted),
          ],
        ),
      ),
    );

    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(message: tooltip!, child: box);
    }
    return box;
  }
}

class PosterImage extends StatefulWidget {
  final String rawUrl;

  const PosterImage({super.key, required this.rawUrl});

  @override
  State<PosterImage> createState() => _PosterImageState();
}

class _PosterImageState extends State<PosterImage> {
  bool _useDirect = false;
  bool _failed = false;

  @override
  void didUpdateWidget(covariant PosterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rawUrl != widget.rawUrl) {
      _useDirect = false;
      _failed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || widget.rawUrl.trim().isEmpty) {
      return Container(color: const Color(0xFF222222));
    }

    final proxy = LocalHttpServer.imageUrl(widget.rawUrl);
    final direct = LocalHttpServer.splitUrlHeaders(widget.rawUrl).url;
    final src = (_useDirect || proxy == null) ? direct : proxy;
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(src)) {
      return Container(color: const Color(0xFF222222));
    }

    return Image.network(
      src,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
      errorBuilder: (_, _, _) {
        if (!_useDirect && proxy != null && direct != proxy) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _useDirect = true);
          });
        } else if (!_failed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _failed = true);
          });
        }
        return Container(color: const Color(0xFF222222));
      },
    );
  }
}

class GlobalToastOverlay extends StatelessWidget {
  final String? text;

  const GlobalToastOverlay({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final visible = text != null && text!.isNotEmpty;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 24),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: visible ? 1.0 : 0.0,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 200),
              offset: visible ? Offset.zero : const Offset(0, -0.3),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 680),
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xF512161C),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.7),
                      blurRadius: 36,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Text(
                  text ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFF0F6FC),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
