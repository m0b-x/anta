part of re_editor;

typedef ToolbarMenuBuilder = Widget Function({
  required BuildContext context,
  required TextSelectionToolbarAnchors anchors,
  required CodeLineEditingController controller,
  required VoidCallback onDismiss,
  required VoidCallback onRefresh,
});

abstract class SelectionToolbarController {
  /// [onRefresh] is how the editor shows the toolbar again for a selection
  /// that changed under it ("Select all"), with anchors measured from the
  /// new selection; without it a refresh re-shows the toolbar at
  /// [anchors].
  ///
  /// [onDismiss] is how a toolbar action that closes the toolbar (Copy)
  /// tells the editor, so a scroll's end does not bring it back; without
  /// it a dismiss only takes the toolbar down.
  void show({
    required BuildContext context,
    required CodeLineEditingController controller,
    required TextSelectionToolbarAnchors anchors,
    Rect? renderRect,
    required LayerLink layerLink,
    required ValueNotifier<bool> visibility,
    VoidCallback? onRefresh,
    VoidCallback? onDismiss,
  });

  void hide(BuildContext context);
}

abstract class MobileSelectionToolbarController
    implements SelectionToolbarController {
  factory MobileSelectionToolbarController(
          {required ToolbarMenuBuilder builder}) =>
      _MobileSelectionToolbarController(builder: builder);
}
