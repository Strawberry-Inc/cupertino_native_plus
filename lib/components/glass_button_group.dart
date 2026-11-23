import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import '../utils/version_detector.dart';
import '../utils/icon_renderer.dart';
import '../utils/theme_helper.dart';
import '../channel/params.dart';
import '../channel/view_types.dart';
import '../style/button_data.dart';
import '../style/button_theme.dart';
import '../style/sf_symbol.dart';
import '../utils/platform_view_builder.dart';
import '../style/image_placement.dart';
import 'button.dart';

/// A group of buttons that can be rendered together for proper Liquid Glass blending effects.
///
/// This widget renders all buttons in a single SwiftUI view, allowing them
/// to properly blend together when using glassEffectUnionId.
///
/// On iOS 26+ and macOS 26+, this uses native SwiftUI rendering for proper
/// Liquid Glass effects. For older versions, it falls back to Flutter widgets.
///
/// **Breaking Change in v1.1.0**: This widget now accepts [CNButtonData] models
/// instead of [CNButton] widgets. Use the [CNGlassButtonGroup.fromWidgets]
/// constructor for backward compatibility.
///
/// Example:
/// ```dart
/// CNGlassButtonGroup(
///   buttons: [
///     CNButtonData.icon(
///       icon: CNIcon.symbol('house'),
///       onPressed: () => print('Home'),
///     ),
///     CNButtonData.icon(
///       icon: CNIcon.symbol('gear'),
///       onPressed: () => print('Settings'),
///     ),
///     CNButtonData(
///       label: 'More',
///       icon: CNIcon.symbol('ellipsis'),
///       onPressed: () => print('More'),
///     ),
///   ],
///   axis: Axis.horizontal,
///   spacing: 8.0,
/// )
/// ```
class CNGlassButtonGroup extends StatefulWidget {
  /// Creates a group of glass buttons using data models.
  ///
  /// The [buttons] list contains button data models.
  /// The [axis] determines whether buttons are laid out horizontally (Axis.horizontal)
  /// or vertically (Axis.vertical).
  /// The [spacing] controls the spacing between buttons in the layout (HStack/VStack).
  /// The [spacingForGlass] controls how Liquid Glass effects blend together.
  /// For proper blending, [spacingForGlass] should be larger than [spacing] so that
  /// glass effects merge when buttons are close together.
  const CNGlassButtonGroup({
    super.key,
    required this.buttons,
    this.axis = Axis.horizontal,
    this.spacing = 8.0,
    this.spacingForGlass = 40.0,
    this.iconChangeDuration,
  }) : _buttonWidgets = null;

  /// Creates a group from existing CNButton widgets.
  ///
  /// This constructor provides backward compatibility with the pre-1.1.0 API.
  /// Prefer using the default constructor with [CNButtonData] for new code.
  ///
  /// @Deprecated('Use the default constructor with CNButtonData instead')
  const CNGlassButtonGroup.fromWidgets({
    super.key,
    required List<CNButton> buttonWidgets,
    this.axis = Axis.horizontal,
    this.spacing = 8.0,
    this.spacingForGlass = 40.0,
    this.iconChangeDuration,
  }) : buttons = const [],
       _buttonWidgets = buttonWidgets;

  /// List of button data models.
  final List<CNButtonData> buttons;

  /// Internal: List of button widgets (for backward compatibility).
  final List<CNButton>? _buttonWidgets;

  /// Layout axis for buttons.
  final Axis axis;

  /// Spacing between buttons.
  final double spacing;

  /// Spacing value for Liquid Glass blending (affects how glass effects merge).
  final double spacingForGlass;

  /// When set (iOS 26+), a later update that changes a button's icon keeps the
  /// button and cross-fades the icon over this duration.
  final Duration? iconChangeDuration;

  /// Returns the effective button count (from data or widgets).
  int get _effectiveButtonCount =>
      _buttonWidgets != null ? _buttonWidgets.length : buttons.length;

  @override
  State<CNGlassButtonGroup> createState() => _CNGlassButtonGroupState();
}

class _CNGlassButtonGroupState extends State<CNGlassButtonGroup> {
  final _viewKey = UniqueKey();
  MethodChannel? _channel;
  List<_ButtonSnapshot>? _lastButtonSnapshots;
  Axis? _lastAxis;
  double? _lastSpacing;
  double? _lastSpacingForGlass;
  bool? _lastIsDark;

