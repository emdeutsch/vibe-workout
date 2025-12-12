/**
 * Supabase Client for auth operations
 */

import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { getConfig } from '../config.js';

let supabaseAdmin: SupabaseClient | null = null;

/**
 * Get admin Supabase client (service role - bypasses RLS)
 * Use only for admin operations, not user-facing queries
 */
export function getSupabaseAdmin(): SupabaseClient {
  if (!supabaseAdmin) {
    const config = getConfig();
    supabaseAdmin = createClient(config.supabase.url, config.supabase.serviceRoleKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUrl: false,
      },
    });
  }
  return supabaseAdmin;
}

/**
 * Create a Supabase client for a specific user's JWT
 * This respects RLS policies
 */
export function getSupabaseClient(accessToken: string): SupabaseClient {
  const config = getConfig();
  return createClient(config.supabase.url, config.supabase.anonKey, {
    global: {
      headers: {
        Authorization: `Bearer ${accessToken}`,
      },
    },
    auth: {
      autoRefreshToken: false,
      persistSession: false,
      detectSessionInUrl: false,
    },
  });
}

/**
 * Verify a Supabase access token and return the user
 */
export async function verifyToken(accessToken: string) {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase.auth.getUser(accessToken);

  if (error || !data.user) {
    return null;
  }

  return data.user;
}
