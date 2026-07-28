import 'package:flutter/material.dart';

/// Matches the original web app's `C` color object exactly (white + red theme).
class AppColors {
  static const bg = Color(0xFFFFFFFF);
  static const card = Color(0xFFFFFFFF);
  static const cardAlt = Color(0xFFFAFAFA);
  static const border = Color(0xFFE5E5E5);
  static const borderBright = Color(0xFFD0021B);
  static const red = Color(0xFFD0021B);
  static const redDim = Color(0xFFA00115);
  static const redGlow = Color(0xFFFF1A2E);
  static const redFaint = Color(0xFFFFE5E8);
  static const black = Color(0xFF000000);
  static const text = Color(0xFF1A1A1A);
  static const textDim = Color(0xFF666666);
  static const textMuted = Color(0xFF999999);
}

const List<String> kAssets = [
  'BOOM1000', 'BOOM900', 'BOOM600', 'BOOM500', 'BOOM300',
  'CRASH1000', 'CRASH900', 'CRASH600', 'CRASH500', 'CRASH300',
];

String shortAssetLabel(String a) =>
    a.replaceAll('BOOM', 'B').replaceAll('CRASH', 'C');
