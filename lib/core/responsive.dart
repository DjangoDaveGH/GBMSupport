import 'package:flutter/material.dart';

/// The Enterprise Web Dashboard (Phase 5) and the mobile apps (Phases 2-4)
/// share one Flutter codebase, one Firebase backend, and every repository/
/// provider in `lib/features/*/data` — only the presentation layer forks
/// above this width. Below it, support-side roles get the same bottom-nav
/// mobile experience as everyone else; there's no separate desktop project
/// duplicating auth, models, or business logic.
const double kDesktopBreakpoint = 900;

bool isDesktopWidth(BuildContext context) => MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;
