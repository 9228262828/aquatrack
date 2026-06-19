import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const AquaTrackApp());
}

class AquaTrackApp extends StatefulWidget {
  const AquaTrackApp({super.key});

  @override
  State<AquaTrackApp> createState() => _AquaTrackAppState();
}

class _AquaTrackAppState extends State<AquaTrackApp> {
  late final AquaTrackController _controller;
  bool _darkMode = false;

  @override
  void initState() {
    super.initState();
    _controller = AquaTrackController();
    unawaited(_loadController());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AquaTrack',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0284C7),
        scaffoldBackgroundColor: const Color(0xFFF0F9FF),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF38BDF8),
        scaffoldBackgroundColor: const Color(0xFF082F49),
      ),
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) {
        return AquaTrackScope(
          notifier: _controller,
          onDarkModeChanged: _setDarkMode,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const SplashScreen(),
    );
  }

  Future<void> _loadController() async {
    await _controller.load();
    if (!mounted) return;

    final darkMode = _controller.darkMode;
    if (_darkMode != darkMode) {
      setState(() {
        _darkMode = darkMode;
      });
    }
  }

  Future<void> _setDarkMode(bool value) async {
    if (!mounted) return;

    if (_darkMode != value) {
      setState(() {
        _darkMode = value;
      });
    }

    await _controller.setDarkMode(value);
  }
}

class AquaTrackScope extends InheritedNotifier<AquaTrackController> {
  const AquaTrackScope({
    super.key,
    required super.notifier,
    required this.onDarkModeChanged,
    required super.child,
  });

  final Future<void> Function(bool value) onDarkModeChanged;

  static AquaTrackController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AquaTrackScope>();
    assert(scope != null, 'No AquaTrackScope found in context.');
    return scope!.notifier!;
  }

  static Future<void> Function(bool value) darkModeUpdaterOf(
    BuildContext context,
  ) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AquaTrackScope>();
    assert(scope != null, 'No AquaTrackScope found in context.');
    return scope!.onDarkModeChanged;
  }
}

class AquaTrackController extends ChangeNotifier {
  AquaTrackController();

  static const _dailyGoalKey = 'daily_goal';
  static const _completedCupsKey = 'completed_cups';
  static const _streakKey = 'streak';
  static const _lastTrackedDateKey = 'last_tracked_date';
  static const _darkModeKey = 'dark_mode';
  static const _lastGoalCompletedDateKey = 'last_goal_completed_date';
  static const _defaultDailyGoal = 8;

  SharedPreferences? _preferences;
  Timer? _dayResetTimer;
  bool _isLoaded = false;
  bool _isDisposed = false;
  int _dailyGoal = _defaultDailyGoal;
  int _completedCups = 0;
  int _streak = 0;
  String _lastTrackedDate = '';
  String _lastGoalCompletedDate = '';
  bool _darkMode = false;

  bool get isLoaded => _isLoaded;
  int get dailyGoal => _dailyGoal;
  int get completedCups => _completedCups;
  int get streak => _streak;
  bool get darkMode => _darkMode;

  Future<void> load() async {
    _preferences = await SharedPreferences.getInstance();
    if (_isDisposed) return;

    _dailyGoal = _preferences!.getInt(_dailyGoalKey) ?? _defaultDailyGoal;
    _completedCups = _preferences!.getInt(_completedCupsKey) ?? 0;
    _streak = _preferences!.getInt(_streakKey) ?? 0;
    _lastTrackedDate = _preferences!.getString(_lastTrackedDateKey) ?? '';
    _darkMode = _preferences!.getBool(_darkModeKey) ?? false;
    _lastGoalCompletedDate =
        _preferences!.getString(_lastGoalCompletedDateKey) ?? '';

    _dailyGoal = _dailyGoal.clamp(1, 99).toInt();
    _completedCups = _completedCups.clamp(0, 999).toInt();
    _streak = _streak.clamp(0, 9999).toInt();
    _resetIfNewDay(DateTime.now());

    _isLoaded = true;
    await _saveHydration();
    _scheduleNextDayReset();
    _notifyListeners();
  }

  Future<void> drinkCup() async {
    if (!_isLoaded) return;

    _resetIfNewDay(DateTime.now());
    final wasGoalCompletedToday = _isGoalCompletedToday;

    _completedCups += 1;
    if (!wasGoalCompletedToday && _completedCups >= _dailyGoal) {
      _streak += 1;
      _lastGoalCompletedDate = _lastTrackedDate;
    }

    await _saveHydration();
    _notifyListeners();
  }

