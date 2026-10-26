import 'package:flutter/material.dart';

void main() => runApp(const WorkHoursApp());

class WorkHoursApp extends StatelessWidget {
  const WorkHoursApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Учёт рабочего времени',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF315C84)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedIndex = 0;

  static const pages = <_PageContent>[
    _PageContent(
      title: 'Сегодня',
      icon: Icons.today_outlined,
      description: 'Здесь появятся ближайшая смена, подтверждение начала '
          'работы и check-out.',
      items: ['Запланированное начало', 'Фактическое подтверждение', 'Итог смены'],
    ),
    _PageContent(
      title: 'План',
      icon: Icons.calendar_month_outlined,
      description: 'Расписание смен на неделю и будущие даты.',
      items: ['Создать смену', 'Выбрать проект', 'Скопировать расписание'],
    ),
    _PageContent(
      title: 'Проекты',
      icon: Icons.work_outline,
      description: 'Проекты и доступные для них тарифы.',
      items: ['Название проекта', 'Несколько тарифов', 'Архив проектов'],
    ),
    _PageContent(
      title: 'Отчёты',
      icon: Icons.bar_chart_outlined,
      description: 'Часы и заработок по завершённым сменам.',
      items: ['День и неделя', 'Месяц и выбранный период', 'PDF и CSV'],
    ),
    _PageContent(
      title: 'Настройки',
      icon: Icons.settings_outlined,
      description: 'Напоминания, резервные копии и предпочтения.',
      items: ['Уведомления', 'Экспорт и восстановление', 'Язык и валюта'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final currentPage = pages[selectedIndex];
    return Scaffold(
      appBar: AppBar(title: const Text('Учёт рабочего времени')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('Прототип интерфейса',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 12),
                Text(currentPage.title,
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 12),
                Text(currentPage.description),
                const SizedBox(height: 24),
                for (final item in currentPage.items)
                  Card(
                    child: ListTile(
                      leading: Icon(currentPage.icon),
                      title: Text(item),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => setState(() => selectedIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), label: 'Сегодня'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: 'План'),
          NavigationDestination(icon: Icon(Icons.work_outline), label: 'Проекты'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), label: 'Отчёты'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Настройки'),
        ],
      ),
    );
  }
}

class _PageContent {
  const _PageContent({
    required this.title,
    required this.icon,
    required this.description,
    required this.items,
  });

  final String title;
  final IconData icon;
  final String description;
  final List<String> items;
}
