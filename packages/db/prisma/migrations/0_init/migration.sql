-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateTable
CREATE TABLE "public"."profiles" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "hr_threshold_bpm" INTEGER NOT NULL DEFAULT 100,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "profiles_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."workout_sessions" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "started_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "ended_at" TIMESTAMP(3),
    "source" TEXT NOT NULL DEFAULT 'watch',
    "active" BOOLEAN NOT NULL DEFAULT true,

    CONSTRAINT "workout_sessions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."hr_samples" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "session_id" TEXT NOT NULL,
    "bpm" INTEGER NOT NULL,
    "ts" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "source" TEXT NOT NULL DEFAULT 'watch',

    CONSTRAINT "hr_samples_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."hr_status" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "bpm" INTEGER NOT NULL,
    "threshold_bpm" INTEGER NOT NULL,
    "hr_ok" BOOLEAN NOT NULL,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "hr_status_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."github_accounts" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "github_user_id" INTEGER NOT NULL,
    "username" TEXT NOT NULL,

    CONSTRAINT "github_accounts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."github_tokens" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "encrypted_access_token" TEXT NOT NULL,
    "scopes" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "github_tokens_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."gate_repos" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "owner" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "user_key" TEXT NOT NULL,
    "signal_ref" TEXT NOT NULL,
    "github_app_installation_id" INTEGER,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "active_session_id" TEXT,
    "bootstrap_version" INTEGER NOT NULL DEFAULT 1,
    "signer_key_version" INTEGER NOT NULL DEFAULT 1,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "gate_repos_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."hr_buckets" (
    "id" TEXT NOT NULL,
    "session_id" TEXT NOT NULL,
    "bucket_start" TIMESTAMP(3) NOT NULL,
    "bucket_end" TIMESTAMP(3) NOT NULL,
    "min_bpm" INTEGER NOT NULL,
    "max_bpm" INTEGER NOT NULL,
    "avg_bpm" INTEGER NOT NULL,
    "sample_count" INTEGER NOT NULL,
    "time_above_threshold_secs" INTEGER NOT NULL,
    "threshold_bpm" INTEGER NOT NULL,

    CONSTRAINT "hr_buckets_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."workout_summaries" (
    "id" TEXT NOT NULL,
    "session_id" TEXT NOT NULL,
    "duration_secs" INTEGER NOT NULL,
    "avg_bpm" INTEGER NOT NULL,
    "max_bpm" INTEGER NOT NULL,
    "min_bpm" INTEGER NOT NULL,
    "time_above_threshold_secs" INTEGER NOT NULL,
    "time_below_threshold_secs" INTEGER NOT NULL,
    "threshold_bpm" INTEGER NOT NULL,
    "total_samples" INTEGER NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "workout_summaries_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "public"."session_commits" (
    "id" TEXT NOT NULL,
    "session_id" TEXT NOT NULL,
    "repo_owner" TEXT NOT NULL,
    "repo_name" TEXT NOT NULL,
    "commit_sha" TEXT NOT NULL,
    "commit_msg" TEXT NOT NULL,
    "lines_added" INTEGER,
    "lines_removed" INTEGER,
    "committed_at" TIMESTAMP(3) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "session_commits_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "profiles_user_id_key" ON "public"."profiles"("user_id");

-- CreateIndex
CREATE INDEX "workout_sessions_user_id_active_idx" ON "public"."workout_sessions"("user_id", "active");

-- CreateIndex
CREATE INDEX "workout_sessions_user_id_started_at_idx" ON "public"."workout_sessions"("user_id", "started_at");

-- CreateIndex
CREATE INDEX "hr_samples_user_id_ts_idx" ON "public"."hr_samples"("user_id", "ts");

-- CreateIndex
CREATE INDEX "hr_samples_session_id_idx" ON "public"."hr_samples"("session_id");

-- CreateIndex
CREATE UNIQUE INDEX "hr_status_user_id_key" ON "public"."hr_status"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "github_accounts_user_id_key" ON "public"."github_accounts"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "github_tokens_user_id_key" ON "public"."github_tokens"("user_id");

-- CreateIndex
CREATE INDEX "gate_repos_user_id_active_idx" ON "public"."gate_repos"("user_id", "active");

-- CreateIndex
CREATE INDEX "gate_repos_active_session_id_idx" ON "public"."gate_repos"("active_session_id");

-- CreateIndex
CREATE UNIQUE INDEX "gate_repos_owner_name_key" ON "public"."gate_repos"("owner", "name");

-- CreateIndex
CREATE INDEX "hr_buckets_session_id_bucket_start_idx" ON "public"."hr_buckets"("session_id", "bucket_start");

-- CreateIndex
CREATE UNIQUE INDEX "workout_summaries_session_id_key" ON "public"."workout_summaries"("session_id");

-- CreateIndex
CREATE INDEX "session_commits_session_id_idx" ON "public"."session_commits"("session_id");

-- CreateIndex
CREATE UNIQUE INDEX "session_commits_session_id_commit_sha_key" ON "public"."session_commits"("session_id", "commit_sha");

-- AddForeignKey
ALTER TABLE "public"."workout_sessions" ADD CONSTRAINT "workout_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("user_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."hr_samples" ADD CONSTRAINT "hr_samples_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("user_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."hr_samples" ADD CONSTRAINT "hr_samples_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."workout_sessions"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."hr_status" ADD CONSTRAINT "hr_status_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("user_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."github_accounts" ADD CONSTRAINT "github_accounts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("user_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."github_tokens" ADD CONSTRAINT "github_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("user_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."gate_repos" ADD CONSTRAINT "gate_repos_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("user_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."gate_repos" ADD CONSTRAINT "gate_repos_active_session_id_fkey" FOREIGN KEY ("active_session_id") REFERENCES "public"."workout_sessions"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."hr_buckets" ADD CONSTRAINT "hr_buckets_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."workout_sessions"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."workout_summaries" ADD CONSTRAINT "workout_summaries_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."workout_sessions"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."session_commits" ADD CONSTRAINT "session_commits_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."workout_sessions"("id") ON DELETE CASCADE ON UPDATE CASCADE;

┌─────────────────────────────────────────────────────────┐
│  Update available 5.22.0 -> 7.1.0                       │
│                                                         │
│  This is a major update - please follow the guide at    │
│  https://pris.ly/d/major-version-upgrade                │
│                                                         │
│  Run the following to update                            │
│    npm i --save-dev prisma@latest                       │
│    npm i @prisma/client@latest                          │
└─────────────────────────────────────────────────────────┘
