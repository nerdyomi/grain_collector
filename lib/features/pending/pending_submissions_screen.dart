import 'package:flutter/material.dart';

import '../../core/services/grain_upload_service.dart';
import '../../core/services/pending_queue_service.dart';
import '../../core/services/sync_service.dart';

class PendingSubmissionsScreen extends StatefulWidget {
  const PendingSubmissionsScreen({super.key});

  @override
  State<PendingSubmissionsScreen> createState() =>
      _PendingSubmissionsScreenState();
}

class _PendingSubmissionsScreenState extends State<PendingSubmissionsScreen> {
  final _queue = PendingQueueService();
  late final _sync = SyncService(queue: _queue, uploader: GrainUploadService());

  List<PendingEntry> _entries = [];
  bool _loading = true;
  String? _loadError;
  final Set<String> _retrying = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final entries = await _queue.loadAll();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _retry(String entryId) async {
    setState(() => _retrying.add(entryId));
    final success = await _sync.retryOne(entryId);
    if (!mounted) return;
    setState(() => _retrying.remove(entryId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Uploaded successfully.' : 'Still failing — will keep retrying.'),
      ),
    );
    _load();
  }

  Future<void> _delete(String entryId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete submission?'),
        content: const Text(
          'This will permanently delete this pending submission and its local photos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _queue.remove(entryId);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Submissions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Retry all',
            onPressed: () async {
              await _sync.retryAll();
              _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Could not load pending submissions:\n$_loadError'),
                    const SizedBox(height: 16),
                    ElevatedButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          : _entries.isEmpty
          ? const Center(child: Text('No pending submissions.'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final entry = _entries[index];
                  final isRetrying = _retrying.contains(entry.entryId);
                  return Card(
                    child: ListTile(
                      title: Text('${entry.cropType.toUpperCase()} · ${entry.entryId}'),
                      subtitle: Text(
                        'Created: ${entry.createdAt}\n'
                        'Retries: ${entry.retryCount}'
                        '${entry.lastError != null ? '\nError: ${entry.lastError}' : ''}',
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isRetrying)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            IconButton(
                              icon: const Icon(Icons.sync),
                              onPressed: () => _retry(entry.entryId),
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(entry.entryId),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
