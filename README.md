# Laundry App

Flutter client for the single-store laundry application.

## Local development

The app uses the linked hosted Supabase project by default. The local run command
below overrides that configuration with the local Supabase URL and key.

Start the local Supabase stack from this directory:

```powershell
npx supabase start
npx supabase db reset
```

Apply the migrations to the linked hosted Supabase project before testing real
Google customers and the laundry catalog:

```powershell
npx supabase link --project-ref osnblefzulmsuthhuswl
npx supabase db push
```

The latest migration provisions Google-authenticated customers and seeds the
initial active services, item types, units, and prices. The Flutter app now
reads this catalog from Supabase instead of using demo prices.

This applies the checked-in schema baseline, security/order migrations, and a development-only catalog seed. The seed contains no customer records.

Run the app against local Supabase on the desktop:

```powershell
flutter run `
	--dart-define=SUPABASE_URL=http://127.0.0.1:54321 `
	--dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_LOCAL_PUBLISHABLE_KEY
```

Get the local publishable key from `npx supabase status`. For an Android emulator, use `http://10.0.2.2:54321` as the URL. Do not use a service-role or secret key in the Flutter app.

For an Android emulator to load MB Bank transfer details from the local Laravel site, keep `php artisan serve` running on the host at port 8000. The debug launch uses `http://10.0.2.2:8000/api/v1/payment-config`. On a physical phone, pass `--dart-define=PAYMENT_CONFIG_URL=http://<computer-LAN-IP>:8000/api/v1/payment-config` and make the Laravel server reachable on the LAN. Restart the app after changing a `--dart-define` value.

Staff sign in through the deployed Laravel API at `https://sky-laundry.vercel.app/api/v1/` using the same email and password as the web account. Laravel returns a revocable bearer token; the app stores it with secure storage and sends it to staff order and booking endpoints. For local development, override the API with `--dart-define=STAFF_API_BASE_URL=http://10.0.2.2:8000/api/v1/` on an Android emulator, `http://127.0.0.1:8000/api/v1/` on desktop, or the computer's LAN IP on a physical phone. The account and linked employee profile must both be active. Customer sign-in remains on Supabase.

Customer sign-in and registration use Supabase phone OTP. Configure an SMS provider in the hosted project's Auth settings before expecting production SMS delivery. New customer profiles are created or linked only after Supabase confirms the phone number. Staff and manager identities must be provisioned and linked by a trusted administrator; self-service signup cannot grant staff roles.

## Checks

```powershell
flutter test
flutter analyze
npx supabase test db --local
npx supabase db advisors --local --type security
```

The production database schema is represented by the baseline migration. Apply later migrations to production only after review and a deployment window; the checked-in RLS migration intentionally restricts the existing broad client grants.
