import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui_mode.dart';

/// Wraps a child so it works with pointer (mouse/touch) *and* D-pad input.
///
/// Focus rules (both burned by shipping the wrong ones):
/// - **Focusable on any Android build** ([dpadFocusEnabled]), never on
///   Windows. Gating focusability on the saved TV mode locked fresh installs
///   out — the device picker shows *before* a mode exists, so nothing was
///   focusable and the remote couldn't even choose "TV".
/// - **Autofocus only where a D-pad is expected** ([dpadAutofocusEnabled]):
///   TV mode or no mode chosen yet. Honouring it on phones lit up the first
///   tile of every grid on its own ("buttons lit that I never clicked").
///
/// The widget is a single focus node (a previous version nested two, so the
/// D-pad focus landed on the node without the key handler and OK did
/// nothing): OK activates on key-up, and holding OK (key repeat) triggers
/// [onLongPress] — the D-pad equivalent of a touch long-press.
///
/// Focus indicator: a pulsing gold/red glow ring, designed to be
/// unmistakable for low-vision users — no reliance on subtle color shifts
/// alone. The element itself never scales (so it can't overlap its
/// neighbours); the ring + animated glow carries all the emphasis.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.borderRadius = 16,
    this.autofocus = false,
    this.focusNode,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double borderRadius;

  /// Only honoured where a D-pad is expected (see [dpadAutofocusEnabled]).
  final bool autofocus;
  final FocusNode? focusNode;

  /// Test hook: forces D-pad (TV) behaviour regardless of the host platform
  /// (widget tests run on the dev machine, where Platform says Windows).
  /// true = TV (focusable + autofocus), false = Windows (no focus at all).
  @visibleForTesting
  static bool? debugDpadOverride;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> with SingleTickerProviderStateMixin {
  bool _hovered = false;
  bool _selectDown = false;
  bool _longPressFired = false;

  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  /// Whether this element takes part in D-pad focus at all.
  static bool get _focusable => TvFocusable.debugDpadOverride ?? dpadFocusEnabled();

  /// Whether autofocus requests are honoured.
  static bool get _autofocusEnabled =>
      TvFocusable.debugDpadOverride ?? dpadAutofocusEnabled();

  /// Hover highlight is a mouse thing, i.e. Windows only.
  static bool get _hoverEnabled => Platform.isWindows;

  static bool _isSelectKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA;
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    // Only act when this very node is focused: when a focusable descendant
    // (e.g. an IconButton inside the tile) has the focus, its own action must
    // win, so let the event bubble up to the app-level shortcuts.
    if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
    if (!_isSelectKey(event.logicalKey)) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      _selectDown = true;
      _longPressFired = false;
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) {
      // Holding OK = long-press (used by "Continua a guardare" tiles on TV).
      if (widget.onLongPress != null && !_longPressFired) {
        _longPressFired = true;
        widget.onLongPress!();
      }
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      final shouldTap = _selectDown && !_longPressFired;
      _selectDown = false;
      _longPressFired = false;
      if (shouldTap) widget.onTap();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      // On Windows this node is invisible to the focus system entirely. On
      // Android it is always focusable (a remote must work even in the wrong
      // mode), but only pre-lights itself where a D-pad is expected.
      autofocus: widget.autofocus && _autofocusEnabled,
      canRequestFocus: _focusable,
      skipTraversal: !_focusable,
      onKeyEvent: _handleKey,
      child: Builder(
        builder: (context) {
          // Focus.of registers a dependency, so this subtree rebuilds when
          // the focus state changes.
          final focused = Focus.of(context).hasPrimaryFocus;

          return MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: _hoverEnabled ? (_) => setState(() => _hovered = true) : null,
            onExit: _hoverEnabled ? (_) => setState(() => _hovered = false) : null,
            child: GestureDetector(
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) {
                  // Breathing glow only while focused: alpha/blur ride the
                  // pulse animation so the ring visibly "lives" instead of
                  // sitting static — this is the main low-vision cue.
                  final t = focused ? _pulse.value : 0.0;
                  final glowAlpha = 0.35 + (t * 0.35); // 0.35 -> 0.70
                  final glowBlur = 14.0 + (t * 10.0); // 14 -> 24
                  final ringWidth = focused ? 4.0 : (_hovered ? 2.0 : 0.0);

                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(widget.borderRadius),
                      border: Border.all(
                        // Focus (remote/keyboard) must be unmistakable; hover
                        // is only a soft hint. Gold ring with a red inner
                        // accent gives a distinct two-tone "you are here"
                        // marker rather than a single flat color.
                        color: focused
                            ? Color.lerp(AppColors.gold, AppColors.redLight, t * 0.4)!
                            : (_hovered ? AppColors.gold.withValues(alpha: 0.5) : Colors.transparent),
                        width: ringWidth,
                      ),
                      boxShadow: focused
                          ? [
                              BoxShadow(
                                color: AppColors.gold.withValues(alpha: glowAlpha),
                                blurRadius: glowBlur,
                                spreadRadius: 1 + t,
                              ),
                              BoxShadow(
                                color: AppColors.red.withValues(alpha: glowAlpha * 0.5),
                                blurRadius: glowBlur * 1.6,
                                spreadRadius: 0,
                              ),
                            ]
                          : null,
                    ),
                    child: child,
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  child: widget.child,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
