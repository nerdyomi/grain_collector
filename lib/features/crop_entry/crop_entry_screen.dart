import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models/captured_location.dart';
import '../../core/models/crop_config.dart';
import '../../core/services/grain_upload_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/pending_queue_service.dart';
import '../../core/services/sync_service.dart';
import '../../core/utils/sample_id.dart';

class _CategoryState {
  File? photo;
  double? weightGm;
}

class CropEntryScreen extends StatefulWidget {
  final CropConfig crop;

  const CropEntryScreen({super.key, required this.crop});

  @override
  State<CropEntryScreen> createState() => _CropEntryScreenState();
}

class _CropEntryScreenState extends State<CropEntryScreen> {
  late final String _entryId;
  final _picker = ImagePicker();
  final _locationService = LocationService();
  final _uploadService = GrainUploadService();
  final _pendingQueue = PendingQueueService();
  late final _syncService = SyncService(
    queue: _pendingQueue,
    uploader: _uploadService,
  );

  final Map<String, _CategoryState> _categoryStates = {};
  final Map<String, TextEditingController> _weightControllers = {};
  final _moistureController = TextEditingController();
  final _notesController = TextEditingController();

  CapturedLocation _location = CapturedLocation.notCaptured;
  bool _locationLoading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _entryId = generateEntryId(widget.crop.idPrefix);
    for (final category in widget.crop.categories) {
      _categoryStates[category.key] = _CategoryState();
      _weightControllers[category.key] = TextEditingController();
    }
    _captureLocation();
  }

  @override
  void dispose() {
    for (final c in _weightControllers.values) {
      c.dispose();
    }
    _moistureController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _captureLocation() async {
    setState(() => _locationLoading = true);
    final result = await _locationService.captureCurrentLocation();
    if (!mounted) return;
    setState(() {
      _location = result;
      _locationLoading = false;
    });
  }

  Future<void> _capturePhoto(String categoryKey) async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null) return;
      final permanentFile = await _pendingQueue.persistPhoto(
        File(picked.path),
        _entryId,
        categoryKey,
      );
      setState(() {
        _categoryStates[categoryKey]!.photo = permanentFile;
      });
    } catch (e) {
      _showMessage('Could not open camera. Check camera permission.');
    }
  }

  void _retakePhoto(String categoryKey) {
    setState(() {
      _categoryStates[categoryKey]!.photo = null;
    });
    _capturePhoto(categoryKey);
  }

  void _onWeightChanged(String categoryKey, String value) {
    final parsed = double.tryParse(value.trim());
    setState(() {
      _categoryStates[categoryKey]!.weightGm = value.trim().isEmpty
          ? null
          : parsed;
    });
  }

  bool get _isValid {
    final whole = _categoryStates['whole'];
    if (whole == null || whole.photo == null || whole.weightGm == null) {
      return false;
    }
    for (final category in widget.crop.categories.where((c) => !c.mandatory)) {
      final state = _categoryStates[category.key]!;
      final hasPhoto = state.photo != null;
      final hasWeight = state.weightGm != null;
      if (hasPhoto != hasWeight) return false; // paired rule
    }
    return true;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    if (!_isValid || _submitting) return;
    setState(() => _submitting = true);

    final createdAt = DateTime.now();
    final connectivity = await Connectivity().checkConnectivity();
    final hasConnectivity = !connectivity.contains(
      ConnectivityResult.none,
    );

    final categoriesForUpload = <String, CategoryUploadData>{};
    final pendingCategories = <String, PendingCategoryData>{};
    for (final entry in _categoryStates.entries) {
      categoriesForUpload[entry.key] = CategoryUploadData(
        weightGm: entry.value.weightGm,
        photoFile: entry.value.photo,
      );
      pendingCategories[entry.key] = PendingCategoryData(
        weightGm: entry.value.weightGm,
        localPhotoPath: entry.value.photo?.path,
      );
    }

    var uploaded = false;
    String? error;

    if (hasConnectivity) {
      try {
        await _uploadService.submitEntry(
          crop: widget.crop,
          entryId: _entryId,
          categories: categoriesForUpload,
          moisture: _moistureController.text,
          notes: _notesController.text,
          location: _location,
          createdAtDevice: createdAt,
        );
        uploaded = true;
      } catch (e) {
        error = e.toString();
      }
    }

    if (!uploaded) {
      await _pendingQueue.add(
        PendingEntry(
          entryId: _entryId,
          cropType: widget.crop.cropType,
          categories: pendingCategories,
          moisture: _moistureController.text,
          notes: _notesController.text,
          location: _location,
          createdAt: createdAt,
          lastError: error,
        ),
      );
      // Best-effort immediate retry kicks off in the background so a
      // flaky-but-actually-working connection doesn't leave this stuck.
      unawaited(_syncService.retryOne(_entryId));
    }

    if (!mounted) return;
    setState(() => _submitting = false);

    _showMessage(
      uploaded
          ? 'Submitted successfully.'
          : 'Saved on device — will upload when online.',
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.crop.displayName} Sample')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final category in widget.crop.categories) ...[
            _CategoryTile(
              label: category.label,
              mandatory: category.mandatory,
              photo: _categoryStates[category.key]!.photo,
              weightController: _weightControllers[category.key]!,
              onCapture: () => _capturePhoto(category.key),
              onRetake: () => _retakePhoto(category.key),
              onWeightChanged: (v) => _onWeightChanged(category.key, v),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _moistureController,
            decoration: const InputDecoration(
              labelText: 'Moisture (optional)',
              border: OutlineInputBorder(),
              hintText: 'e.g. 13.5%',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Additional details (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          _LocationStatus(
            location: _location,
            loading: _locationLoading,
            onRetry: _captureLocation,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isValid && !_submitting ? _submit : null,
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Submit'),
          ),
          if (!_isValid)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Whole photo + weight are required. Any other category needs both photo and weight, or neither.',
                style: TextStyle(color: Colors.red, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final String label;
  final bool mandatory;
  final File? photo;
  final TextEditingController weightController;
  final VoidCallback onCapture;
  final VoidCallback onRetake;
  final ValueChanged<String> onWeightChanged;

  const _CategoryTile({
    required this.label,
    required this.mandatory,
    required this.photo,
    required this.weightController,
    required this.onCapture,
    required this.onRetake,
    required this.onWeightChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                if (mandatory)
                  const Chip(
                    label: Text('Required', style: TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  )
                else
                  const Chip(
                    label: Text('Optional', style: TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (photo != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      photo!,
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.camera_alt_outlined),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(
                      photo == null ? Icons.camera_alt : Icons.refresh,
                    ),
                    label: Text(photo == null ? 'Capture Photo' : 'Retake'),
                    onPressed: photo == null ? onCapture : onRetake,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: weightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: onWeightChanged,
              decoration: const InputDecoration(
                labelText: 'Weight (gm)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationStatus extends StatelessWidget {
  final CapturedLocation location;
  final bool loading;
  final VoidCallback onRetry;

  const _LocationStatus({
    required this.location,
    required this.loading,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    String text;
    if (loading) {
      text = 'Capturing location...';
    } else if (location.captured) {
      text =
          'Location captured (${location.latitude!.toStringAsFixed(5)}, '
          '${location.longitude!.toStringAsFixed(5)})'
          '${location.accuracy != null ? ' ±${location.accuracy!.toStringAsFixed(0)}m' : ''}';
    } else {
      text = 'Location unavailable';
    }

    return Row(
      children: [
        Icon(
          location.captured ? Icons.location_on : Icons.location_off,
          size: 18,
          color: location.captured ? Colors.green : Colors.grey,
        ),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        if (!loading)
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: onRetry,
            tooltip: 'Retry location',
          ),
      ],
    );
  }
}
