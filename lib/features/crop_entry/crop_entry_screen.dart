import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:image_picker/image_picker.dart';

import '../../core/models/captured_location.dart';
import '../../core/models/crop_config.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/grain_upload_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/pending_queue_service.dart';
import '../../core/services/sync_service.dart';
import '../../core/services/worker_profile_service.dart';
import '../../core/utils/bangla_numerals.dart';
import '../../core/utils/sample_id.dart';

class _CategoryState {
  File? photo;
  double? weightGm;
  String? textValue;
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
  final Map<String, TextEditingController> _fieldControllers = {};
  final _moistureController = TextEditingController();
  final _supplierController = TextEditingController();
  final _notesController = TextEditingController();

  CapturedLocation _location = CapturedLocation.notCaptured;
  bool _locationLoading = true;
  bool _submitting = false;
  WorkerProfile? _workerProfile;

  @override
  void initState() {
    super.initState();
    _entryId = generateEntryId(widget.crop.idPrefix);
    for (final category in widget.crop.categories) {
      _categoryStates[category.key] = _CategoryState();
      _fieldControllers[category.key] = TextEditingController();
    }
    _captureLocation();
    _loadWorkerProfile();
  }

  @override
  void dispose() {
    for (final c in _fieldControllers.values) {
      c.dispose();
    }
    _moistureController.dispose();
    _supplierController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadWorkerProfile() async {
    final workerId = AuthService().currentWorkerId;
    if (workerId == null) return;
    final profile = await WorkerProfileService().loadCached(workerId);
    if (!mounted) return;
    setState(() => _workerProfile = profile);
  }

  double? get _moistureValue => double.tryParse(_moistureController.text.trim());

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

  void _onFieldChanged(
    String categoryKey,
    CategoryFieldType fieldType,
    String value,
  ) {
    setState(() {
      final state = _categoryStates[categoryKey]!;
      final trimmed = value.trim();
      if (fieldType == CategoryFieldType.weight) {
        state.weightGm = trimmed.isEmpty ? null : double.tryParse(trimmed);
      } else {
        state.textValue = trimmed.isEmpty ? null : trimmed;
      }
    });
  }

  bool get _isValid {
    final whole = _categoryStates['whole'];
    if (whole == null || whole.photo == null || whole.weightGm == null) {
      return false;
    }
    for (final category in widget.crop.categories.where((c) => !c.mandatory)) {
      if (!category.pairedValidation) continue;
      final state = _categoryStates[category.key]!;
      final hasPhoto = state.photo != null;
      final hasValue = category.fieldType == CategoryFieldType.weight
          ? state.weightGm != null
          : state.textValue != null;
      if (hasPhoto != hasValue) return false; // paired rule
    }
    if (_moistureValue == null) return false;
    if (!_location.captured) return false;
    return true;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _buildSummaryText() {
    final crop = widget.crop;
    final wholeWeight = _categoryStates['whole']!.weightGm!;
    final date = toBanglaDigits(DateFormat('dd/MM/yyyy').format(DateTime.now()));
    final moistureDisplay = '${formatBanglaGrams(_moistureValue!)}%';
    final supplier = _supplierController.text.trim();

    final buffer = StringBuffer()..writeln(date);
    if (_workerProfile != null) {
      buffer.writeln('${_workerProfile!.name} (${_workerProfile!.designation})');
    }
    buffer
      ..writeln('সরবরাহকারী : $supplier')
      ..writeln()
      ..writeln(crop.summaryTitleBn)
      ..writeln()
      ..writeln('${crop.wholeWeightLabelBn} : ${formatBanglaGrams(wholeWeight)} গ্রাম')
      ..writeln('$moistureLabelBn : $moistureDisplay');

    for (final category in crop.summaryPercentageCategories) {
      final weight = _categoryStates[category.key]?.weightGm;
      final percentText = weight == null
          ? '${toBanglaDigits('0')}%'
          : formatBanglaPercent((weight / wholeWeight) * 100);
      buffer.writeln('${category.labelBn} : $percentText');
    }

    return buffer.toString().trimRight();
  }

  Future<void> _onSubmitPressed() async {
    if (!_isValid || _submitting) return;
    final summary = _buildSummaryText();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _SummaryDialog(
        summaryText: summary,
        onConfirm: () {
          Navigator.of(context).pop();
          _submit();
        },
      ),
    );
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
        textValue: entry.value.textValue,
        photoFile: entry.value.photo,
      );
      pendingCategories[entry.key] = PendingCategoryData(
        weightGm: entry.value.weightGm,
        textValue: entry.value.textValue,
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
          moisture: _moistureValue,
          supplier: _supplierController.text,
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
          moisture: _moistureValue,
          supplier: _supplierController.text,
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
      appBar: AppBar(title: Text('${widget.crop.bilingualDisplayName} Sample')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final category in widget.crop.categories) ...[
            _CategoryTile(
              label: category.bilingualLabel,
              mandatory: category.mandatory,
              fieldType: category.fieldType,
              photo: _categoryStates[category.key]!.photo,
              fieldController: _fieldControllers[category.key]!,
              onCapture: () => _capturePhoto(category.key),
              onRetake: () => _retakePhoto(category.key),
              onFieldChanged: (v) =>
                  _onFieldChanged(category.key, category.fieldType, v),
            ),
            const SizedBox(height: 12),
          ],
          const Text(
            'Supplier(সরবরাহকারী)',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _supplierController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Supplier name',
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'Moisture($moistureLabelBn)',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              const Chip(
                label: Text('Required', style: TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _moistureController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'e.g. 13.5',
              isDense: true,
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
            onPressed: _isValid && !_submitting ? _onSubmitPressed : null,
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
                'Whole photo + weight, Moisture, and Location are required. '
                'Any other weight category needs both photo and weight, or neither.',
                style: TextStyle(color: Colors.red, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryDialog extends StatelessWidget {
  final String summaryText;
  final VoidCallback onConfirm;

  const _SummaryDialog({required this.summaryText, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Review Summary')),
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
            tooltip: 'Copy',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: summaryText));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Copied.')));
            },
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SelectableText(
          summaryText,
          style: const TextStyle(fontSize: 15, height: 1.5),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Continue Editing'),
        ),
        ElevatedButton(onPressed: onConfirm, child: const Text('Confirm')),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final String label;
  final bool mandatory;
  final CategoryFieldType fieldType;
  final File? photo;
  final TextEditingController fieldController;
  final VoidCallback onCapture;
  final VoidCallback onRetake;
  final ValueChanged<String> onFieldChanged;

  const _CategoryTile({
    required this.label,
    required this.mandatory,
    required this.fieldType,
    required this.photo,
    required this.fieldController,
    required this.onCapture,
    required this.onRetake,
    required this.onFieldChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isWeight = fieldType == CategoryFieldType.weight;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
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
              controller: fieldController,
              keyboardType: isWeight
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              onChanged: onFieldChanged,
              decoration: InputDecoration(
                labelText: isWeight ? 'Weight (gm)' : 'Details',
                border: const OutlineInputBorder(),
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
      text = 'Location unavailable — required, please retry';
    }

    return Row(
      children: [
        Icon(
          location.captured ? Icons.location_on : Icons.location_off,
          size: 18,
          color: location.captured ? Colors.green : Colors.red,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: location.captured || loading ? null : Colors.red,
            ),
          ),
        ),
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
