#!/bin/bash

################################################################################
# 🚀 Enhanced Flutter & Firebase Bootstrapper with Authentication
# Features:
# 1. Flutter project setup with flavors
# 2. Firebase Authentication (email login, register, forgot password)
# 3. Optimized folder structure (MVVM + services)
# 4. Pre-configured Firebase rules and auth UI
# 5. GitHub integration with CI/CD
# 6. Enhanced error handling and logging
#
#The script create the full project folder and automate everything as follow
#1. Email verification
#2. Forgot password functionality
#3. Email verification status checks
#4. Resend verification email option
#5. Secure password reset flow
#6. UI feedback for all authentication states

#The script now creates a complete authentication system with:
#	•  Sign In/Sign Up
#	•  Password Reset
#	•  Email Verification
#	•  Secure Storage
#	•  Error Handling
#	•  Loading States
#	•  Navigation
#	•  User State Management
#Enjoy.Please enhance as much as you can
################################################################################

# ---------------------------------------------
# ========   CONFIGURABLE SECTION   ==========
# ---------------------------------------------
COMPILE_SDK=34
MIN_SDK=21
TARGET_SDK=34
FLUTTER_VERSION="3.32.0"
DEPS=(
  "  firebase_core: ^3.13.1"
  "  firebase_auth: ^5.5.4"
  "  cloud_firestore: ^5.4.4"
  "  dio: ^5.7.0"
  "  provider: ^6.1.2"
  "  flutter_secure_storage: ^9.2.2"
  "  go_router: ^14.2.8"
  "  google_fonts: ^6.2.1"
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
  command -v "$1" &> /dev/null || error "$2 not installed."
}

# ---------------------------------------------
# ===========   PREREQUISITES   ==============
# ---------------------------------------------

log "Checking prerequisites..."
check_command "$FLUTTER_CMD" "Flutter SDK"
check_command "$FIREBASE_CMD" "Firebase CLI"
check_command "$GH_CMD" "GitHub CLI"
check_command "git" "Git"
[ "$($FLUTTER_CMD --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)" == "$FLUTTER_VERSION" ] || error "Flutter version $FLUTTER_VERSION required."
log "All prerequisites met."

# ---------------------------------------------
# ===========   ARGUMENT PARSING   ===========
# ---------------------------------------------
[ -z "$1" ] && error "Usage: ./bootstrap.sh <project_name>"
PROJECT_NAME=$1
PROJECT_DIR="$PWD/$PROJECT_NAME"

# ---------------------------------------------
# =======   CREATE FLUTTER PROJECT   =========
# ---------------------------------------------

log "Creating Flutter project '$PROJECT_NAME'..."
$FLUTTER_CMD create --org com.example "$PROJECT_NAME"
cd "$PROJECT_DIR" || error "Failed to access project directory."

# ---------------------------------------------
# ======   CONFIGURE pubspec.yaml   =========
# ---------------------------------------------

log "Configuring pubspec.yaml..."
mv pubspec.yaml pubspec.yaml.bak
cat <<EOF > pubspec.yaml
name: $PROJECT_NAME
description: A Flutter project with Firebase Authentication.
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
  echo "$dep" >> pubspec.yaml
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
}
EOF

# ---------------------------------------------
# ======   FIREBASE AUTH SETUP   ===========
# ---------------------------------------------

log "Setting up Firebase Authentication..."
read -p "Enter Firebase project ID: " FIREBASE_PROJECT_ID
$FIREBASE_CMD use "$FIREBASE_PROJECT_ID" --add --non-interactive || error "Firebase project init failed."
$FIREBASE_CMD init firestore,auth,functions --project "$FIREBASE_PROJECT_ID" --non-interactive

