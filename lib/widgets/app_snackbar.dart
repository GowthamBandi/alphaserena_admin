import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AppSnackbar {
  static bool _isShowing = false;

  static void show({
    required String title,
    required String message,
    Color background = Colors.black,
  }) {
    if (_isShowing) return;

    _isShowing = true;

    Get.rawSnackbar(
      title: title,
      message: message,
      backgroundColor: background,
      duration: const Duration(seconds: 2),
      snackPosition: SnackPosition.TOP,
      margin: const EdgeInsets.all(12),
      borderRadius: 10,
    );

    Future.delayed(const Duration(seconds: 2), () {
      _isShowing = false;
    });
  }
}
