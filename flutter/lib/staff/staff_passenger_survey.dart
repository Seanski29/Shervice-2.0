import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:qr_flutter/qr_flutter.dart';
import '../constant.dart';
import '../core/session_manager.dart';

class StaffPassengerSurvey extends StatefulWidget {
  const StaffPassengerSurvey({super.key});

  @override
  State<StaffPassengerSurvey> createState() => _StaffPassengerSurveyState();
}

class _StaffPassengerSurveyState extends State<StaffPassengerSurvey> {
  String? _url;
  String? _expiresAt;
  bool _loading = false;
  String? _error;

  Future<void> _generate() async {
    setState(() { _loading = true; _error = null; });
    try {
      final session = await SessionManager.getUserData();
      final token = session['accessToken']?.toString();
      final response = await http.post(
        Uri.parse('$backendUrl/evaluate/passenger-survey'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'expires_in_days': 7}),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300 || data['success'] != true) {
        throw Exception(data['message'] ?? 'Unable to create survey link.');
      }
      setState(() { _url = data['url']?.toString(); _expiresAt = data['expires_at']?.toString(); });
    } catch (error) {
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copy() async {
    final url = _url;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Survey link copied.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Passenger Evaluation Link')),
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Card(
          child: Padding(padding: const EdgeInsets.all(24), child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Anonymous passenger survey', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text('Generate one link or QR code and send it to the OIC for distribution to passengers. The passenger will choose a driver from the full driver list.'),
              const SizedBox(height: 20),
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
              if (_url == null) ElevatedButton.icon(onPressed: _loading ? null : _generate, icon: const Icon(Icons.link), label: Text(_loading ? 'Generating…' : 'Generate Survey Link')),
              if (_url != null) ...[
                Center(child: QrImageView(data: _url!, size: 240, eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black), dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black))),
                const SizedBox(height: 12),
                SelectableText(_url!, textAlign: TextAlign.center),
                if (_expiresAt != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Expires: $_expiresAt', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey))),
                const SizedBox(height: 16),
                OutlinedButton.icon(onPressed: _copy, icon: const Icon(Icons.copy), label: const Text('Copy Link')),
                const SizedBox(height: 8),
                TextButton(onPressed: _loading ? null : _generate, child: const Text('Generate Another Link')),
              ],
            ],
          )),
        )),
      )),
    );
  }
}
