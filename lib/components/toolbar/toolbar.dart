import 'dart:io';

import 'package:collapsible/collapsible.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:keybinder/keybinder.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:saber/components/canvas/ruler.dart';
import 'package:saber/components/canvas/zoom_window.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/components/theming/dynamic_material_app.dart';
import 'package:saber/components/theming/uni_icon.dart';
import 'package:saber/components/toolbar/color_bar.dart';
import 'package:saber/components/toolbar/eraser_modal.dart';
import 'package:saber/components/toolbar/export_bar.dart';
import 'package:saber/components/toolbar/pen_modal.dart';
import 'package:saber/components/toolbar/ruler_modal.dart';
import 'package:saber/components/toolbar/select_modal.dart';
import 'package:saber/components/toolbar/selection_bar.dart';
import 'package:saber/components/toolbar/shapes_bar.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/components/toolbar/toolbar_button.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/laser_pointer.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pencil.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/data/tools/shape_placer.dart';
import 'package:saber/data/tools/tape.dart';
import 'package:saber/i18n/strings.g.dart';

class Toolbar extends StatefulWidget {
  const new({
    super.key,
    required this.readOnly,
    required this.setTool,
    required this.currentTool,
    required this.setColor,
    required this.quillFocus,
    required this.textEditing,
    required this.toggleTextEditing,
    required this.undo,
    required this.isUndoPossible,
    required this.redo,
    required this.isRedoPossible,
    required this.toggleFingerDrawing,
    required this.ruler,
    required this.zoomWindow,
    required this.toggleZoomWindow,
    required this.pickPhoto,
    required this.paste,
    required this.duplicateSelection,
    required this.changeSelectionThickness,
    required this.finishSelectionThickness,
    required this.deleteSelection,
    required this.exportAsSba,
    required this.exportAsPdf,
    required this.exportAsPng,
    required this.showExportOptions,
    required this.importPdf,
  });

  final bool readOnly;

  final ValueChanged<Tool> setTool;
  final Tool currentTool;
  final ValueChanged<Color> setColor;

  final ValueNotifier<QuillStruct?> quillFocus;
  final bool textEditing;
  final VoidCallback toggleTextEditing;

  final VoidCallback undo;
  final bool isUndoPossible;
  final VoidCallback redo;
  final bool isRedoPossible;

  final VoidCallback toggleFingerDrawing;

  /// Shown or hidden by the ruler button.
  final Ruler ruler;

  /// Shown or hidden by [toggleZoomWindow].
  final ZoomWindow zoomWindow;
  final VoidCallback toggleZoomWindow;

  final VoidCallback pickPhoto;

  final VoidCallback paste;

  final VoidCallback duplicateSelection;

  /// See [SelectionBar.changeThickness].
  final ValueChanged<double> changeSelectionThickness;
  final VoidCallback finishSelectionThickness;
  final VoidCallback deleteSelection;

  final Future Function(BuildContext)? exportAsSba;
  final Future Function(BuildContext)? exportAsPdf;
  final Future Function(BuildContext)? exportAsPng;

  /// Whether the export bar is open; its button is in the app bar (see
  /// [Editor]), or in the toolbar in fullscreen.
  final ValueNotifier<bool> showExportOptions;

  /// Imports a PDF's pages into the note, or null if PDFs can't be.
  final VoidCallback? importPdf;

  @override
  State<Toolbar> createState() => _ToolbarState();

  static const _buttonPaddingHorizontal = EdgeInsets.symmetric(horizontal: 6);
  static const _buttonPaddingVertical = EdgeInsets.symmetric(vertical: 6);
}

class _ToolbarState extends State<Toolbar> {
  ValueNotifier<bool> showColorOptions = ValueNotifier(false);
  ValueNotifier<ToolOptions> toolOptionsType = ValueNotifier(ToolOptions.hide);

  @override
  void initState() {
    _assignKeybindings();

    DynamicMaterialApp.addFullscreenListener(_setState);

    super.initState();
  }

