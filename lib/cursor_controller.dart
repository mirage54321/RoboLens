import 'package:flutter/material.dart';

class CursorController extends ChangeNotifier {
  CursorController._();
  static final CursorController instance = CursorController._();

  Offset? position;
  bool hovering = false;
  bool visible = false;

  void updatePosition(Offset pos) {
    position = pos;
    if (!visible) visible = true;
    notifyListeners();
  }

  void hide() {
    visible = false;
    notifyListeners();
  }

  void setHovering(bool value) {
    if (hovering == value) return;
    hovering = value;
    notifyListeners();
  }
}