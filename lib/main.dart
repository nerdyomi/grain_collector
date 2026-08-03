import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/models/crop_config.dart';
import 'core/services/pending_queue_service.dart';
import 'features/crop_entry/crop_entry_screen.dart';
import 'features/pending/pending_submissions_screen.dart';
import 'firebase_options.dart';

void main() {
  runApp(const IFarmerApp());
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
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
    } catch (e) {
      // Non-fatal: the app still works offline; sync will retry auth later.
      debugPrint('Firebase init failed: $e');
    }

    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
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
              label: const Text('Paddy'),
              onPressed: () => _openCrop(CropCatalog.paddy),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.eco),
              label: const Text('Maize'),
              onPressed: () => _openCrop(CropCatalog.maize),
            ),
          ],
        ),
      ),
    );
  }
}