  void _setState() => setState(() {});

  /// A toolbar button, measured after layout: all of them are this long
  /// along the toolbar ([_buttonLength]).
  final _measuredButton = GlobalKey();
  double? _buttonLength;

  /// Whether [groups] of buttons fit in [room], in one row with dividers
  /// between them. Until a button has been measured, nothing fits (the
  /// toolbar wraps for a frame, then measures and lays out again).
  bool _fits(List<List<Widget>> groups, double room) {
    final buttonLength = _buttonLength;
    if (buttonLength == null) return false;
    final buttons = groups.fold(0, (count, group) => count + group.length);
    return buttons * buttonLength +
            (groups.length - 1) * _GroupDivider.length <=
        room;
  }

  /// Measures [_measuredButton] (after a frame), laying out again if its
  /// length changed (e.g. the toolbar moved to the side).
  void _measureButton(Axis axis) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _measuredButton.currentContext?.findRenderObject();
      if (!mounted || box is! RenderBox || !box.hasSize) return;
      final length = axis == Axis.horizontal ? box.size.width : box.size.height;
      if (length != _buttonLength) setState(() => _buttonLength = length);
    });
  }

  Keybinding? _ctrlF;
  Keybinding? _ctrlE;
  Keybinding? _ctrlC;
  Keybinding? _ctrlShiftS;
  Keybinding? _f11;
  Keybinding? _ctrlV;
  void _assignKeybindings() {
    _ctrlF = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyF),
    ], inclusive: true);
    _ctrlE = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyE),
    ], inclusive: true);
    _ctrlC = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyC),
    ], inclusive: true);
    _ctrlShiftS = Keybinding([
      KeyCode.ctrl,
      KeyCode.shift,
      KeyCode.from(LogicalKeyboardKey.keyS),
    ], inclusive: true);
    _f11 = Keybinding([KeyCode.from(LogicalKeyboardKey.f11)], inclusive: true);
    _ctrlV = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyV),
    ], inclusive: true);

    Keybinder.bind(_ctrlF!, widget.toggleFingerDrawing);
    Keybinder.bind(_ctrlE!, toggleEraser);
    Keybinder.bind(_ctrlC!, toggleColorOptions);
    Keybinder.bind(_ctrlShiftS!, toggleExportBar);
    Keybinder.bind(_f11!, toggleFullscreen);
    Keybinder.bind(_ctrlV!, widget.paste);
  }

  void _removeKeybindings() {
    if (_ctrlF != null) Keybinder.remove(_ctrlF!);
    if (_ctrlE != null) Keybinder.remove(_ctrlE!);
    if (_ctrlC != null) Keybinder.remove(_ctrlC!);
    if (_ctrlShiftS != null) Keybinder.remove(_ctrlShiftS!);
    if (_f11 != null) Keybinder.remove(_f11!);
    if (_ctrlV != null) Keybinder.remove(_ctrlV!);
  }

  void toggleEraser() {
    toolOptionsType.value = .hide;
    widget.setTool(Eraser.currentEraser); // this toggles eraser
  }

  void toggleColorOptions() {
    showColorOptions.value = !showColorOptions.value;
  }

  void toggleExportBar() {
    widget.showExportOptions.value = !widget.showExportOptions.value;
  }

  void toggleFullscreen() async {
    DynamicMaterialApp.setFullscreen(
      !DynamicMaterialApp.isFullscreen,
      updateSystem: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    final brightness = Theme.brightnessOf(context);
    final invert = stows.editorAutoInvert.value && brightness == .dark;

    final isToolbarVertical =
        stows.editorToolbarAlignment.value == AxisDirection.left ||
        stows.editorToolbarAlignment.value == AxisDirection.right;

    final buttonPadding = isToolbarVertical
        ? Toolbar._buttonPaddingVertical
        : Toolbar._buttonPaddingHorizontal;

    final currentColor = switch (widget.currentTool) {
      final Pen pen => pen.color,
      final Select select => select.getDominantStrokeColor(),
      _ => null,
    };

    if (widget.currentTool case final Select select) {
      // Show the selection bar only when a selection is done,
      // without closing the selection mode modal otherwise.
      if (select.doneSelecting) {
        toolOptionsType.value = .select;
      } else if (toolOptionsType.value == .select) {
        toolOptionsType.value = .hide;
      }
    }

    final Widget pen = ToolbarIconButton(
      tooltip: Pen.currentPen.name,
      selected: widget.currentTool == Pen.currentPen,
      enabled: !widget.readOnly,
      onPressed: () {
        if (widget.currentTool == Pen.currentPen) {
          if (toolOptionsType.value == .pen) {
            toolOptionsType.value = .hide;
          } else {
            toolOptionsType.value = .pen;
          }
        } else {
          toolOptionsType.value = .hide;
          widget.setTool(Pen.currentPen);
        }
      },
      padding: buttonPadding,
      child: UniIcon(Pen.currentPen.icon, size: 16),
    );
    final Widget pencil = ToolbarIconButton(
      tooltip: t.editor.pens.pencil,
      selected: widget.currentTool == Pencil.currentPencil,
      enabled: !widget.readOnly,
      onPressed: () {
        if (widget.currentTool == Pencil.currentPencil) {
          if (toolOptionsType.value == .pencil) {
            toolOptionsType.value = .hide;
          } else {
            toolOptionsType.value = .pencil;
          }
        } else {
          toolOptionsType.value = .hide;
          widget.setTool(Pencil.currentPencil);
        }
      },
      padding: buttonPadding,
      child: const FaIcon(Pencil.pencilIcon, size: 16),
    );
    final Widget highlighter = ToolbarIconButton(
      tooltip: t.editor.pens.highlighter,
      selected: widget.currentTool == Tape.highlighterTab,
      enabled: !widget.readOnly,
      onPressed: () {
        if (widget.currentTool == Tape.highlighterTab) {
          if (toolOptionsType.value == .highlighter) {
            toolOptionsType.value = .hide;
          } else {
            toolOptionsType.value = .highlighter;
          }
        } else {
          toolOptionsType.value = .hide;
          widget.setTool(Tape.highlighterTab);
        }
      },
      padding: buttonPadding,
      child: const FaIcon(Highlighter.highlighterIcon, size: 16),
    );
    final Widget color = ValueListenableBuilder(
      valueListenable: showColorOptions,
      builder: (context, showColorOptions, child) {
        return ToolbarIconButton(
          tooltip: t.editor.toolbar.toggleColors,
          selected: showColorOptions,
          enabled: !widget.readOnly,
          onPressed: toggleColorOptions,
          padding: buttonPadding,
          child: child!,
        );
      },
      child: currentColor == null
          ? const Icon(Icons.palette)
          : Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: currentColor.withInversion(invert).withValues(alpha: 1),
                shape: .circle,
                border: Border.all(color: colorScheme.primary, width: 2),
              ),
            ),
    );
    final Widget select = ToolbarIconButton(
      tooltip: t.editor.toolbar.select,
      selected: widget.currentTool is Select,
      enabled: !widget.readOnly,
      onPressed: () {
        if (widget.currentTool is Select) {
          toolOptionsType.value = toolOptionsType.value == .selectMode
              ? .hide
              : .selectMode;
        } else {
          toolOptionsType.value = .hide;
          widget.setTool(Select.current);
        }
      },
      padding: buttonPadding,
      child: ListenableBuilder(
        listenable: stows.lastSelectBoxMode,
        builder: (context, _) => Icon(
          Select.current.icon,
          shadows: !widget.readOnly
              ? [
                  BoxShadow(
                    color: colorScheme.primary,
                    blurRadius: 0.1,
                    spreadRadius: 10,
                    blurStyle: BlurStyle.solid,
                  ),
                ]
              : null,
        ),
      ),
    );
    final Widget eraser = ToolbarIconButton(
      tooltip: t.editor.toolbar.toggleEraser,
      selected: widget.currentTool is Eraser,
      enabled: !widget.readOnly,
      onPressed: () {
        // eraser modal
        if (widget.currentTool is Eraser) {
          if (toolOptionsType.value == .eraser) {
            toolOptionsType.value = .hide;
          } else {
            toolOptionsType.value = .eraser;
          }
        } else {
          toolOptionsType.value = .hide;
          widget.setTool(Eraser.currentEraser);
        }
      },
      padding: buttonPadding,
      child: ListenableBuilder(
        listenable: stows.lastEraserAreaMode,
        builder: (context, _) {
          final iconTheme = IconTheme.of(context);
          return SvgPicture.asset(
            Eraser.currentEraser.icon,
            width: iconTheme.size,
            height: iconTheme.size,
            theme: SvgTheme(currentColor: iconTheme.color!),
          );
        },
      ),
    );
    final Widget image = ToolbarIconButton(
      tooltip: t.editor.toolbar.photo,
      enabled: !widget.readOnly,
      onPressed: widget.pickPhoto,
      padding: buttonPadding,
      child: const AdaptiveIcon(
        icon: Icons.photo,
        cupertinoIcon: CupertinoIcons.photo,
      ),
    );
    final Widget text = ToolbarIconButton(
      tooltip: t.editor.toolbar.text,
      selected: widget.textEditing,
      enabled: !widget.readOnly,
      onPressed: widget.toggleTextEditing,
      padding: buttonPadding,
      child: const AdaptiveIcon(
        icon: Icons.text_fields,
        cupertinoIcon: CupertinoIcons.text_cursor,
      ),
    );
    final placingShapes = widget.currentTool is ShapePlacer;
    // Picks the shape placer and shows its options, or hides or shows them.
    void openShapes() {
      if (placingShapes) {
        toolOptionsType.value = toolOptionsType.value == .shapes
            ? .hide
            : .shapes;
      } else {
        widget.setTool(ShapePlacer.currentPlacer);
        toolOptionsType.value = .shapes;
      }
    }

    final Widget shapes = ToolbarIconButton(
      tooltip: t.editor.toolbar.shapes,
      selected: placingShapes,
      enabled: !widget.readOnly,
      onPressed: openShapes,
      padding: buttonPadding,
      child: const Icon(ShapePlacer.shapesIcon),
    );
    final Widget laser = ToolbarIconButton(
      tooltip: t.editor.pens.laserPointer,
      selected: widget.currentTool == LaserPointer.currentLaserPointer,
      enabled: true, // even in read-only mode
      onPressed: () {
        toolOptionsType.value = .hide;
        widget.setTool(LaserPointer.currentLaserPointer);
      },
      padding: buttonPadding,
      child: const Icon(Symbols.stylus_laser_pointer),
    );
    final Widget ruler = ListenableBuilder(
      listenable: widget.ruler,
      builder: (context, child) => ToolbarIconButton(
        tooltip: t.editor.toolbar.ruler,
        selected: widget.ruler.visible,
        // Shows the ruler, then opens or closes its options.
        onPressed: () {
          if (!widget.ruler.visible) {
            widget.ruler.visible = true;
            toolOptionsType.value = .ruler;
          } else {
            toolOptionsType.value = toolOptionsType.value == .ruler
                ? .hide
                : .ruler;
          }
        },
        padding: buttonPadding,
        child: child!,
      ),
      child: const Icon(Icons.straighten),
    );
    final Widget zoomWindow = ListenableBuilder(
      listenable: widget.zoomWindow,
      builder: (context, child) => ToolbarIconButton(
        tooltip: t.editor.zoomWindow.title,
        selected: widget.zoomWindow.visible,
        enabled: !widget.readOnly,
        onPressed: widget.toggleZoomWindow,
        padding: buttonPadding,
        child: child!,
      ),
      child: const Icon(Icons.zoom_in),
    );
    final Widget? fingerDrawing = stows.hideFingerDrawingToggle.value
        ? null
        : ValueListenableBuilder(
            valueListenable: stows.editorFingerDrawing,
            builder: (context, value, child) {
              return ToolbarIconButton(
                tooltip: t.editor.toolbar.toggleFingerDrawing,
                selected: value,
                enabled: !widget.readOnly,
                onPressed: widget.toggleFingerDrawing,
                padding: buttonPadding,
                child: const Icon(CupertinoIcons.hand_draw),
              );
            },
          );
    final Widget fullscreen = ToolbarIconButton(
      tooltip: t.editor.toolbar.fullscreen,
      selected: DynamicMaterialApp.isFullscreen,
      enabled: !widget.readOnly,
      onPressed: toggleFullscreen,
      padding: buttonPadding,
      child: AdaptiveIcon(
        icon: DynamicMaterialApp.isFullscreen
            ? Icons.fullscreen_exit
            : Icons.fullscreen,
        cupertinoIcon: DynamicMaterialApp.isFullscreen
            ? CupertinoIcons.fullscreen_exit
            : CupertinoIcons.fullscreen,
      ),
    );
    final Widget undo = ToolbarIconButton(
      tooltip: t.editor.toolbar.undo,
      enabled: !widget.readOnly && widget.isUndoPossible,
      onPressed: widget.undo,
      padding: buttonPadding,
      child: const AdaptiveIcon(
        icon: Icons.undo,
        cupertinoIcon: CupertinoIcons.arrow_uturn_left,
      ),
    );
    final Widget redo = ToolbarIconButton(
      tooltip: t.editor.toolbar.redo,
      enabled: !widget.readOnly && widget.isRedoPossible,
      onPressed: widget.redo,
      padding: buttonPadding,
      child: const AdaptiveIcon(
        icon: Icons.redo,
        cupertinoIcon: CupertinoIcons.arrow_uturn_right,
      ),
    );
    final Widget share = ValueListenableBuilder(
      valueListenable: widget.showExportOptions,
      builder: (context, showExportOptions, child) {
        return ToolbarIconButton(
          tooltip: t.editor.toolbar.export,
          selected: showExportOptions,
          enabled: !widget.readOnly,
          onPressed: toggleExportBar,
          padding: buttonPadding,
          child: child!,
        );
      },
      child: const AdaptiveIcon(
        icon: Icons.share,
        cupertinoIcon: CupertinoIcons.share,
      ),
    );
    final pdf = ToolbarIconButton(
      tooltip: t.editor.toolbar.pdf,
      enabled: !widget.readOnly,
      onPressed: widget.importPdf,
      padding: buttonPadding,
      child: const Icon(Icons.picture_as_pdf),
    );

    // The groups of buttons (see [ToolOptions.insert] and [ToolOptions.tools]).
    final writing = [
      // Measured, to work out how many buttons fit (see [_fits]).
      KeyedSubtree(key: _measuredButton, child: pen),
      pencil,
      highlighter,
      color,
      select,
      eraser,
    ];
    final insert = [image, text, shapes, pdf];
    final tools = [ruler, zoomWindow, laser];
    final view = [
      ?fingerDrawing,
      fullscreen,
      // Share is in the app bar, which fullscreen hides.
      if (DynamicMaterialApp.isFullscreen) share,
    ];
    final edit = [undo, redo];
    final toolsActive =
        widget.ruler.visible ||
        widget.zoomWindow.visible ||
        widget.currentTool == LaserPointer.currentLaserPointer;
    Widget groupButton(
      ToolOptions group,
      String name,
      IconData icon, {
      required bool active,
    }) => ValueListenableBuilder(
      valueListenable: toolOptionsType,
      builder: (context, open, _) => ToolbarIconButton(
        tooltip: name,
        selected: open == group,
        enabled: !widget.readOnly,
        onPressed: () => toolOptionsType.value = open == group ? .hide : group,
        padding: buttonPadding,
        // A dot when something in the group is on.
        child: Badge(isLabelVisible: active, child: Icon(icon)),
      ),
    );
    final insertGroup = groupButton(
      .insert,
      t.editor.toolbar.insert,
      Icons.add_box_outlined,
      active: widget.textEditing || placingShapes,
    );
    final toolsGroup = groupButton(
      .tools,
      t.editor.toolbar.tools,
      Icons.handyman_outlined,
      active: toolsActive,
    );
    final axis = isToolbarVertical ? Axis.vertical : Axis.horizontal;
    _measureButton(axis);
    Widget row(List<List<Widget>> groups) => Flex(
      direction: axis,
      mainAxisSize: .min,
      children: [
        for (final (index, group) in groups.indexed) ...[
          if (index > 0) _GroupDivider(axis: axis),
          ...group,
        ],
      ],
    );

    final bars = <Widget>[
      ValueListenableBuilder(
        valueListenable: widget.showExportOptions,
        builder: (context, showExportOptions, child) {
          return Collapsible(
            axis: isToolbarVertical
                ? CollapsibleAxis.horizontal
                : CollapsibleAxis.vertical,
            maintainState: true,
            collapsed: !showExportOptions,
            child: child!,
          );
        },
        child: ExportBar(
          axis: isToolbarVertical ? Axis.vertical : Axis.horizontal,
          toggleExportBar: toggleExportBar,
          exportAsSba: widget.exportAsSba,
          exportAsPdf: widget.exportAsPdf,
          exportAsPng: widget.exportAsPng,
        ),
      ),
      ValueListenableBuilder(
        valueListenable: toolOptionsType,
        builder: (context, toolOptionsType, _) {
          return Collapsible(
            axis: isToolbarVertical
                ? CollapsibleAxis.horizontal
                : CollapsibleAxis.vertical,
            maintainState: true,
            collapsed: toolOptionsType == .hide,
            // Centred, and scrollable where it's wider than the screen
            // (e.g. the pen options on a phone).
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: isToolbarVertical
                    ? Axis.vertical
                    : Axis.horizontal,
                child: switch (toolOptionsType) {
                  .hide => const SizedBox.square(
                    dimension: SizePicker.smallLength,
                  ),
                  .pen => PenModal(
                    getTool: () => Pen.currentPen,
                    setTool: widget.setTool,
                  ),
                  .highlighter => PenModal(
                    getTool: () => Tape.highlighterTab,
                    setTool: widget.setTool,
                  ),
                  .pencil => PenModal(
                    getTool: () => Pencil.currentPencil,
                    setTool: widget.setTool,
                  ),
                  .eraser => EraserModal(getTool: () => Eraser.currentEraser),
                  .shapes => const ShapesBar(),
                  .selectMode => SelectModal(setTool: widget.setTool),
                  .select => SelectionBar(
                    duplicateSelection: widget.duplicateSelection,
                    changeThickness: widget.changeSelectionThickness,
                    finishThickness: widget.finishSelectionThickness,
                    deleteSelection: widget.deleteSelection,
                  ),
                  .insert => _GroupBar(
                    axis: isToolbarVertical ? Axis.vertical : Axis.horizontal,
                    items: [
                      (
                        icon: Icons.photo,
                        name: t.editor.toolbar.photo,
                        selected: false,
                        onPressed: () {
                          this.toolOptionsType.value = .hide;
                          widget.pickPhoto();
                        },
                      ),
                      (
                        icon: Icons.text_fields,
                        name: t.editor.toolbar.text,
                        selected: widget.textEditing,
                        onPressed: widget.toggleTextEditing,
                      ),
                      (
                        icon: ShapePlacer.shapesIcon,
                        name: t.editor.toolbar.shapes,
                        selected: placingShapes,
                        onPressed: openShapes,
                      ),
                      if (widget.importPdf case final importPdf?)
                        (
                          icon: Icons.picture_as_pdf,
                          name: t.editor.toolbar.pdf,
                          selected: false,
                          onPressed: () {
                            this.toolOptionsType.value = .hide;
                            importPdf();
                          },
                        ),
                    ],
                  ),
                  .tools => _GroupBar(
                    axis: isToolbarVertical ? Axis.vertical : Axis.horizontal,
                    items: [
                      (
                        icon: Icons.straighten,
                        name: t.editor.toolbar.ruler,
                        selected: widget.ruler.visible,
                        // Shows the ruler and its options.
                        onPressed: () {
                          widget.ruler.visible = true;
                          this.toolOptionsType.value = .ruler;
                        },
                      ),
                      (
                        icon: Icons.zoom_in,
                        name: t.editor.zoomWindow.title,
                        selected: widget.zoomWindow.visible,
                        onPressed: widget.toggleZoomWindow,
                      ),
                      (
                        icon: Symbols.stylus_laser_pointer,
                        name: t.editor.pens.laserPointer,
                        selected:
                            widget.currentTool ==
                            LaserPointer.currentLaserPointer,
                        onPressed: () {
                          this.toolOptionsType.value = .hide;
                          widget.setTool(LaserPointer.currentLaserPointer);
                        },
                      ),
                    ],
                  ),
                  .ruler => RulerModal(
                    ruler: widget.ruler,
                    hide: () {
                      widget.ruler.visible = false;
                      this.toolOptionsType.value = .hide;
                    },
                  ),
                },
              ),
            ),
          );
        },
      ),
      ValueListenableBuilder(
        valueListenable: showColorOptions,
        builder: (context, showColorOptions, child) {
          return Collapsible(
            axis: isToolbarVertical
                ? CollapsibleAxis.horizontal
                : CollapsibleAxis.vertical,
            maintainState: true,
            collapsed: !showColorOptions,
            child: child!,
          );
        },
        child: ColorBar(
          axis: isToolbarVertical ? Axis.vertical : Axis.horizontal,
          setColor: widget.setColor,
          currentColor: currentColor,
          invert: invert,
        ),
      ),
      ValueListenableBuilder(
        valueListenable: widget.quillFocus,
        builder: (context, quill, _) {
          final baseButtonStyle =
              IconButtonTheme.of(context).style ?? const ButtonStyle();

          final iconTheme = QuillIconTheme(
            iconButtonUnselectedData: IconButtonData(
              style: baseButtonStyle.copyWith(
                backgroundColor: WidgetStateProperty.all(Colors.transparent),
                foregroundColor: WidgetStateProperty.all(colorScheme.primary),
              ),
            ),
            iconButtonSelectedData: IconButtonData(
              style: baseButtonStyle.copyWith(
                backgroundColor: WidgetStateProperty.all(colorScheme.primary),
                foregroundColor: WidgetStateProperty.all(colorScheme.onPrimary),
              ),
            ),
          );
          return Collapsible(
            axis: isToolbarVertical
                ? CollapsibleAxis.horizontal
                : CollapsibleAxis.vertical,
            maintainState: false,
            collapsed: !widget.textEditing || quill == null,
            child: quill != null
                ? QuillSimpleToolbar(
                    controller: quill.controller,
                    config: QuillSimpleToolbarConfig(
                      axis: isToolbarVertical ? Axis.vertical : Axis.horizontal,
                      buttonOptions: QuillSimpleToolbarButtonOptions(
                        base: QuillToolbarBaseButtonOptions(
                          iconTheme: iconTheme,
                        ),
                      ),
                      // scrollable on Android and iOS
                      multiRowsDisplay: !Platform.isAndroid && !Platform.isIOS,
                      showUndo: false,
                      showRedo: false,
                      showFontSize: false,
                      showFontFamily: false,
                      showClearFormat: false,
                    ),
                  )
                : const SizedBox.shrink(),
          );
        },
      ),
      Center(
        child: Padding(
          padding: const .all(8),
          // Groups inline when there's room, collapsed into a button when
          // there isn't (Tools first), and wrapping if even that's too wide.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final room = axis == Axis.horizontal
                  ? constraints.maxWidth
                  : constraints.maxHeight;
              final allInline = [writing, insert, tools, view, edit];
              final toolsCollapsed = [
                writing,
                insert,
                [toolsGroup],
                view,
                edit,
              ];
              final bothCollapsed = [
                [...writing, insertGroup, toolsGroup],
                view,
                edit,
              ];
              for (final groups in [allInline, toolsCollapsed, bothCollapsed]) {
                if (_fits(groups, room)) return row(groups);
              }
              return Wrap(
                direction: axis,
                alignment: WrapAlignment.center,
                runSpacing: 8,
                children: [for (final group in bothCollapsed) ...group],
              );
            },
          ),
        ),
      ),
    ];

    return Flex(
      direction: isToolbarVertical ? Axis.horizontal : Axis.vertical,
      textDirection: switch (stows.editorToolbarAlignment.value) {
        AxisDirection.left => .rtl,
        AxisDirection.right => .ltr,
        _ => null,
      },
      verticalDirection: switch (stows.editorToolbarAlignment.value) {
        AxisDirection.down => VerticalDirection.down,
        AxisDirection.up => VerticalDirection.up,
        _ => VerticalDirection.down,
      },
      children: bars,
    );
  }

  @override
  void dispose() {
    DynamicMaterialApp.removeFullscreenListener(_setState);
    DynamicMaterialApp.setFullscreen(false, updateSystem: true);

    _removeKeybindings();
    super.dispose();
  }
}

