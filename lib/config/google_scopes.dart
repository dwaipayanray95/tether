/// Single source of truth for Google OAuth scopes requested by the app.
///
/// All scopes are requested together during the sign-in button press
/// (see AuthService.signInWithGoogle), since Android requires
/// authorizeScopes() to be initiated from a real user interaction.
///
/// To add a new Google API/scope in the future: add it to [all] here.
/// Existing signed-in users won't have it granted yet — MainShell's
/// scope validation will detect the gap and sign them out so they
/// re-authenticate and grant the new scope on next login.
class GoogleScopes {
  static const List<String> basic = [
    'email',
    'profile',
  ];

  static const List<String> drive = [
    'https://www.googleapis.com/auth/drive.file',
    'https://www.googleapis.com/auth/drive.appdata',
  ];

  static const List<String> all = [
    ...basic,
    ...drive,
  ];
}
