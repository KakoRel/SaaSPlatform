import 'package:flutter/material.dart';

class AdaptiveLayout extends StatelessWidget {
  const AdaptiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
    this.breakpoint = 600,
  });

  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1200 && desktop != null) {
          return desktop!;
        } else if (constraints.maxWidth >= breakpoint && tablet != null) {
          return tablet!;
        } else {
          return mobile;
        }
      },
    );
  }
}

class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({
    super.key,
    required this.builder,
  });

  final Widget Function(
    BuildContext context,
    ScreenType screenType,
    BoxConstraints constraints,
  ) builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        ScreenType screenType;
        
        if (constraints.maxWidth >= 1200) {
          screenType = ScreenType.desktop;
        } else if (constraints.maxWidth >= 600) {
          screenType = ScreenType.tablet;
        } else {
          screenType = ScreenType.mobile;
        }

        return builder(context, screenType, constraints);
      },
    );
  }
}

enum ScreenType { mobile, tablet, desktop }

// Responsive utilities
class Responsive {
  Responsive._();

  static bool isMobile(BoxConstraints constraints) => constraints.maxWidth < 600;
  static bool isTablet(BoxConstraints constraints) => 
      constraints.maxWidth >= 600 && constraints.maxWidth < 1200;
  static bool isDesktop(BoxConstraints constraints) => constraints.maxWidth >= 1200;

  static int getColumns(BoxConstraints constraints) {
    if (constraints.maxWidth >= 1200) return 4;
    if (constraints.maxWidth >= 900) return 3;
    if (constraints.maxWidth >= 600) return 2;
    return 1;
  }

  static double getCardWidth(BoxConstraints constraints) {
    if (constraints.maxWidth >= 1200) return 300;
    if (constraints.maxWidth >= 600) return 250;
    return constraints.maxWidth - 32;
  }

  static EdgeInsets getPadding(BoxConstraints constraints) {
    if (constraints.maxWidth >= 1200) return const EdgeInsets.all(24);
    if (constraints.maxWidth >= 600) return const EdgeInsets.all(16);
    return const EdgeInsets.all(12);
  }
}
