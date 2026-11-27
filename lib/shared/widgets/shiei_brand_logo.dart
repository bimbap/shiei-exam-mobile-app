import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Official horizontal brand lockup:
/// [Shiei Shield Logo] + "SHIEI" bold typography
class ShieiBrandLogo extends StatelessWidget {
  final double logoSize;
  final double fontSize;
  final MainAxisSize mainAxisSize;
  final MainAxisAlignment mainAxisAlignment;
  final bool? isDark;

  const ShieiBrandLogo({
    super.key,
    this.logoSize = 34,
    this.fontSize = 20,
    this.mainAxisSize = MainAxisSize.min,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final dark = isDark ?? AppTheme.isDark(context);
    final textColor = dark ? Colors.white : const Color(0xFF0F172A);

    return Row(
      mainAxisSize: mainAxisSize,
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Shiei Dual-Arc S Logo Mark
        Container(
          width: logoSize,
          height: logoSize,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(logoSize * 0.25),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(dark ? 0.35 : 0.14),
                blurRadius: logoSize * 0.28,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(logoSize * 0.25),
            child: Image.asset(
              'assets/images/shiei_logo.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(
                Icons.shield_rounded,
                size: logoSize * 0.75,
                color: AppTheme.primaryGlow,
              ),
            ),
          ),
        ),
        SizedBox(width: logoSize * 0.32),

        // Brand Typography: Pure minimal "SHIEI"
        Text(
          'SHIEI',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.2,
            color: textColor,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}
