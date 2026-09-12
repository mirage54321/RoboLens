import 'dart:convert';
import 'package:flutter/material.dart';
import 'tap_cursor.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'battery_screen.dart';

const Yellor = Color(0xFFFFC107);
const YellorLight = Color(0xFFFFF4E5);
const YellorDark = Color(0xFFB38600);

class BatteryLoginScreen extends StatefulWidget {
  const BatteryLoginScreen({super.key});

  @override
  State<BatteryLoginScreen> createState() => _BatteryLoginScreenState();
}

class _BatteryLoginScreenState extends State<BatteryLoginScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _loginTeamCtrl = TextEditingController();
  final _loginPassCtrl = TextEditingController();

  final _regTeamCtrl = TextEditingController();
  final _regPassCtrl = TextEditingController();

  final _guestTeamCtrl = TextEditingController();

  bool _loading = false;
  String? _loginError;
  String? _regError;
  String? _guestError;

  static const String _base = 'https://ridgeboticsapp.onrender.com';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _saveSession({
    required String team,
    String? pass,
    required bool guest,
    String? teamName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('battery_team', team);
    await prefs.setBool('battery_guest', guest);
    if (pass != null) {
      await prefs.setString('battery_passcode', pass);
    } else {
      await prefs.remove('battery_passcode');
    }
    if (teamName != null) {
      await prefs.setString('battery_team_name', teamName);
    } else {
      await prefs.remove('battery_team_name');
    }
  }

  Future<void> _login() async {
    final team = _loginTeamCtrl.text.trim();
    final pass = _loginPassCtrl.text.trim();
    if (team.isEmpty || pass.isEmpty) {
      setState(() => _loginError = 'Enter both fields');
      return;
    }
    setState(() {
      _loading = true;
      _loginError = null;
    });
    try {
      final res = await http
          .post(
            Uri.parse('$_base/battery/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'teamNumber': team, 'passcode': pass}),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        await _saveSession(
          team: team,
          pass: pass,
          guest: false,
          teamName: data['teamName'] as String?,
        );
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const BatteryScreen()),
        );
      } else {
        setState(() {
          _loginError = 'Wrong team number or passcode';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _loginError = 'Could not connect, try again';
        _loading = false;
      });
    }
  }

  Future<void> _register() async {
    final team = _regTeamCtrl.text.trim();
    final pass = _regPassCtrl.text.trim();
    if (team.isEmpty || pass.isEmpty) {
      setState(() => _regError = 'Enter both fields');
      return;
    }
    if (pass.length < 4) {
      setState(() => _regError = 'Passcode must be at least 4 characters');
      return;
    }
    setState(() {
      _loading = true;
      _regError = null;
    });
    try {
      final res = await http
          .post(
            Uri.parse('$_base/battery/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'teamNumber': team, 'passcode': pass}),
          )
          .timeout(const Duration(seconds: 20));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        await _saveSession(
          team: team,
          pass: pass,
          guest: false,
          teamName: data['teamName'] as String?,
        );
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const BatteryScreen()),
        );
      } else {
        String message = 'Registration failed';
        try {
          final data = jsonDecode(res.body);
          message = data['error'] ?? message;
        } catch (_) {}
        setState(() {
          _regError = message;
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _regError = 'Could not connect, try again';
        _loading = false;
      });
    }
  }

  Future<void> _guestView() async {
    final team = _guestTeamCtrl.text.trim();
    if (team.isEmpty) {
      setState(() => _guestError = 'Enter a team number');
      return;
    }
    setState(() {
      _loading = true;
      _guestError = null;
    });
    try {
      final res = await http
          .get(Uri.parse('$_base/battery/list?teamNumber=$team&guest=true'))
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        await _saveSession(
          team: team,
          pass: null,
          guest: true,
          teamName: data['teamName'] as String?,
        );
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const BatteryScreen()),
        );
      } else if (res.statusCode == 404) {
        setState(() {
          _guestError = 'Team not found. Ask them to register first.';
          _loading = false;
        });
      } else {
        setState(() {
          _guestError = 'Could not connect, try again';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _guestError = 'Could not connect, try again';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 255, 248),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      TapCursor(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: YellorLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.arrow_back,
                              color: Yellor, size: 17),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text('Battery tracker',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TabBar(
                    controller: _tabController,
                    labelColor: YellorDark,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: Yellor,
                    labelStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500),
                    tabs: const [
                      Tab(text: 'Log in'),
                      Tab(text: 'New team'),
                      Tab(text: 'Guest'),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _loginTab(),
                  _registerTab(),
                  _guestTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loginTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          _field('Team number', _loginTeamCtrl, TextInputType.number),
          const SizedBox(height: 12),
          _field('Passcode', _loginPassCtrl, TextInputType.text,
              obscure: true, onSubmit: (_) => _login()),
          if (_loginError != null) _errorText(_loginError!),
          const SizedBox(height: 20),
          _bigButton('Log in', _loading ? null : _login),
        ],
      ),
    );
  }

  Widget _registerTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text('Create a battery tracker for your team.',
              style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          const SizedBox(height: 16),
          _field('Team number', _regTeamCtrl, TextInputType.number),
          const SizedBox(height: 12),
          _field('Choose a passcode', _regPassCtrl, TextInputType.text,
              obscure: true, onSubmit: (_) => _register()),
          const SizedBox(height: 6),
          Text('At least 4 characters. Share this with your team.',
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          if (_regError != null) _errorText(_regError!),
          const SizedBox(height: 20),
          _bigButton('Create account', _loading ? null : _register),
        ],
      ),
    );
  }

  Widget _guestTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text("View a team's batteries without logging in. Read-only.",
              style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          const SizedBox(height: 16),
          _field('Team number', _guestTeamCtrl, TextInputType.number,
              onSubmit: (_) => _guestView()),
          if (_guestError != null) _errorText(_guestError!),
          const SizedBox(height: 20),
          _bigButton('View as guest', _loading ? null : _guestView),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl,
    TextInputType type, {
    bool obscure = false,
    Function(String)? onSubmit,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      obscureText: obscure,
      onSubmitted: onSubmit,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Yellor),
        ),
      ),
    );
  }

  Widget _errorText(String msg) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(msg,
          style: const TextStyle(color: Color(0xFFD93025), fontSize: 13)),
    );
  }

  Widget _bigButton(String label, VoidCallback? onTap) {
    return SizedBox(
      width: double.infinity,
      child: TapCursor(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: onTap == null ? Yellor.withValues(alpha: 0.4) : Yellor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(label,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.white)),
          ),
        ),
      ),
    );
  }
}