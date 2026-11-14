// Where Supabase redirects after the magic link is clicked (set via --dart-define).
const String kEmailRedirectUrl = String.fromEnvironment('EMAIL_REDIRECT_URL', defaultValue: 'http://localhost:5000');
