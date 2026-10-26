import 'package:flutter/material.dart';

/// The Enterprise Web Dashboard (Phase 5) and the mobile apps (Phases 2-4)
/// share one Flutter codebase, one Firebase backend, and every repository/
/// provider in `lib/features/*/data` — only the presentation layer forks
/// above this width. Below it, support-side roles get the same bottom-nav
/// mobile experience as everyone else; there's no separate desktop project
/// duplicating auth, models, or business logic.
// Keep the desktop shell for viewports with enough room for its navigation
// rail and content columns. Narrower tablets and small laptop windows use the
// compact layout instead of producing cramped desktop cards and panes.
// A standard laptop browser viewport is often 1024px wide (and can be
// narrower still when the browser is zoomed). Keep the back-office desktop
// ticket screen available at that size so its desktop Actions menu does not
// disappear merely because the window is not a large monitor.
const double kDesktopBreakpoint = 900;

bool isDesktopWidth(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;
