import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/models/crop_config.dart';
import 'core/services/auth_service.dart';
import 'core/services/pending_queue_service.dart';
import 'core/services/worker_profile_service.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/profile_setup_screen.dart';
import 'features/crop_entry/crop_entry_screen.dart';
import 'features/pending/pending_submissions_screen.dart';
import 'firebase_options.dart';

void main() {
  runApp(const IFarmerApp());
}

/// After a worker is authenticated (either a restored session on app start,
/// or a fresh login), decide whether they land on Home or need to fill in
/// their profile first. Shared by SplashScreen and LoginScreen so there's
/// one place that knows this rule.
Future<void> navigateAfterAuth(BuildContext context) async {
  final workerId = AuthService().currentWorkerId!;
  final profileService = WorkerProfileService();

  var profile = await profileService.loadCached(workerId);
  if (profile == null) {
    try {
      profile = await profileService.fetchFromFirestore(workerId);
      if (profile != null) {
        await profileService.cacheLocally(profile);
      }
    } catch (e) {
      debugPrint('Could not fetch worker profile: $e');
    }
  }

  if (!context.mounted) return;
  Navigator.of(context).pushReplacement(
    MaterialPageRoute(
      builder: (_) =>
          profile != null ? const HomeScreen() : const ProfileSetupScreen(),
    ),
  );
}

class IFarmerApp extends StatelessWidget {
  const IFarmerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedGreen = Color(0xFF2E7D32);

    return MaterialApp(
      title: 'iFarmer Grain Quality Collector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedGreen,
          brightness: Brightness.light,
        ).copyWith(surface: Colors.white),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: seedGreen,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: seedGreen,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(64),
            textStyle: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      // Non-fatal: the app still works offline; sync will retry auth later.
      debugPrint('Firebase init failed: $e');
    }

    if (!mounted) return;

    if (FirebaseAuth.instance.currentUser == null) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    } else {
      await navigateAfterAuth(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FractionallySizedBox(
              widthFactor: 0.45,
              child: Image.asset('assets/images/logo.png'),
            ),
            const SizedBox(height: 24),
            const Text(
              'iFarmer Grain Quality Collector',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2E7D32),
              ),
            ),
            const SizedBox(height: 32),
            if (_errorMessage == null)
              const CircularProgressIndicator(color: Color(0xFF2E7D32))
            else
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _pendingQueue = PendingQueueService();
  final _authService = AuthService();
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _refreshPendingCount();
  }

  Future<void> _refreshPendingCount() async {
    try {
      final entries = await _pendingQueue.loadAll();
      if (!mounted) return;
      setState(() => _pendingCount = entries.length);
    } catch (e) {
      debugPrint('Could not read pending queue: $e');
    }
  }

  Future<void> _openCrop(CropConfig crop) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => CropEntryScreen(crop: crop)));
    _refreshPendingCount();
  }

  Future<void> _openPending() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PendingSubmissionsScreen()));
    _refreshPendingCount();
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _authService.signOut();
    await WorkerProfileService().clearCache();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('iFarmer Grain Quality Collector'),
        actions: [
          IconButton(
            icon: Badge(
              label: Text('$_pendingCount'),
              isLabelVisible: _pendingCount > 0,
              child: const Icon(Icons.pending_actions),
            ),
            tooltip: 'Pending Submissions',
            onPressed: _openPending,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: _logout,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/logo.png', height: 96),
            const SizedBox(height: 16),
            const Text(
              'Select Crop Type',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.grass),
              label: Text(CropCatalog.paddy.bilingualDisplayName),
              onPressed: () => _openCrop(CropCatalog.paddy),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.eco),
              label: Text(CropCatalog.maize.bilingualDisplayName),
              onPressed: () => _openCrop(CropCatalog.maize),
            ),
          ],
        ),
      ),
    );
  }
}