  /// Cached future for FutureBuilder – rebuilt only when buttons change.
  Future<_ButtonsParams>? _creationParamsFuture;

  /// What the current native view is created with. A platform view only takes
  /// the params of the build that creates it, so changes made before
  /// [_onCreated] are sent from there. Set by [_onPlatformViewMounted].
  ({List<_ButtonSnapshot> snapshots, bool isDark})? _createdWith;

  /// Whether button changes are being sent, and whether the buttons changed
  /// again meanwhile. One send runs at a time, so each is compared against
  /// what the previous one sent.
  bool _syncingButtons = false;
  bool _buttonsChangedWhileSyncing = false;

  /// Whether we're using widget mode (backward compatibility).
  bool get _usingWidgets => widget._buttonWidgets != null;

  bool get _isDark => ThemeHelper.isDark(context);

  List<_ButtonSnapshot> _currentSnapshots() => _usingWidgets
      ? widget._buttonWidgets!
            .map((b) => _ButtonSnapshot.fromButtonWidget(b))
            .toList()
      : widget.buttons.map((b) => _ButtonSnapshot.fromButtonData(b)).toList();

  /// (Re)builds and caches the creation-params future.
  void _rebuildCreationParamsFuture(BuildContext context) {
    final snapshots = _currentSnapshots();
    final buttons = _usingWidgets
        ? Future.wait(
            widget._buttonWidgets!.map(
              (button) => _buttonWidgetToMapAsync(button, context),
            ),
          )
        : Future.wait(
            widget.buttons.map(
              (button) => _buttonDataToMapAsync(button, context),
            ),
          );
    _creationParamsFuture = buttons.then(
      (buttons) => _ButtonsParams(snapshots: snapshots, buttons: buttons),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Build the future on first mount only (initState has no context).
    if (_creationParamsFuture == null) {
      _rebuildCreationParamsFuture(context);
    }
    _syncBrightnessIfNeeded();
  }

  @override
  void didUpdateWidget(covariant CNGlassButtonGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBrightnessIfNeeded();

    // Invalidate the cached future only when the button list actually changed.
    final currentSnapshots = _currentSnapshots();

    final previousSnapshots = _usingWidgets
        ? oldWidget._buttonWidgets!
              .map((b) => _ButtonSnapshot.fromButtonWidget(b))
              .toList()
        : oldWidget.buttons
              .map((b) => _ButtonSnapshot.fromButtonData(b))
              .toList();

    final buttonsChanged =
        previousSnapshots.length != currentSnapshots.length ||
        !_snapshotsEqual(previousSnapshots, currentSnapshots);

    if (buttonsChanged) {
      _rebuildCreationParamsFuture(context);
    }

    _syncButtonsToNativeIfNeeded();
  }

  @override
  void dispose() {
    _detachChannel();
    super.dispose();
  }

  /// Stops listening to the current native view. Otherwise its channel keeps
  /// calling into this state, and holding on to its buttons, after the view
  /// is gone.
  void _detachChannel() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
  }

  /// A platform view is being created with these params. The group gets a new
  /// one whenever its place in the tree changes (e.g. the axis changes), so
  /// forget the previous view and compare against this one from now on.
  void _onPlatformViewMounted(List<_ButtonSnapshot> snapshots, bool isDark) {
    _detachChannel();
    _createdWith = (snapshots: snapshots, isDark: isDark);
    _lastButtonSnapshots = null;
    _lastIsDark = null;
  }