  Future<void> undoCup() async {
    if (!_isLoaded || _completedCups == 0) return;

    _resetIfNewDay(DateTime.now());
    final wasGoalCompletedToday = _isGoalCompletedToday;

    _completedCups -= 1;
    if (wasGoalCompletedToday && _completedCups < _dailyGoal) {
      _streak = (_streak - 1).clamp(0, 9999).toInt();
      _lastGoalCompletedDate = '';
    }

    await _saveHydration();
    _notifyListeners();
  }

  Future<void> setDailyGoal(int cups) async {
    if (!_isLoaded) return;

    _resetIfNewDay(DateTime.now());
    final wasGoalCompletedToday = _isGoalCompletedToday;

    _dailyGoal = cups.clamp(1, 99).toInt();
    if (!wasGoalCompletedToday && _completedCups >= _dailyGoal) {
      _streak += 1;
      _lastGoalCompletedDate = _lastTrackedDate;
    } else if (wasGoalCompletedToday && _completedCups < _dailyGoal) {
      _streak = (_streak - 1).clamp(0, 9999).toInt();
      _lastGoalCompletedDate = '';
    }

    await _saveHydration();
    _notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    if (!_isLoaded) return;

    _darkMode = value;
    await _preferences?.setBool(_darkModeKey, _darkMode);
  }

  bool get _isGoalCompletedToday =>
      _lastGoalCompletedDate == _lastTrackedDate &&
      _lastGoalCompletedDate.isNotEmpty;

  void _resetIfNewDay(DateTime now) {
    final today = _dateKey(now);
    if (_lastTrackedDate.isEmpty) {
      _lastTrackedDate = today;
      return;
    }

    if (_lastTrackedDate == today) return;

    final yesterday = _dateKey(now.subtract(const Duration(days: 1)));
    if (_lastGoalCompletedDate != yesterday) {
      _streak = 0;
    }

    _completedCups = 0;
    _lastTrackedDate = today;
    if (_lastGoalCompletedDate != today) {
      _lastGoalCompletedDate =
          _lastGoalCompletedDate == yesterday ? _lastGoalCompletedDate : '';
    }
  }

  Future<void> _saveHydration() async {
    final preferences = _preferences;
    if (preferences == null) return;

    await preferences.setInt(_dailyGoalKey, _dailyGoal);
    await preferences.setInt(_completedCupsKey, _completedCups);
    await preferences.setInt(_streakKey, _streak);
    await preferences.setString(_lastTrackedDateKey, _lastTrackedDate);
    await preferences.setBool(_darkModeKey, _darkMode);
    await preferences.setString(
      _lastGoalCompletedDateKey,
      _lastGoalCompletedDate,
    );
  }

  void _scheduleNextDayReset() {
    _dayResetTimer?.cancel();

    final now = DateTime.now();
    final tomorrow = DateUtils.dateOnly(now).add(const Duration(days: 1));
    final delay = tomorrow.difference(now) + const Duration(seconds: 1);

    _dayResetTimer = Timer(delay, _handleDayResetTimer);
  }

  Future<void> _handleDayResetTimer() async {
    if (!_isLoaded || _isDisposed) return;

    _resetIfNewDay(DateTime.now());
    await _saveHydration();
    _notifyListeners();
    _scheduleNextDayReset();
  }

