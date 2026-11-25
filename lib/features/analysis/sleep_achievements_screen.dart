import 'package:flutter/material.dart';

import '../../models/sleep_session.dart';
import 'sleep_achievements_card.dart';

class SleepAchievementsScreen extends StatelessWidget {
  const SleepAchievementsScreen({super.key, required this.sessions});

  final List<SleepSession> sessions;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Достижения и рекорды')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const Text(
            'Ваши достижения и четыре личных рекорда, рассчитанные по завершённым ночам.',
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 12),
          SleepAchievementsCard(sessions: sessions),
        ],
      ),
    ),
  );
}
