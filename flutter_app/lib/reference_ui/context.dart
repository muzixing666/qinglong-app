// Adapter for the FlClash UI components. See UPSTREAM.md and the bundled license.
import 'package:flutter/material.dart';

extension ReferenceContext on BuildContext {
  ColorScheme get colorScheme => Theme.of(this).colorScheme;
  bool get disableAnimations => MediaQuery.disableAnimationsOf(this);
  Duration motionDuration(Duration value) =>
      disableAnimations ? Duration.zero : value;
}
