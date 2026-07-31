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

    // Guarded: a snackbar is presentation and must never be able to break the
    // flow that raised it. This one is shown immediately after database
    // writes, where a render failure previously turned a COMMITTED save into a
    // reported failure and sent the operator back to repeat it.
    try {
      Get.rawSnackbar(
        title: title,
        message: message,
        backgroundColor: background,
        duration: const Duration(seconds: 2),
        snackPosition: SnackPosition.TOP,
        margin: const EdgeInsets.all(12),
        borderRadius: 10,
      );
    } catch (_) {
      _isShowing = false;
      return;
    }

    Future.delayed(const Duration(seconds: 2), () {
      _isShowing = false;
    });
  }
}