enum ToolOptions {
  hide,

  /// The buttons of a group collapsed into one (see [_GroupBar]).
  insert,
  tools,
  pen,
  highlighter,
  pencil,
  eraser,

  /// The options of [ShapePlacer].
  shapes,
  selectMode,
  select,
  ruler,
}

/// A thin line between groups of toolbar buttons, as long as a button.
class _GroupDivider extends StatelessWidget {
  const new({required this.axis});

  final Axis axis;

  /// The space on either side of the line.
  static const _gap = ToolbarIconButton.innerPadding / 2;

  /// How much room it takes along the toolbar.
  static const length = 2 * _gap + 1;

  @override
  Widget build(BuildContext context) {
    const length =
        ToolbarIconButton.iconSize + 2 * ToolbarIconButton.innerPadding;
    final horizontal = axis == Axis.horizontal;
    return Padding(
      padding: horizontal
          ? const .symmetric(horizontal: _gap)
          : const .symmetric(vertical: _gap),
      child: SizedBox(
        width: horizontal ? 1 : length,
        height: horizontal ? length : 1,
        child: ColoredBox(color: ColorScheme.of(context).outlineVariant),
      ),
    );
  }
}

/// The buttons of a collapsed group (e.g. Insert), each with its name, so
/// nothing has to be guessed from an icon.
class _GroupBar extends StatelessWidget {
  const new({required this.axis, required this.items});

  final Axis axis;
  final List<
    ({IconData icon, String name, bool selected, VoidCallback onPressed})
  >
  items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const .all(ToolbarIconButton.innerPadding / 2),
      child: Flex(
        direction: axis,
        mainAxisSize: .min,
        spacing: ToolbarIconButton.innerPadding,
        children: [
          for (final item in items)
            if (item.selected)
              FilledButton.tonalIcon(
                onPressed: item.onPressed,
                icon: Icon(item.icon),
                label: Text(item.name),
              )
            else
              TextButton.icon(
                onPressed: item.onPressed,
                icon: Icon(item.icon),
                label: Text(item.name),
              ),
        ],
      ),
    );
  }
}