  void _notifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  String _dateKey(DateTime date) {
    final local = date.toLocal();
    return DateUtils.dateOnly(local).toIso8601String();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _dayResetTimer?.cancel();
    super.dispose();
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF075985),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 30,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.water_drop_rounded,
                  size: 70,
                  color: Color(0xFF0284C7),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'AquaTrack',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Stay hydrated every day',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                    );
                  },
                  child: const Text('Get Started'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AquaTrackScope.of(context);
    final goal = controller.dailyGoal;
    final completed = controller.completedCups;
    final streak = controller.streak;
    final progress = (completed / goal).clamp(0.0, 1.0).toDouble();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Today Hydration',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (!controller.isLoaded)
            const Padding(
              padding: EdgeInsets.only(bottom: 20),
              child: LinearProgressIndicator(),
            ),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              children: [
                const Icon(Icons.water_drop_rounded,
                    color: Colors.white, size: 70),
                const SizedBox(height: 16),
                Text(
                  '$completed / $goal cups',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Daily water progress',
                  style: TextStyle(color: Colors.white.withOpacity(0.85)),
                ),
                const SizedBox(height: 22),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 12,
                    backgroundColor: Colors.white.withOpacity(0.25),
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: _InfoCard(
                  title: 'Streak',
                  value: '$streak days',
                  icon: Icons.local_fire_department_rounded,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _InfoCard(
                  title: 'Goal',
                  value: '$goal cups',
                  icon: Icons.flag_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: controller.isLoaded ? controller.drinkCup : null,
              icon: const Icon(Icons.add_rounded),
              label: const Text('I drank a cup'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: controller.isLoaded && completed > 0
                  ? controller.undoCup
                  : null,
              icon: const Icon(Icons.undo_rounded),
              label: const Text('Undo'),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _InfoCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          Icon(icon, color: colorScheme.primary),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AquaTrackScope.of(context);
    final setDarkMode = AquaTrackScope.darkModeUpdaterOf(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ListTile(
            title: const Text('Daily Goal'),
            subtitle: Text('${controller.dailyGoal} cups per day'),
            leading: const Icon(Icons.flag_rounded),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showDailyGoalDialog(context, controller),
          ),
          SwitchListTile(
            value: controller.darkMode,
            onChanged: controller.isLoaded
                ? (value) {
                    unawaited(setDarkMode(value));
                  }
                : null,
            title: const Text('Dark Mode'),
            secondary: const Icon(Icons.dark_mode_rounded),
          ),
          ListTile(
            title: const Text('Privacy Policy'),
            leading: const Icon(Icons.privacy_tip_rounded),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
            ),
          ),
          ListTile(
            title: const Text('Terms & Conditions'),
            leading: const Icon(Icons.article_rounded),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TermsConditionsScreen()),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'AquaTrack 1.0.0\nSimple daily water tracker.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _showDailyGoalDialog(
    BuildContext context,
    AquaTrackController controller,
  ) async {
    final textController =
        TextEditingController(text: controller.dailyGoal.toString());

    final goal = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Daily Goal'),
          content: TextField(
            controller: textController,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Cups per day',
              helperText: 'Choose a goal from 1 to 99 cups.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = int.tryParse(textController.text.trim());
                Navigator.pop(dialogContext, parsed);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    textController.dispose();

    if (goal != null && context.mounted) {
      await controller.setDailyGoal(goal);
    }
  }
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _TextPage(
      title: 'Privacy Policy',
      content:
          'AquaTrack is designed as a simple offline hydration tracker.\n\n'
          'Data stored on your device: your daily cup goal, cups completed for the current day, streak count, last tracked date, and dark mode preference. This information is saved locally using device preferences so the app can restore your progress when you reopen it.\n\n'
          'No account or backend: AquaTrack does not require a login, does not connect to a backend server, and does not use Firebase or other cloud services for your hydration data.\n\n'
          'No advertising or tracking: AquaTrack does not show ads, does not use advertising SDKs, and does not sell or share your data with third parties.\n\n'
          'No notifications: AquaTrack does not schedule or send reminders, push notifications, or marketing messages.\n\n'
          'Your control: because the data is stored locally on your device, uninstalling the app or clearing app data may remove your saved AquaTrack progress and settings.',
    );
  }
}

class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _TextPage(
      title: 'Terms & Conditions',
      content:
          'By using AquaTrack, you agree to use the app as a personal hydration tracking tool.\n\n'
          'Personal use: AquaTrack is intended to help you record cups of water and monitor a daily goal on your own device. It is not a backend service, social platform, or account-based product.\n\n'
          'No medical advice: AquaTrack does not provide medical, nutrition, or health care advice. Hydration needs vary by person and circumstance, so consult a qualified professional if you have health questions.\n\n'
          'Local data: your goal, cups, streak, last tracked date, and dark mode preference are stored locally on your device. You are responsible for managing your device data, backups, and app removal.\n\n'
          'Availability: AquaTrack is provided as a simple utility. Features may change, and the app may not be error-free or available on every device configuration.\n\n'
          'Acceptable use: do not misuse the app, attempt to reverse engineer it for harmful purposes, or use it in a way that violates applicable laws.\n\n'
          'If you do not agree with these terms, stop using AquaTrack and remove it from your device.',
    );
  }
}

class _TextPage extends StatelessWidget {
  final String title;
  final String content;

  const _TextPage({
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            content,
            style: const TextStyle(fontSize: 16, height: 1.6),
          ),
        ],
      ),
    );
  }
}