import 'package:flutter/material.dart';

import '../../models/update_status.dart';
import '../../services/api_service.dart';

class UpdateListScreen extends StatefulWidget {
  const UpdateListScreen({super.key, required this.deviceId});

  final String deviceId;
  static const route = '/updates';

  @override
  State<UpdateListScreen> createState() => _UpdateListScreenState();
}

class _UpdateListScreenState extends State<UpdateListScreen> {
  final ApiService _api = ApiService();
  late Future<List<UpdateStatus>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.fetchUpdates(widget.deviceId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Updates')),
      body: FutureBuilder<List<UpdateStatus>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final updates = snapshot.data!;
          return ListView.builder(
            itemCount: updates.length,
            itemBuilder: (_, idx) {
              final u = updates[idx];
              return ListTile(
                title: Text(u.version ?? 'unknown'),
                subtitle: Text('Status: ${u.status ?? 'pending'}'),
                trailing: Text(u.lastUpdateAt ?? ''),
              );
            },
          );
        },
      ),
    );
  }
}
