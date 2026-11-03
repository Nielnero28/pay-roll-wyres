# Wyres Payroll Desk (Supabase version)

Static site (`index.html`) + Supabase (Postgres database and logins).
Data is shared, so every device and both users see the same records.

## Setup
1. Create a Supabase project. Run `supabase-schema.sql` in the SQL Editor.
2. Authentication > Users: add the Admin and Secretary (tick Auto Confirm). Turn off public sign-ups.
3. Run the two commented `insert into public.profiles ...` lines at the bottom of the SQL file (with the real emails).
4. In `index.html`, replace `PASTE_YOUR_SUPABASE_PROJECT_URL` and `PASTE_YOUR_SUPABASE_ANON_KEY`
   (Supabase > Project Settings > API). Use the anon/public key only. Never the service_role key.

## Deploy on Vercel
Push these files to the TOP LEVEL of a GitHub repository (index.html must not be inside a subfolder).
Vercel: Add New > Project > import the repo > Framework Preset "Other" > Deploy.

## Keeping devices in sync
The app re-reads the database when you return to the tab and every 30 seconds (when you are not typing).
The Refresh button does it on demand.
