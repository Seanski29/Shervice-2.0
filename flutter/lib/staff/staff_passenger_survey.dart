import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../constant.dart';

class StaffPassengerSurvey extends StatelessWidget {
  const StaffPassengerSurvey({super.key});

  // This is intentionally permanent: staff can display or copy the same QR
  // code whenever the OIC needs to distribute the passenger survey.
  String get surveyUrl =>
      'https://shervice-python-production.up.railway.app/passenger-evaluation';

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: surveyUrl));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passenger survey link copied.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Passenger Evaluation Link')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Anonymous passenger survey',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Use this permanent link or QR code for passengers. '
                      'They can select any driver from the full driver list.',
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: QrImageView(
                        data: surveyUrl,
                        size: 260,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Colors.black,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SelectableText(surveyUrl, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => _copy(context),
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy Link'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
