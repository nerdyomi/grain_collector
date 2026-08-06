import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/worker_profile_service.dart';
import '../../main.dart' show HomeScreen;

/// Shown once, right after a worker's very first successful login - name
/// and designation(পদবি) are then cached/stored so this never appears again
/// for that worker.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _authService = AuthService();
  final _profileService = WorkerProfileService();
  final _nameController = TextEditingController();
  final _designationController = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _designationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final designation = _designationController.text.trim();
    if (name.isEmpty || designation.isEmpty) {
      setState(() => _error = 'Enter your name and designation.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final workerId = _authService.currentWorkerId!;
      await _profileService.save(
        WorkerProfile(workerId: workerId, name: name, designation: designation),
      );
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not save. Check your connection and try again.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your Details')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Please enter your name and designation. You will only need to do this once.',
                style: TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _designationController,
                decoration: const InputDecoration(
                  labelText: 'Designation(পদবি)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _submitting ? null : _save,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
