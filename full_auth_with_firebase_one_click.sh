```bash
#!/bin/bash

################################################################################
# 🚀 Production-Ready Flutter & Firebase Authentication Bootstrapper
# Features:
# 1. Flutter project with dev/prod flavors
# 2. Firebase Authentication (email login, sign-up, password reset, email verification)
# 3. MVVM architecture with services
# 4. Firebase emulator support for local testing
# 5. GoRouter for navigation with auth state redirects
# 6. GitHub integration with CI/CD via GitHub Actions
# 7. Comprehensive error handling, loading states, and user feedback
# 8. Automated README generation
#
# Creates a secure authentication system with:
# - Sign In/Sign Up with email verification
# - Password reset and resend verification email
# - Secure storage for user credentials
# - User-friendly error messages and loading states
# - Dynamic navigation based on auth state
# - Firestore rules for user-specific data
# - CI/CD pipeline for automated builds and tests
################################################################################

# ---------------------------------------------
# ========   CONFIGURABLE SECTION   ==========
# ---------------------------------------------
COMPILE_SDK=34
MIN_SDK=21
TARGET_SDK=34
MIN_FLUTTER_VERSION="3.2.0"
DEPS=(
  "firebase_core: ^3.6.0"
  "firebase_auth: ^5.3.1"
  "cloud_firestore: ^5.4.4"
  "dio: ^5.7.0"
  "provider: ^6.1.2"
  "flutter_secure_storage: ^9.2.2"
  "go_router: ^14.2.8"
  "google_fonts: ^6.2.1"
)
FLUTTER_CMD="flutter"
FIREBASE_CMD="firebase"
GH_CMD="gh"

# ---------------------------------------------
# ===========   UTILITY FUNCTIONS   ===========
# ---------------------------------------------

log() { echo "📢 $1"; }
error() { echo "❌ $1"; exit 1; }
check_command() {
  command -v "$1" &> /dev/null || { echo "⚠️ $2 not installed. $3"; return 1; }
}
version_gte() {
  [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" == "$2" ]
}
replace_in_file() {
  sed -i "s|$1|$2|g" "$3" || error "Failed to update $3"
}

# ---------------------------------------------
# ===========   PREREQUISITES   ==============
# ---------------------------------------------

log "Checking prerequisites..."
check_command "$FLUTTER_CMD" "Flutter SDK" "Install from https://flutter.dev/docs/get-started/install" || error "Flutter SDK required."
FLUTTER_INSTALLED_VERSION=$($FLUTTER_CMD --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | tr -d '[:space:]' | head -n1)
[ -z "$FLUTTER_INSTALLED_VERSION" ] && error "Failed to detect Flutter version. Run 'flutter --version' to diagnose."
log "Detected Flutter version: $FLUTTER_INSTALLED_VERSION"
version_gte "$FLUTTER_INSTALLED_VERSION" "$MIN_FLUTTER_VERSION" || error "Flutter version >= $MIN_FLUTTER_VERSION required. Current: $FLUTTER_INSTALLED_VERSION. Update via 'flutter upgrade'."
check_command "$FIREBASE_CMD" "Firebase CLI" "Skipping Firebase setup. Install via 'npm install -g firebase-tools'."
FIREBASE_AVAILABLE=$?
check_command "$GH_CMD" "GitHub CLI" "Skipping GitHub integration. Install via 'gh' package manager."
GH_AVAILABLE=$?
check_command "git" "Git" "Git required for version control." || error "Git required."
check_command "code" "VS Code" "VS Code not found, project won't auto-open."
log "Prerequisites check complete."

# ---------------------------------------------
# ===========   ARGUMENT PARSING   ===========
# ---------------------------------------------
[ -z "$1" ] && error "Usage: $0 <project_name>"
PROJECT_NAME=$1
PROJECT_DIR="$PWD/$PROJECT_NAME"

# ---------------------------------------------
# =======   CREATE FLUTTER PROJECT   =========
# ---------------------------------------------

log "Creating Flutter project '$PROJECT_NAME'..."
$FLUTTER_CMD create --org com.example "$PROJECT_NAME" || error "Flutter project creation failed."
cd "$PROJECT_DIR" || error "Failed to access project directory."

# ---------------------------------------------
# ======   CONFIGURE pubspec.yaml   =========
# ---------------------------------------------

log "Configuring pubspec.yaml..."
mv pubspec.yaml pubspec.yaml.bak || error "Failed to backup pubspec.yaml."
cat <<EOF > pubspec.yaml
name: $PROJECT_NAME
description: A production-ready Flutter project with Firebase Authentication.
publish_to: 'none'
version: 1.0.0+1
environment:
  sdk: '>=3.2.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
EOF
for dep in "${DEPS[@]}"; do
  echo "  $dep" >> pubspec.yaml
done
cat <<EOF >> pubspec.yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
flutter:
  uses-material-design: true
EOF
$FLUTTER_CMD pub get || error "Failed to install dependencies."

# ---------------------------------------------
# ======   CREATE FOLDER STRUCTURE   =========
# ---------------------------------------------

log "Creating MVVM folder structure..."
mkdir -p lib/{core/{config,utils},data/{models,services},ui/{pages,viewmodels,widgets},routes}
cat <<EOF > lib/core/config/app_config.dart
class AppConfig {
  static const String appName = '$PROJECT_NAME';
  static const bool isDebug = bool.fromEnvironment('dart.vm.product') == false;
  static const bool useEmulator = bool.fromEnvironment('USE_EMULATOR', defaultValue: false);
}
EOF

# ---------------------------------------------
# ======   FIREBASE AUTH SETUP   ===========
# ---------------------------------------------

if [ $FIREBASE_AVAILABLE -eq 0 ]; then
  log "Setting up Firebase Authentication..."
  read -p "Enter Firebase project ID (or press Enter to skip): " FIREBASE_PROJECT_ID
  if [ -n "$FIREBASE_PROJECT_ID" ]; then
    $FIREBASE_CMD use "$FIREBASE_PROJECT_ID" --add --non-interactive || error "Firebase project init failed."
    $FIREBASE_CMD init firestore,auth,functions --project "$FIREBASE_PROJECT_ID" --non-interactive || error "Firebase init failed."
    cat <<EOF > firebase.json
{
  "firestore": {
    "rules": "firestore.rules",
    "indexes": "firestore.indexes.json"
  },
  "functions": {
    "source": "functions"
  },
  "emulators": {
    "auth": {
      "port": 9099
    },
    "firestore": {
      "port": 8080
    },
    "functions": {
      "port": 5001
    },
    "ui": {
      "enabled": true
    }
  }
}
EOF
    cat <<EOF > firestore.rules
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
EOF
  else
    log "Skipping Firebase setup (no project ID provided)."
  fi
else
  log "Skipping Firebase setup (Firebase CLI not installed)."
fi

# ---------------------------------------------
# ======   AUTH UI & LOGIC   ==============
# ---------------------------------------------

log "Creating authentication UI and logic..."
cat <<EOF > lib/data/services/auth_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _storage = const FlutterSecureStorage();

  Future<UserCredential?> signInWithEmailAndPassword(String email, String password) async {
    try {
      final result = await _auth.signInWithEmailAndPassword(email: email, password: password);
      await _storage.write(key: 'uid', value: result.user?.uid);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  Future<UserCredential?> signUpWithEmailAndPassword(String email, String password) async {
    try {
      final result = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      await _storage.write(key: 'uid', value: result.user?.uid);
      await _firestore.collection('users').doc(result.user?.uid).set({
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await sendEmailVerification();
      return result;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> sendEmailVerification() async {
    try {
      await _auth.currentUser?.sendEmailVerification();
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> isEmailVerified() async {
    await _auth.currentUser?.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _storage.delete(key: 'uid');
  }

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;
}
EOF

cat <<EOF > lib/ui/pages/auth_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/auth_viewmodel.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool _isSignUp = false;
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = Provider.of<AuthViewModel>(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _isSignUp ? 'Create Account' : 'Sign In',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _emailController,
                  onChanged: (value) => viewModel.email = value,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  enabled: !viewModel.isLoading,
                  validator: (value) =>
                      value?.isEmpty ?? true ? 'Email is required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  onChanged: (value) => viewModel.password = value,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                  enabled: !viewModel.isLoading,
                  validator: (value) => value != null && value.length < 6
                      ? 'Password must be at least 6 characters'
                      : null,
                ),
                if (viewModel.error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    viewModel.error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: viewModel.isLoading
                      ? null
                      : () {
                          if (_formKey.currentState?.validate() ?? false) {
                            if (_isSignUp) {
                              viewModel.register(context);
                            } else {
                              viewModel.signIn(context);
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: viewModel.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isSignUp ? 'Sign Up' : 'Sign In'),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: viewModel.isLoading
                      ? null
                      : () => setState(() => _isSignUp = !_isSignUp),
                  child: Text(_isSignUp
                      ? 'Already have an account? Sign In'
                      : "Don't have an account? Sign Up"),
                ),
                TextButton(
                  onPressed: viewModel.isLoading
                      ? null
                      : () {
                          if (_emailController.text.isEmpty) {
                            viewModel.setError('Please enter your email');
                            return;
                          }
                          viewModel.resetPassword(
                              _emailController.text, context);
                        },
                  child: const Text('Forgot Password?'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
EOF

cat <<EOF > lib/ui/viewmodels/auth_viewmodel.dart
import 'package:flutter/material.dart';
import '../../data/services/auth_service.dart';

class AuthViewModel extends ChangeNotifier {
  final AuthService _authService = AuthService();
  String? _email, _password, _error;
  bool _isLoading = false;

  String? get error => _error;
  bool get isLoading => _isLoading;

  set email(String value) => _email = value;
  set password(String value) => _password = value;

  void setError(String error) {
    _error = error;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> signIn(BuildContext context) async {
    if (_email == null || _password == null) {
      setError('Email and password are required');
      return;
    }
    _isLoading = true;
    notifyListeners();
    try {
      final userCredential =
          await _authService.signInWithEmailAndPassword(_email!, _password!);
      if (userCredential?.user != null) {
        final isVerified = await _authService.isEmailVerified();
        if (!isVerified) {
          setError('Please verify your email before signing in');
          await _authService.signOut();
        } else {
          clearError();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Signed in successfully')),
            );
          }
        }
      }
    } catch (e) {
      setError(_formatAuthError(e.toString()));
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> register(BuildContext context) async {
    if (_email == null || _password == null) {
      setError('Email and password are required');
      return;
    }
    _isLoading = true;
    notifyListeners();
    try {
      await _authService.signUpWithEmailAndPassword(_email!, _password!);
      clearError();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Verification email sent. Please check your inbox')),
        );
      }
    } catch (e) {
      setError(_formatAuthError(e.toString()));
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> resetPassword(String email, BuildContext context) async {
    if (email.isEmpty) {
      setError('Please enter your email');
      return;
    }
    _isLoading = true;
    notifyListeners();
    try {
      await _authService.sendPasswordResetEmail(email);
      clearError();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Password reset email sent. Check your inbox')),
        );
      }
    } catch (e) {
      setError(_formatAuthError(e.toString()));
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> sendEmailVerification(BuildContext context) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _authService.sendEmailVerification();
      clearError();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification email sent')),
        );
      }
    } catch (e) {
      setError(_formatAuthError(e.toString()));
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> isEmailVerified() async {
    return await _authService.isEmailVerified();
  }

  String _formatAuthError(String error) {
    if (error.contains('invalid-email')) return 'Invalid email format';
    if (error.contains('user-not-found')) return 'No user found with this email';
    if (error.contains('wrong-password')) return 'Incorrect password';
    if (error.contains('email-already-in-use')) return 'Email already in use';
    if (error.contains('weak-password')) return 'Password is too weak';
    return error.replaceAll(RegExp(r'\[.*?\]'), '').trim();
  }
}
EOF

# ---------------------------------------------
# ======   MAIN & ROUTING SETUP   ==========
# ---------------------------------------------

log "Configuring main.dart and routing..."
cat <<EOF > lib/main.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/config/app_config.dart';
import 'ui/viewmodels/auth_viewmodel.dart';
import 'routes/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  if (AppConfig.useEmulator) {
    const emulatorHost = 'localhost';
    FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, 8080);
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthViewModel(),
      child: MaterialApp.router(
        title: AppConfig.appName,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        routerConfig: AppRouter.router,
      ),
    );
  }
}
EOF

cat <<EOF > lib/routes/app_router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../data/services/auth_service.dart';
import '../ui/pages/auth_page.dart';
import '../ui/pages/home.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/',
    redirect: (context, state) async {
      final authService = AuthService();
      final user = authService.currentUser;
      if (user != null && await authService.isEmailVerified()) {
        return state.location == '/' ? '/home' : null;
      }
      return state.location == '/home' ? '/' : null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const AuthPage(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomePage(),
      ),
    ],
  );
}
EOF

cat <<EOF > lib/ui/pages/home.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/services/auth_service.dart';
import '../viewmodels/auth_viewmodel.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = Provider.of<AuthViewModel>(context);
    final authService = AuthService();
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await authService.signOut();
              if (context.mounted) {
                context.go('/');
              }
            },
          ),
        ],
      ),
      body: Center(
        child: FutureBuilder<bool>(
          future: authService.isEmailVerified(),
          builder: (context, snapshot) {
            final isVerified = snapshot.data ?? false;
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Welcome!',
                  style: TextStyle(fontSize: 24),
                ),
                const SizedBox(height: 16),
                Text(
                  'Logged in as: ${user?.email ?? 'Unknown'}',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                Text(
                  'Email verified: ${isVerified ? "Yes" : "No"}',
                  style: const TextStyle(fontSize: 16),
                ),
                if (!isVerified) ...[
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: viewModel.isLoading
                        ? null
                        : () => viewModel.sendEmailVerification(context),
                    child: const Text('Resend Verification Email'),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
EOF

# ---------------------------------------------
# ======   ANDROID CONFIGURATION   ==========
# ---------------------------------------------

log "Configuring Android..."
ANDROID_GRADLE="android/app/build.gradle"
MANIFEST_ANDROID="android/app/src/main/AndroidManifest.xml"
replace_in_file "compileSdkVersion [0-9]*" "compileSdkVersion $COMPILE_SDK" "$ANDROID_GRADLE"
replace_in_file "targetSdkVersion [0-9]*" "targetSdkVersion $TARGET_SDK" "$ANDROID_GRADLE"
replace_in_file "minSdkVersion [0-9]*" "minSdkVersion $MIN_SDK" "$ANDROID_GRADLE"
sed -i "/defaultConfig {/,/}/ s/}/&\n        flavorDimensions \"environment\"\n        productFlavors {\n            dev {\n                dimension \"environment\"\n                applicationIdSuffix \".dev\"\n                versionNameSuffix \"-dev\"\n            }\n            prod {\n                dimension \"environment\"\n            }\n        }\n    }/" "$ANDROID_GRADLE" || error "Failed to configure Android flavors."
sed -i "/<application/i\    <uses-permission android:name=\"android.permission.INTERNET\"/>" "$MANIFEST_ANDROID" || error "Failed to update AndroidManifest.xml."

# ---------------------------------------------
# ======   CI/CD SETUP   ==================
# ---------------------------------------------

log "Setting up GitHub Actions CI/CD..."
mkdir -p .github/workflows
cat <<EOF > .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'zulu'
          java-version: '17'
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '$FLUTTER_INSTALLED_VERSION'
          channel: 'stable'
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
      - run: flutter build apk --flavor dev
EOF

# ---------------------------------------------
# ======   GENERATE README   ===============
# ---------------------------------------------

log "Generating README.md..."
cat <<EOF > README.md
# $PROJECT_NAME

A production-ready Flutter application with Firebase Authentication, bootstrapped via a Bash script. This project features a secure, scalable authentication system with email sign-in, sign-up, password reset, and email verification, built using the MVVM architecture.

![Authentication UI](screenshots/auth_page.png)

## Features
- **Firebase Authentication**: Email-based sign-in, sign-up, password reset, email verification, and resend verification email.
- **MVVM Architecture**: Structured with models, services, viewmodels, and widgets for maintainability.
- **Flavors**: Dev and prod environments with distinct application IDs.
- **Navigation**: `go_router` with auth state redirects and email verification checks.
- **State Management**: `provider` for reactive UI updates.
- **Secure Storage**: `flutter_secure_storage` for user credentials.
- **Firebase Emulator**: Local testing support for auth and Firestore.
- **CI/CD**: GitHub Actions for automated builds, tests, and linting.
- **Error Handling**: User-friendly error messages and loading states.
- **Firestore Rules**: Secure, user-specific data access.

## Prerequisites
- **Flutter SDK**: Version >= 3.2.0 (tested with $FLUTTER_INSTALLED_VERSION)
- **Firebase CLI**: `npm install -g firebase-tools`
- **GitHub CLI**: `gh`
- **Git**: For version control
- **VS Code**: Recommended IDE

## Setup Instructions
1. **Clone the Repository**:
   \`\`\`bash
   git clone https://github.com/<your-username>/$PROJECT_NAME.git
   cd $PROJECT_NAME
   \`\`\`

2. **Install Dependencies**:
   \`\`\`bash
   flutter pub get
   \`\`\`

3. **Configure Firebase**:
   - Create a Firebase project at [Firebase Console](https://console.firebase.google.com).
   - Enable Email/Password authentication.
   - Add Android apps for `dev` (com.example.$PROJECT_NAME.dev) and `prod` (com.example.$PROJECT_NAME).
   - Download `google-services.json` for each flavor and place in:
     - `android/app/src/dev/`
     - `android/app/src/prod/`
   - Run:
     \`\`\`bash
     firebase login
     firebase use <your-firebase-project-id>
     \`\`\`

4. **Run Firebase Emulator** (Optional):
   \`\`\`bash
   firebase emulators:start
   \`\`\`
   Set `USE_EMULATOR=true` in your environment or modify `AppConfig.useEmulator`.

5. **Run the App**:
   \`\`\`bash
   flutter run --flavor dev
   \`\`\`

## Usage
- **Sign In/Sign Up**: Enter email and password. After sign-up, verify your email via the sent link.
- **Email Verification**: Non-verified users are prompted to resend verification emails on the home page.
- **Password Reset**: Use "Forgot Password?" to receive a reset email.
- **Logout**: Sign out via the app bar icon.

## Project Structure
\`\`\`
$PROJECT_NAME/
├── .github/workflows/    # GitHub Actions CI/CD
├── android/              # Android-specific files
├── lib/
│   ├── core/            # Configuration and utilities
│   ├── data/            # Models and services (e.g., AuthService)
│   ├── ui/              # Pages, viewmodels, and widgets
│   ├── routes/          # Navigation with go_router
├── firebase.json        # Firebase configuration
├── firestore.rules      # Firestore security rules
├── README.md            # Project documentation
├── screenshots/         # Screenshots (add auth_page.png)
\`\`\`

## CI/CD
Automated builds, tests, and linting are configured via GitHub Actions. See `.github/workflows/ci.yml`.

## Screenshots
### Authentication Page
![Auth Page](screenshots/auth_page.png)

## Future Enhancements
- Social login (Google, Apple)
- App icon generation
- iOS flavor support
- Additional Firebase services (e.g., Analytics, Push Notifications)

## Contributing
Contributions are welcome! Open an issue or submit a pull request.

## License
MIT License. See [LICENSE](LICENSE) for details.
EOF

# ---------------------------------------------
# ======   GIT & GITHUB SETUP   ===========
# ---------------------------------------------

log "Setting up Git and GitHub..."
git init || error "Git init failed."
cat <<EOF > .gitignore
# Flutter
.flutter-plugins
.flutter-plugins-dependencies
.packages
.pub/
build/

# Android
/android/.gradle/
*.iml

# iOS
Pods/

# Editor
.idea/
.vscode/

# Firebase
/firebase-debug.log
.env
/google-services.json
EOF
cat <<EOF > LICENSE
MIT License

Copyright (c) $(date +%Y) [Your Name]

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
git add . || error "Git add failed."
git commit -m "Initial commit: Bootstrap $PROJECT_NAME with Firebase Auth" || error "Git commit failed."
if [ $GH_AVAILABLE -eq 0 ]; then
  read -p "Push to GitHub? (y/n): " PUSH_TO_GH
  if [ "$PUSH_TO_GH" = "y" ]; then
    read -p "GitHub username: " GH_USER
    read -p "Repository name (default: $PROJECT_NAME): " GH_REPO
    GH_REPO=${GH_REPO:-$PROJECT_NAME}
    $GH_CMD repo create "$GH_USER/$GH_REPO" --public --source=. --remote=origin --push || error "GitHub repo creation failed."
  else
    log "Skipping GitHub push."
  fi
else
  log "Skipping GitHub integration (GitHub CLI not installed)."
fi

# ---------------------------------------------
# ======   OPEN IN VS CODE   ==============
# ---------------------------------------------

if command -v code &> /dev/null; then
  log "Opening in VS Code..."
  code . || error "Failed to open VS Code."
else
  log "VS Code not found. Open the project manually in '$PROJECT_DIR'."
fi

log "🎉 Project '$PROJECT_NAME' bootstrapped with Firebase Auth!"
```
