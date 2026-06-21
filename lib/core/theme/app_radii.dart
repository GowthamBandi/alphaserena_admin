import 'package:flutter/widgets.dart';

/// Corner-radius tokens used across the app.
class AppRadii {
  AppRadii._();

  static const double sm = 14; // inputs, buttons, chips, tabs
  static const double md = 16; // primary buttons, dialogs
  static const double card = 18; // standard content cards
  static const double nav = 20; // floating bottom nav
  static const double lg = 22; // premium / gradient cards, overlays

  static const BorderRadius smR = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdR = BorderRadius.all(Radius.circular(md));
  static const BorderRadius cardR = BorderRadius.all(Radius.circular(card));
  static const BorderRadius navR = BorderRadius.all(Radius.circular(nav));
  static const BorderRadius lgR = BorderRadius.all(Radius.circular(lg));
}
