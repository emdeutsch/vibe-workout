/**
 * Core types for viberunner HR gating system
 */

// HR signal payload - stored in git ref as JSON
export interface HrSignalPayload {
  v: number; // Version (currently 1)
  user_key: string; // Stable user identifier
  session_id: string; // Current workout session ID (for commit tagging)
  hr_ok: boolean; // Whether HR is above threshold
  bpm: number; // Current heart rate BPM
  threshold_bpm: number; // User's configured threshold
  exp_unix: number; // Expiration timestamp (Unix seconds)
  nonce: string; // Random nonce for replay prevention
  sig: string; // Ed25519 signature (hex encoded)
}

// Payload without signature (for signing/verification)
export interface HrSignalPayloadUnsigned {
  v: number;
  user_key: string;
  session_id: string;
  hr_ok: boolean;
  bpm: number;
  threshold_bpm: number;
  exp_unix: number;
  nonce: string;
}

// Gate repo configuration stored in viberunner.config.json
export interface GateRepoConfig {
  version: number;
  user_key: string;
  signal_ref_pattern: string; // e.g., "refs/viberunner/hr/{user_key}"
  payload_filename: string; // e.g., "hr-signal.json"
  public_key: string; // Ed25519 public key (hex)
  public_key_version: number;
  ttl_seconds: number; // Expected TTL (10-20 seconds)
}

// Verification result
export interface VerifyResult {
  valid: boolean;
  reason?: string;
  payload?: HrSignalPayload;
}

// API request/response types
export interface UpdateThresholdRequest {
  hr_threshold_bpm: number;
}

export interface StartWorkoutRequest {
  source?: 'watch' | 'ble';
  repo_ids?: string[]; // Gate repo IDs to activate for this workout
}

export interface StartWorkoutResponse {
  session_id: string;
  started_at: string;
  selected_repos?: Array<{ id: string; owner: string; name: string }>;
}

export interface IngestHrSampleRequest {
  session_id: string;
  bpm: number;
  ts?: string; // ISO timestamp, defaults to now
  source?: 'watch' | 'ble';
}

export interface HrStatusResponse {
  bpm: number;
  threshold_bpm: number;
  hr_ok: boolean;
  expires_at: string;
  tools_unlocked: boolean;
}

export interface CreateGateRepoRequest {
  name: string;
  description?: string;
  private?: boolean;
  org?: string; // Organization login (if creating in org)

  // Repository features
  has_issues?: boolean;
  has_wiki?: boolean;
  has_projects?: boolean;

  // Templates
  license_template?: string; // e.g., "mit", "apache-2.0"
  gitignore_template?: string; // e.g., "Node", "Swift"

  // Merge settings
  allow_squash_merge?: boolean;
  allow_merge_commit?: boolean;
  allow_rebase_merge?: boolean;
  delete_branch_on_merge?: boolean;

  // Auto-install GitHub App after creation
  auto_install_app?: boolean;
}

// GitHub organization
export interface GitHubOrg {
  id: number;
  login: string;
  avatar_url: string;
}

export interface GitHubOrgsResponse {
  orgs: GitHubOrg[];
}

export interface CreateGateRepoResponse {
  id: string;
  owner: string;
  name: string;
  user_key: string;
  signal_ref: string;
  html_url: string;
  needs_app_install: boolean;
  install_url?: string; // GitHub App installation URL (if auto_install_app was requested)
}

export interface GateRepoResponse {
  id: string;
  owner: string;
  name: string;
  user_key: string;
  signal_ref: string;
  active: boolean;
  github_app_installed: boolean;
  created_at: string;
}

export interface ProfileResponse {
  user_id: string;
  hr_threshold_bpm: number;
  github_connected: boolean;
  github_username?: string;
}

// GitHub OAuth types
export interface GitHubOAuthStartResponse {
  authorization_url: string;
  state: string;
}

export interface GitHubOAuthCallbackRequest {
  code: string;
  state: string;
}

// Constants
export const SIGNAL_VERSION = 1;
export const DEFAULT_TTL_SECONDS = 15;
export const PAYLOAD_FILENAME = 'hr-signal.json';
export const SIGNAL_REF_PATTERN = 'refs/viberunner/hr/{user_key}';

// Helper to build signal ref from user_key
export function buildSignalRef(userKey: string): string {
  return `refs/viberunner/hr/${userKey}`;
}
