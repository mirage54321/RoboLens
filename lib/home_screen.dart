import 'package:flutter/material.dart';
import 'tap_cursor.dart';
import 'package:url_launcher/url_launcher.dart';
import 'constants.dart';
import 'scan_screen.dart';
import 'rules_screen.dart';
import 'battery_screen.dart';
import 'batteryLOGIN_screen.dart';
import 'match_notifier_screen.dart';

// flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080

const pinkConstant = Color(0xFFCF2879);
const yellowConstant = Color(0xFFFFC107);
const grayConstant = Color.fromARGB(255, 204, 204, 204);
const orangeConstant = Color.fromARGB(255, 255, 160, 7);
const pinkConstantLight = Color(0xFFFFE4F0);
const yellowConstantLight = Color(0xFFFFF4E5);
const reportEmail = 'maronimira5@gmail.com';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _showReportDialog(BuildContext context) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Report an error',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    TapCursor(
                      onTap: () => Navigator.pop(ctx),
                      child: Icon(Icons.close, color: Colors.grey[400], size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Tell us what happened. This opens your mail app with the '
                  'details filled in so you can send it straight to us.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[600], height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 6,
                  decoration: InputDecoration(
                    hintText:
                        'e.g. "The scan tool crashed after I uploaded a photo"',
                    hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                    filled: true,
                    fillColor: Colors.grey[100],
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: const TextStyle(fontSize: 13.5),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final description = controller.text.trim();
                      await _launchReportEmail(description);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text('Send report',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Future<void> _launchReportEmail(String description) async {
    final body = description.isEmpty
        ? 'Describe what happened here.'
        : description;

    final uri = Uri(
      scheme: 'mailto',
      path: reportEmail,
      query:
          'subject=${Uri.encodeComponent('Marble error report')}&body=${Uri.encodeComponent(body)}',
    );

    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 255, 255),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                top(context),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        scanner(context),
                        rules(context),
                        battery(context),
                        stats(context),
                        const SizedBox(height: 24),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            Positioned(
              right: 16,
              bottom: 16,
              child: TapCursor(
                onTap: () => _showReportDialog(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey[300]!),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.flag_outlined, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Text(
                        'Report',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget top(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    //   child: Row(
    //     children: [
    //       Container(
    //         width: 32,
    //         height: 32,
    //         decoration: BoxDecoration(
    //           color: grayConstant,
    //           borderRadius: BorderRadius.circular(10),
    //         ),
    //         clipBehavior: Clip.antiAlias,
    //         child: Image.asset(
    //           'web/icons/Icon-111.png',
    //           fit: BoxFit.cover,
    //         ),
    //       ),
    //       const SizedBox(width: 8),
    //       RichText(
    //         text: const TextSpan(
    //           style: TextStyle(
    //               fontSize: 18,
    //               fontWeight: FontWeight.w500,
    //               color: Colors.black),
    //           children: [
    //             TextSpan(text: 'Robo'),
    //             TextSpan(text: 'L', style: TextStyle(color: pinkConstant)),
    //             TextSpan(text: 'e', style: TextStyle(color: TealScan)),
    //             TextSpan(text: 'n', style: TextStyle(color: yellowConstant)),
    //             TextSpan(text: 's', style: TextStyle(color: orangeConstant)),
    //           ],
    //         ),
    //       ),
    //       const Spacer(),
    //     ],
    //   ),
    );
  }

  Widget welcome() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Hey, ready to check your robot?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
          const SizedBox(height: 3),
        ],
      ),
    );
  }

  Widget _toolCard({
    required BuildContext context,
    required VoidCallback onTap,
    required Color color,
    required String title,
    required String description,
    required String ctaText,
    required Color ctaTextColor,
    required IconData icon,
  }) {
    return TapCursor(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(22),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showIcon = constraints.maxWidth >= 220;
            final iconSize = constraints.maxWidth < 300 ? 48.0 : 64.0;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                            color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.8),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          ctaText,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: ctaTextColor),
                        ),
                      ),
                    ],
                  ),
                ),
                if (showIcon) ...[
                  const SizedBox(width: 8),
                  Icon(icon, size: iconSize, color: Colors.white24),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget scanner(BuildContext context) {
    return _toolCard(
      context: context,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ScanScreen()),
      ),
      color: TealScan,
      title: 'Scan for issues',
      description:
          'In this tool, you can upload a photo of your robot and an AI will spot damage, loose wires, and more!',
      ctaText: 'Start scanning',
      ctaTextColor: TealScanText,
      icon: Icons.vrpano_outlined,
    );
  }

  Widget rules(BuildContext context) {
    return _toolCard(
      context: context,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RulesScreen()),
      ),
      color: pinkConstant,
      title: 'Check FRC rules',
      description:
          'In this tool, you can upload a photo of your robot and an AI will check if your robot passes the specific FRC inspection rules for a selected year!',
      ctaText: 'Check rules',
      ctaTextColor: pinkConstant,
      icon: Icons.fact_check_outlined,
    );
  }

  Widget battery(BuildContext context) {
    return _toolCard(
      context: context,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BatteryLoginScreen()),
      ),
      color: yellowConstant,
      title: 'Track your competition batteries',
      description:
          'In this tool, you can log your batteries with your team so that you can ensure optimal performance!',
      ctaText: 'Log batteries',
      ctaTextColor: yellowConstant,
      icon: Icons.battery_charging_full,
    );
  }

  Widget stats(BuildContext context) {
    return _toolCard(
      context: context,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MatchNotifierScreen()),
      ),
      color: orangeConstant,
      title: 'Look at FRC team stats',
      description:
          'In this tool, you can view and analyze FRC team statistics to improve your performance!',
      ctaText: 'View team stats',
      ctaTextColor: orangeConstant,
      icon: Icons.bar_chart,
    );
    
  }
  
}