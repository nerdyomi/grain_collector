/// Supabase project used only for photo storage (Firestore/Auth stay on
/// Firebase). Using the REST API directly with the publishable key rather
/// than the full supabase_flutter SDK keeps this to one small service file
/// since we don't need Supabase's own auth/realtime features.
///
/// Values are supplied at build time via --dart-define-from-file=.env
/// (see .env.example for the required keys).
class SupabaseConfig {
  static const projectUrl = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const bucket = 'grain-samples';
}