  Future<void> _syncBrightnessIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;
    final isDark = _isDark;
    if (_lastIsDark != isDark) {
      // Record before sending, so a change made while this is in flight is
      // compared against what was sent.
      _lastIsDark = isDark;
      try {
        await ch.invokeMethod('setBrightness', {'isDark': isDark});
      } catch (_) {
        if (_channel == ch && _lastIsDark == isDark) _lastIsDark = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIOSOrMacOS =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    final shouldUseNative =
        isIOSOrMacOS && PlatformVersion.shouldUseNativeGlass;

    if (!shouldUseNative) {
      return _buildFlutterFallback(context);
    }

    return _buildNativeGroup(context);
  }

  Widget _buildNativeGroup(BuildContext context) {
    const viewType = ViewTypes.cupertinoNativeGlassButtonGroup;

    return FutureBuilder<_ButtonsParams>(
      future: _creationParamsFuture,
      builder: (context, snapshot) {
        final params = snapshot.data;
        if (params == null) {
          return const SizedBox.shrink();
        }

        final isDark = ThemeHelper.isDark(context);
        final creationParams = <String, dynamic>{
          'buttons': params.buttons,
          'axis': widget.axis == Axis.horizontal ? 'horizontal' : 'vertical',
          'spacing': widget.spacing,
          'spacingForGlass': widget.spacingForGlass,
          'isDark': isDark,
          if (widget.iconChangeDuration != null)
            'iconChangeDuration': widget.iconChangeDuration!.inMilliseconds,
        };

        final platformView = _PlatformViewMount(
          onMount: () => _onPlatformViewMounted(params.snapshots, isDark),
          child: buildCupertinoPlatformView(
            context,
            key: _viewKey,
            viewType: viewType,
            creationParams: creationParams,
            onPlatformViewCreated: _onCreated,
          ),
        );

        if (widget.axis == Axis.horizontal) {
          final buttonHeight = _getEffectiveMinHeight();
          return LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.hasBoundedWidth) {
                return ClipRect(
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: buttonHeight,
                    child: platformView,
                  ),
                );
              } else {
                final estimatedWidth =
                    widget._effectiveButtonCount * 44.0 +
                    ((widget._effectiveButtonCount - 1) * widget.spacing);
                return ClipRect(
                  child: SizedBox(
                    width: estimatedWidth,
                    height: buttonHeight,
                    child: platformView,
                  ),
                );
              }
            },
          );
        } else {
          final buttonHeight = _getEffectiveMinHeight();
          final estimatedHeight =
              (widget._effectiveButtonCount * buttonHeight) +
              ((widget._effectiveButtonCount - 1) * widget.spacing);
          return ClipRect(
            child: LimitedBox(
              maxHeight: estimatedHeight.clamp(44.0, 400.0),
              child: SizedBox(width: double.infinity, child: platformView),
            ),
          );
        }
      },
    );
  }

  double _getEffectiveMinHeight() {
    if (_usingWidgets && widget._buttonWidgets!.isNotEmpty) {
      return widget._buttonWidgets!.first.config.minHeight ?? 44.0;
    } else if (widget.buttons.isNotEmpty) {
      return widget.buttons.first.config.minHeight ?? 44.0;
    }
    return 44.0;
  }

  void _onCreated(int id) {
    final channel = ViewTypes.methodChannelFor(
      ViewTypes.cupertinoNativeGlassButtonGroup,
      id,
    );
    _detachChannel();
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'buttonPressed') {
        final index = call.arguments['index'] as int?;
        if (index != null && index >= 0) {
          if (_usingWidgets && index < widget._buttonWidgets!.length) {
            widget._buttonWidgets![index].onPressed?.call();
          } else if (!_usingWidgets && index < widget.buttons.length) {
            widget.buttons[index].onPressed?.call();
          }
        }
      }
    });

    // Compare later changes against what the view was created with: changes
    // made while it was being created haven't reached it yet.
    _lastButtonSnapshots = _createdWith?.snapshots;
    _lastIsDark = _createdWith?.isDark;
    _lastAxis = widget.axis;
    _lastSpacing = widget.spacing;
    _lastSpacingForGlass = widget.spacingForGlass;
    _syncBrightnessIfNeeded();
    _syncButtonsToNativeIfNeeded();
  }

  Future<void> _syncButtonsToNativeIfNeeded() async {
    if (_channel == null) return;
    if (_syncingButtons) {
      _buttonsChangedWhileSyncing = true;
      return;
    }
    _syncingButtons = true;
    try {
      do {
        _buttonsChangedWhileSyncing = false;
        await _sendButtonChanges();
      } while (_buttonsChangedWhileSyncing && mounted);
    } finally {
      _syncingButtons = false;
    }
  }

  Future<void> _sendButtonChanges() async {
    final ch = _channel;
    if (ch == null || !mounted) return;

    // Stick to the buttons of this moment: the widget may change while this
    // awaits, and the next round sends those changes.
    final buttonWidgets = widget._buttonWidgets;
    final buttons = widget.buttons;
    final currentSnapshots = _currentSnapshots();
    final lastSnapshots = _lastButtonSnapshots;

    final buttonsChanged =
        lastSnapshots == null ||
        lastSnapshots.length != currentSnapshots.length ||
        !_snapshotsEqual(lastSnapshots, currentSnapshots);

    final axisChanged = _lastAxis != widget.axis;
    final spacingChanged = _lastSpacing != widget.spacing;
    final spacingForGlassChanged =
        _lastSpacingForGlass != widget.spacingForGlass;

    if (buttonsChanged) {
      try {
        if (lastSnapshots == null ||
            lastSnapshots.length != currentSnapshots.length) {
          final buttonsData = buttonWidgets != null
              ? await Future.wait(
                  buttonWidgets.map(
                    (button) => _buttonWidgetToMapAsync(button, context),
                  ),
                )
              : await Future.wait(
                  buttons.map(
                    (button) => _buttonDataToMapAsync(button, context),
                  ),
                );
          if (!mounted || _channel != ch) return;
          await ch.invokeMethod('updateButtons', {'buttons': buttonsData});
        } else {
          for (int i = 0; i < currentSnapshots.length; i++) {
            if (lastSnapshots[i].equals(currentSnapshots[i])) continue;
            if (!mounted || _channel != ch) return;
            final buttonData = buttonWidgets != null
                ? await _buttonWidgetToMapAsync(buttonWidgets[i], context)
                : await _buttonDataToMapAsync(buttons[i], context);
            if (!mounted || _channel != ch) return;
            await ch.invokeMethod('updateButton', {
              'index': i,
              'button': buttonData,
            });
          }
        }
      } on PlatformException {
        // Leave the snapshots as they were, so the next change resends.
        return;
      } on MissingPluginException {
        return;
      }
      // A view created meanwhile has its own snapshots.
      if (_channel != ch) return;
      _lastButtonSnapshots = currentSnapshots;
    }

    if (axisChanged || spacingChanged || spacingForGlassChanged) {
      _lastAxis = widget.axis;
      _lastSpacing = widget.spacing;
      _lastSpacingForGlass = widget.spacingForGlass;
    }
  }

  bool _snapshotsEqual(List<_ButtonSnapshot> a, List<_ButtonSnapshot> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (!a[i].equals(b[i])) return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Serialization helpers
  // ---------------------------------------------------------------------------

  /// Builds the native dict for a [CNButtonData].
  Future<Map<String, dynamic>> _buttonDataToMapAsync(
    CNButtonData button,
    BuildContext context,
  ) async {
    // Resolve context-derived values before the async gap.
    final themeMap = _themeToMap(button.theme, context);
    final iconMap = await _resolveIconMap(button.icon, context);
    return _buildButtonMap(
      label: button.label,
      iconMap: iconMap,
      enabled: button.enabled,
      theme: button.theme,
      themeMap: themeMap,
      config: button.config,
    );
  }

  /// Builds the native dict for a legacy [CNButton] widget.
  Future<Map<String, dynamic>> _buttonWidgetToMapAsync(
    CNButton button,
    BuildContext context,
  ) async {
    final iconMap = await _resolveIconMap(button.icon, context);
    final tintArgb = button.tint != null
        // ignore: use_build_context_synchronously
        ? resolveColorToArgb(button.tint, context)
        : null;
    return {
      if (button.label != null) 'label': button.label,
      ...iconMap,
      'enabled': button.enabled,
      if (tintArgb != null) 'tint': tintArgb,
      'minHeight': button.config.minHeight ?? 44.0,
      'style': button.config.style.name,
      if (button.config.glassEffectUnionId != null)
        'glassEffectUnionId': button.config.glassEffectUnionId,
      if (button.config.glassEffectId != null)
        'glassEffectId': button.config.glassEffectId,
      'glassEffectInteractive': button.config.glassEffectInteractive,
      if (button.config.borderRadius != null)
        'borderRadius': button.config.borderRadius,
      if (button.config.padding != null) ..._paddingMap(button.config.padding!),
      if (button.config.minHeight != null) 'minHeight': button.config.minHeight,
      if (button.config.imagePadding != null)
        'imagePadding': button.config.imagePadding,
      'glassMaterial': button.theme.glassMaterial.name,
    };
  }

  /// Resolves [CNIcon] into a flat dict ready for the native layer.
  Future<Map<String, dynamic>> _resolveIconMap(
    CNIcon? icon,
    BuildContext context,
  ) async {
    if (icon == null) return {};
    final base = icon.toMap();
    // Resolve asset path for DPI variants if needed.
    final assetPath = base['assetPath'] as String?;
    if (assetPath != null) {
      final resolved = await resolveAssetPathForPixelRatio(assetPath);
      return {...base, 'assetPath': resolved};
    }
    return base;
  }

  /// Serializes [CNButtonTheme] into a flat dict.
  Map<String, dynamic> _themeToMap(CNButtonTheme theme, BuildContext context) {
    final map = <String, dynamic>{'glassMaterial': theme.glassMaterial.name};
    if (theme.tint != null) {
      map['tint'] = resolveColorToArgb(theme.tint, context);
    }
    if (theme.labelColor != null) {
      map['labelColor'] = resolveColorToArgb(theme.labelColor, context);
    }
    if (theme.iconColor != null) {
      map['themeIconColor'] = resolveColorToArgb(theme.iconColor, context);
    }
    if (theme.backgroundColor != null) {
      map['backgroundColor'] = resolveColorToArgb(
        theme.backgroundColor,
        context,
      );
    }
    return map;
  }

  Map<String, dynamic> _buildButtonMap({
    required String? label,
    required Map<String, dynamic> iconMap,
    required bool enabled,
    required CNButtonTheme theme,
    required Map<String, dynamic> themeMap,
    required CNButtonDataConfig config,
  }) {
    // Per-asset icon color (lower priority than theme colors).
    return {
      if (label != null) 'label': label,
      ...iconMap,
      'enabled': enabled,
      ...themeMap,
      'minHeight': config.minHeight ?? 44.0,
      'style': config.style.name,
      if (config.glassEffectUnionId != null)
        'glassEffectUnionId': config.glassEffectUnionId,
      if (config.glassEffectId != null) 'glassEffectId': config.glassEffectId,
      'glassEffectInteractive': config.glassEffectInteractive,
      if (config.borderRadius != null) 'borderRadius': config.borderRadius,
      if (config.padding != null) ..._paddingMap(config.padding!),
      if (config.minHeight != null) 'minHeight': config.minHeight,
      if (config.imagePadding != null) 'imagePadding': config.imagePadding,
    };
  }

  Map<String, dynamic> _paddingMap(EdgeInsets p) => {
    if (p.top != 0.0) 'paddingTop': p.top,
    if (p.bottom != 0.0) 'paddingBottom': p.bottom,
    if (p.left != 0.0) 'paddingLeft': p.left,
    if (p.right != 0.0) 'paddingRight': p.right,
    if (p.left == p.right && p.left != 0.0) 'paddingHorizontal': p.left,
    if (p.top == p.bottom && p.top != 0.0) 'paddingVertical': p.top,
  };

  // ---------------------------------------------------------------------------
  // Flutter fallback
  // ---------------------------------------------------------------------------

  Widget _buildFlutterFallback(BuildContext context) {
    final children = _usingWidgets
        ? _buildWidgetChildren()
        : _buildDataChildren();

    if (widget.axis == Axis.horizontal) {
      return Wrap(
        spacing: widget.spacing,
        runSpacing: widget.spacing,
        children: children,
      );
    } else {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: children
            .map(
              (child) => Padding(
                padding: EdgeInsets.only(bottom: widget.spacing),
                child: child,
              ),
            )
            .toList(),
      );
    }
  }

  List<Widget> _buildWidgetChildren() {
    return widget._buttonWidgets!.map((button) {
      if (button.isIcon) {
        return CNButton.icon(
          icon: button.icon!,
          onPressed: button.onPressed,
          enabled: button.enabled,
          theme: button.theme,
          tint: button.tint,
          config: CNButtonConfig(
            width: button.config.width,
            style: button.config.style,
            shrinkWrap: true,
            padding: button.config.padding,
            borderRadius: button.config.borderRadius,
            minHeight: button.config.minHeight,
            imagePadding: button.config.imagePadding,
            imagePlacement: button.config.imagePlacement,
            glassEffectUnionId: button.config.glassEffectUnionId,
            glassEffectId: button.config.glassEffectId,
            glassEffectInteractive: button.config.glassEffectInteractive,
          ),
        );
      } else {
        return CNButton(
          label: button.label!,
          icon: button.icon,
          onPressed: button.onPressed,
          enabled: button.enabled,
          theme: button.theme,
          tint: button.tint,
          config: CNButtonConfig(
            width: button.config.width,
            style: button.config.style,
            shrinkWrap: true,
            padding: button.config.padding,
            borderRadius: button.config.borderRadius,
            minHeight: button.config.minHeight,
            imagePadding: button.config.imagePadding,
            imagePlacement: button.config.imagePlacement,
            glassEffectUnionId: button.config.glassEffectUnionId,
            glassEffectId: button.config.glassEffectId,
            glassEffectInteractive: button.config.glassEffectInteractive,
          ),
        );
      }
    }).toList();
  }

  List<Widget> _buildDataChildren() {
    return widget.buttons.map((data) {
      final config = CNButtonConfig(
        width: data.config.width,
        style: data.config.style,
        shrinkWrap: true,
        padding: data.config.padding,
        borderRadius: data.config.borderRadius,
        minHeight: data.config.minHeight,
        imagePadding: data.config.imagePadding,
        imagePlacement: data.config.imagePlacement ?? CNImagePlacement.leading,
        glassEffectUnionId: data.config.glassEffectUnionId,
        glassEffectId: data.config.glassEffectId,
        glassEffectInteractive: data.config.glassEffectInteractive,
      );
      if (data.isIcon) {
        return CNButton.icon(
          icon: data.icon!,
          onPressed: data.onPressed,
          enabled: data.enabled,
          theme: data.theme,
          config: config,
        );
      } else {
        return CNButton(
          label: data.label!,
          icon: data.icon,
          onPressed: data.onPressed,
          enabled: data.enabled,
          theme: data.theme,
          config: config,
        );
      }
    }).toList();
  }
}

