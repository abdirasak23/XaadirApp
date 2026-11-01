import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class SupabaseConfig {
  // Your Supabase configuration - replace with your actual values
  static const String supabaseUrl = 'https://blxbqalbnfwimnwnaivp.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJseGJxYWxibmZ3aW1ud25haXZwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMxODkxMTQsImV4cCI6MjEwODc2NTExNH0.tcoZSdbfSZPkt8xz2SWAaqDIKdC3qMF6XSVXfgHpxDo';


  /// Initialize Supabase
  static Future<void> initialize() async {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
        realtimeClientOptions: const RealtimeClientOptions(
          logLevel: RealtimeLogLevel.info,
        ),
        storageOptions: const StorageClientOptions(
          retryAttempts: 10,
        ),
      );

      debugPrint('✅ Supabase initialized successfully');
    } catch (error) {
      debugPrint('❌ Error initializing Supabase: $error');
      throw error;
    }
  }

  /// Get Supabase client instance
  static SupabaseClient get client => Supabase.instance.client;
}