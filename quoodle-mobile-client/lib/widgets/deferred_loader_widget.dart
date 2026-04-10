import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A widget that defers loading of heavy widgets to improve initial render performance.
/// Shows a skeleton/placeholder while the deferred widget is being loaded.
class DeferredLoader extends StatefulWidget {
  final Widget Function() builder;
  final Duration delay;
  final Widget? placeholder;

  const DeferredLoader({
    super.key,
    required this.builder,
    this.delay = const Duration(milliseconds: 600),
    this.placeholder,
  });

  @override
  State<DeferredLoader> createState() => _DeferredLoaderState();
}

class _DeferredLoaderState extends State<DeferredLoader> {
  late Future<void> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = Future.delayed(widget.delay);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return widget.placeholder ?? _buildSkeletonPlaceholder();
        }
        return widget.builder();
      },
    );
  }

  Widget _buildSkeletonPlaceholder() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Center(
        child: SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor:
                AlwaysStoppedAnimation<Color>(AppTheme.primary.withAlpha(128)),
          ),
        ),
      ),
    );
  }
}
