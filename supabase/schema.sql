-- ============================================================
-- My Salah App — Supabase Database Schema
-- Run this SQL in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================

-- 1. User profiles table
--    Supabase Auth handles the actual auth row (auth.users).
--    This table stores extra profile info (name, gender, age).
CREATE TABLE public.profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  name TEXT NOT NULL,
  gender TEXT DEFAULT 'Male',
  age TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Row Level Security: each user can only read/write their own row
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own profile"
  ON public.profiles
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- Auto-create a profile row when a user signs up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, name)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'name', 'User'));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- 2. Cloud prayer records (backup of local SQLite)
--    Matches the local sqflite prayer_records schema.
CREATE TABLE public.prayer_records (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  date DATE NOT NULL,
  prayer_name INTEGER NOT NULL,   -- PrayerName enum index (0=fajr … 4=isha)
  status INTEGER NOT NULL,        -- PrayerStatus enum index
  prayed_at TIMESTAMPTZ,
  synced_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, date, prayer_name)
);

ALTER TABLE public.prayer_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own records"
  ON public.prayer_records
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Index for fast queries by user + date range
CREATE INDEX idx_prayer_records_user_date
  ON public.prayer_records(user_id, date);


-- 3. OTP verifications table (used exclusively by the Edge Function)
--    The Edge Function uses the service_role key, so no RLS needed.
CREATE TABLE public.otp_verifications (
  id BIGSERIAL PRIMARY KEY,
  email TEXT NOT NULL,
  otp_hash TEXT NOT NULL,          -- SHA-256 hash of the OTP (never store raw)
  expires_at TIMESTAMPTZ NOT NULL,
  used BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Auto-clean old OTP records (optional but good practice)
-- Run this from a cron job or Supabase scheduled function:
-- DELETE FROM public.otp_verifications WHERE expires_at < NOW() - INTERVAL '1 hour';
