import "package:flutter/material.dart";

import "mobile_review_screen.dart";
import "mobile_settings_screen.dart";
import "mobile_today_screen.dart";

class MobileShell extends StatefulWidget {
  const MobileShell({super.key});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = const [MobileTodayScreen(), MobileReviewScreen(), MobileSettingsScreen()];
    final items = const [
      BottomNavigationBarItem(icon: Icon(Icons.today), label: "Today"),
      BottomNavigationBarItem(icon: Icon(Icons.checklist), label: "Review"),
      BottomNavigationBarItem(icon: Icon(Icons.settings), label: "Settings"),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        items: items,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

