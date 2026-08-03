import 'package:flutter/material.dart';

/// Lets code outside the widget tree (push notification taps, background
/// listeners) show a SnackBar or navigate without needing a BuildContext.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
