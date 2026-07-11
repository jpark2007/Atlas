-- ============================================================
-- 0025_user_settings.sql — synced per-user settings (singleton row)
-- Canonical home for preferences that are about the USER, not the
-- device. Clients map their local @AppStorage keys to these columns
-- (Mac "tasks.defaultSpaceName" and iOS "defaultSpaceName" both map
-- to default_space_name). Device-specific state (hotkeys, window
-- geometry, session tokens, notification PERMISSION) stays local.
-- Idempotent; safe to re-run.
-- ============================================================

create table if not exists user_settings (
  user_id                     uuid primary key references auth.users on delete cascade,
  default_space_name          text,
  apple_calendar_default_space text,
  google_two_way_sync         boolean,
  text_scale                  float8,
  sidebar_mode                text,
  tasks_grouping              text,
  per_tab_docs_sync           boolean,
  -- Same JSON shape NotificationPrefs already encodes for @AppStorage
  -- on iOS; Mac (Task 14) reads/writes the identical blob.
  notification_prefs          jsonb,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now()
);

alter table user_settings enable row level security;

drop policy if exists "user_settings: owner access" on user_settings;
create policy "user_settings: owner access" on user_settings
  for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop trigger if exists user_settings_set_updated_at on user_settings;
create trigger user_settings_set_updated_at
  before update on user_settings
  for each row execute function public.set_updated_at();