cat <<EOF > firebase.json
{
  "firestore": {
    "rules": "firestore.rules",
    "indexes": "firestore.indexes.json"
  },
  "functions": {
    "source": "functions"
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

# ---------------------------------------------
# ======   AUTH UI & LOGIC   ==============
# ---------------------------------------------

log "Creating authentication UI and logic..."
cat <<EOF > lib/data/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
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

  bool isEmailVerified() {
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
  const AuthPage({Key? key}) : super(key: key);

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool _isSignUp = false;
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
      appBar: AppBar(
        title: Text(_isSignUp ? 'Create Account' : 'Sign In'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _emailController,
              onChanged: (value) => viewModel.email = value,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              enabled: !viewModel.isLoading,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              onChanged: (value) => viewModel.password = value,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              enabled: !viewModel.isLoading,
            ),
            if (viewModel.error != null) ...[
              const SizedBox(height: 12),
              Text(viewModel.error!, 
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: viewModel.isLoading
                  ? null
                  : () {
                      if (_isSignUp) {
                        viewModel.register();
                      } else {
                        viewModel.signIn();
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
                  : () {
                      setState(() {
                        _isSignUp = !_isSignUp;
                      });
                    },
              child: Text(_isSignUp
                  ? 'Already have an account? Sign In'
                  : "Don't have an account? Sign Up"),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: viewModel.isLoading
                  ? null
                  : () {
                      if (_emailController.text.isEmpty) {
                        viewModel.setError('Please enter your email address');
                        return;
                      }
                      viewModel.resetPassword(_emailController.text);
                    },
              child: const Text('Forgot Password?'),
            ),
          ],
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

  Future<void> signIn() async {
    if (_email == null || _password == null) return;
    _isLoading = true;
    notifyListeners();
    try {
      await _authService.signInWithEmailAndPassword(_email!, _password!);
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> register() async {
    if (_email == null || _password == null) return;
    _isLoading = true;
    notifyListeners();
    try {
      await _authService.signUpWithEmailAndPassword(_email!, _password!);
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> resetPassword(String email) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _authService.sendPasswordResetEmail(email);
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }
  
  Future<void> sendEmailVerification() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _authService.sendEmailVerification();
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }
  
  bool isEmailVerified() {
    return _authService.isEmailVerified();
  }
}
EOF

# ---------------------------------------------
# ======   MAIN & ROUTING SETUP   ==========
# ---------------------------------------------

log "Configuring main.dart and routing..."
cat <<EOF > lib/main.dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'ui/pages/auth_page.dart';
import 'ui/viewmodels/auth_viewmodel.dart';
import 'routes/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthViewModel(),
      child: MaterialApp.router(
        title: '$PROJECT_NAME',
        theme: ThemeData(primarySwatch: Colors.blue),
        routerConfig: AppRouter.router,
      ),
    );
  }
}
EOF

cat <<EOF > lib/routes/app_router.dart
import 'package:go_router/go_router.dart';
import '../ui/pages/auth_page.dart';
import '../ui/pages/home.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
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
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/services/auth_service.dart';

class HomePage extends StatelessWidget {
  HomePage({Key? key}) : super(key: key);
  
  final AuthService _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isVerified = _authService.isEmailVerified();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _authService.signOut();
              if (context.mounted) {
                Navigator.of(context).pushReplacementNamed('/');
              }
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Welcome!',
              style: TextStyle(fontSize: 24),
            ),
            const SizedBox(height: 16),
            Text(
              'Logged in as: \${user?.email}',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Text(
              'Email verified: \${isVerified ? "Yes" : "No"}',
              style: const TextStyle(fontSize: 16),
            ),
            if (!isVerified)
              ElevatedButton(
                onPressed: () async {
                  try {
                    await _authService.sendEmailVerification();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Verification email sent!')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: \${e.toString()}')),
                      );
                    }
                  }
                },
                child: const Text('Resend Verification Email'),
              ),
          ],
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

sed -i "/defaultConfig {/,/}/ s/}/&\n        flavorDimensions \"environment\"\n        productFlavors {\n            dev {\n                dimension \"environment\"\n                applicationIdSuffix \".dev\"\n                versionNameSuffix \"-dev\"\n            }\n            prod {\n                dimension \"environment\"\n            }\n        }\n    }/" "$ANDROID_GRADLE"

sed -i "/<application/i\    <uses-permission android:name=\"android.permission.INTERNET\"/>" "$MANIFEST_ANDROID"

# ---------------------------------------------
# ======   GIT & GITHUB SETUP   ===========
# ---------------------------------------------

log "Setting up Git and GitHub..."
git init
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
EOF

git add .
git commit -m "Initial commit: Bootstrap $PROJECT_NAME with Firebase Auth"

read -p "Push to GitHub? (y/n): " PUSH_TO_GH
if [ "$PUSH_TO_GH" = "y" ]; then
  read -p "GitHub username: " GH_USER
  read -p "Repository name (default: $PROJECT_NAME): " GH_REPO
  GH_REPO=${GH_REPO:-$PROJECT_NAME}
  $GH_CMD repo create "$GH_USER/$GH_REPO" --public --source=. --remote=origin --push
fi

# ---------------------------------------------
# ======   OPEN IN VS CODE   ==============
# ---------------------------------------------

log "Opening in VS Code..."
code .

log "🎉 Project '$PROJECT_NAME' bootstrapped with Firebase Auth!"

