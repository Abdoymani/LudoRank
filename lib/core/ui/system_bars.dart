import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps Android's status and navigation bars transparent over the app,
/// so the system's grey navigation bar never shows under a dark screen.
///
/// Used once around the whole app (MaterialApp.builder), in light and dark.
class AppSystemBars extends StatelessWidget {
  final Widget child;

  const AppSystemBars({super.key, required this.child});

  /// The bars' style for [theme]: transparent (the app draws behind
  /// them), no grey contrast scrim, icons readable on the background.
  static SystemUiOverlayStyle styleFor(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    final iconBrightness = dark ? Brightness.light : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: iconBrightness,
      statusBarBrightness: theme.brightness,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: iconBrightness,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: styleFor(Theme.of(context)),
      child: child,
    );
  }
}

/// Hides the status and navigation bars while it is on screen (a swipe
/// from the edge shows them for a moment), and brings them back when it
/// leaves. For the match screen: players sit around the phone, and a hand
/// on the navigation bar must not press Home or Back by accident.
class ImmersiveSystemBars extends StatefulWidget {
  final Widget child;

  const ImmersiveSystemBars({super.key, required this.child});

  @override
  State<ImmersiveSystemBars> createState() => _ImmersiveSystemBarsState();
}

class _ImmersiveSystemBarsState extends State<ImmersiveSystemBars>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hide();
  }

  // Many phones show the bars again after the app was in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _hide();
  }

  void _hide() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
