import 'package:flutter/material.dart';

/// Owns a dialog's [TextEditingController]s so they are released only after the
/// dialog route has actually left the tree.
///
/// Wrap the widget returned by `showDialog`'s `builder` with this and hand it
/// the controllers the dialog's fields are bound to:
///
/// ```dart
/// final nameCtrl = TextEditingController();
/// final ok = await showDialog<bool>(
///   context: context,
///   builder: (ctx) => DialogControllerOwner(
///     controllers: [nameCtrl],
///     child: AlertDialog(...),
///   ),
/// );
/// // `nameCtrl.text` is still readable here; the owner disposes it later.
/// ```
///
/// Disposing the controllers in the caller the moment `showDialog`'s future
/// completes is a bug. `Navigator.pop` completes that future immediately, but
/// the route keeps animating out for a few frames afterwards; if the soft
/// keyboard closes during that exit the dialog subtree rebuilds once more
/// against the already-disposed controller. The framework then fails
/// `assert(_dependents.isEmpty)` in `InheritedElement.debugDeactivated`
/// (`package:flutter/src/widgets/framework.dart`) and the [ErrorWidget] that
/// replaces the broken subtree covers the whole app with its red-on-yellow
/// error screen.
///
/// Releasing them from a [State] that wraps the dialog moves the `dispose()`
/// to the end of the route's life. Children are unmounted before their parent,
/// so every field has already detached its listener by the time the controllers
/// are disposed and no live listener is left behind.
class DialogControllerOwner extends StatefulWidget {
  const DialogControllerOwner({
    super.key,
    required this.controllers,
    required this.child,
  });

  /// The controllers owned by the dialog below. They are disposed with this
  /// widget.
  final List<TextEditingController> controllers;

  final Widget child;

  @override
  State<DialogControllerOwner> createState() => _DialogControllerOwnerState();
}

class _DialogControllerOwnerState extends State<DialogControllerOwner> {
  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
