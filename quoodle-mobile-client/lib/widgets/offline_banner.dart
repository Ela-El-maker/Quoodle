import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/offline_repository.dart';
import '../theme/app_colors.dart';

class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  late final OfflineRepository _repo;
  StreamSubscription<ConnectivityStatus>? _sub;
  ConnectivityStatus _status = ConnectivityStatus.unknown;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _repo = OfflineRepository(api: ApiService());
    _status = _repo.connectivityStatus;
    _sub = _repo.connectivityStream.listen((status) {
      if (!mounted) return;
      setState(() => _status = status);
    });
    _repo.checkConnectivity();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      _repo.checkConnectivity();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_status == ConnectivityStatus.online ||
        _status == ConnectivityStatus.unknown) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded,
              color: AppColors.textSecondary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Offline - showing cached data where available.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => _repo.checkConnectivity(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