// ---------------------------------------------------------------------------
// Change detection snapshot
// ---------------------------------------------------------------------------

/// Calls [onMount] when it's mounted, which is when the platform view in
/// [child] is created. Tells a new platform view from a rebuilt one.
class _PlatformViewMount extends StatefulWidget {
  const _PlatformViewMount({required this.onMount, required this.child});

  final VoidCallback onMount;
  final Widget child;

  @override
  State<_PlatformViewMount> createState() => _PlatformViewMountState();
}

class _PlatformViewMountState extends State<_PlatformViewMount> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The buttons' native params, with the snapshots they were made from.
class _ButtonsParams {
  const _ButtonsParams({required this.snapshots, required this.buttons});

  final List<_ButtonSnapshot> snapshots;
  final List<Map<String, dynamic>> buttons;
}

class _ButtonSnapshot {
  final String? label;
  final Map<String, dynamic> iconMap;
  final String style;
  final bool enabled;
  final int? tint;
  final String glassMaterial;

  _ButtonSnapshot({
    this.label,
    required this.iconMap,
    required this.style,
    required this.enabled,
    this.tint,
    this.glassMaterial = 'regular',
  });

  factory _ButtonSnapshot.fromButtonWidget(CNButton button) {
    return _ButtonSnapshot(
      label: button.label,
      iconMap: button.icon?.toMap() ?? {},
      style: button.config.style.name,
      enabled: button.enabled,
      tint: button.tint?.toARGB32(),
      glassMaterial: button.theme.glassMaterial.name,
    );
  }

  factory _ButtonSnapshot.fromButtonData(CNButtonData button) {
    return _ButtonSnapshot(
      label: button.label,
      iconMap: button.icon?.toMap() ?? {},
      style: button.config.style.name,
      enabled: button.enabled,
      tint: button.theme.tint?.toARGB32(),
      glassMaterial: button.theme.glassMaterial.name,
    );
  }

  bool equals(_ButtonSnapshot other) {
    if (label != other.label) return false;
    if (style != other.style) return false;
    if (enabled != other.enabled) return false;
    if (tint != other.tint) return false;
    if (glassMaterial != other.glassMaterial) return false;
    // Compare icon maps
    if (iconMap.length != other.iconMap.length) return false;
    for (final key in iconMap.keys) {
      if (iconMap[key] != other.iconMap[key]) return false;
    }
    return true;
  }
}
