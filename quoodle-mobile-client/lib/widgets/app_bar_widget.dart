import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool showBack;
  final PreferredSizeWidget? bottom;

  const GlassAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.showBack = false,
    this.bottom,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(bottom != null ? 56 + bottom!.preferredSize.height : 56);

  @override
  Widget build(BuildContext context) {
    final actionWidgets = actions ?? const <Widget>[];

    return AppBar(
      automaticallyImplyLeading: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 55,
      bottom: bottom,
      leadingWidth: showBack ? 48 : (leading != null ? 56 : 20),
      leading: showBack
          ? IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 18,
                color: AppTheme.textPrimary,
              ),
              onPressed: () => Navigator.maybePop(context),
            )
          : leading != null
              ? Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: leading,
                )
              : null,
      titleSpacing: showBack || leading != null ? 0 : 16,
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.ibmPlexSans(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      ),
      actions: actionWidgets,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.glassSurface,
              border: const Border(
                bottom: BorderSide(color: AppTheme.border, width: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
