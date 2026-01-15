import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_tasks/core/constants/app_colors.dart';
import 'package:flow_tasks/core/constants/app_spacing.dart';
import 'package:flow_tasks/core/providers/providers.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';
import 'package:flow_tasks/features/tasks/presentation/widgets/task_list.dart';
import 'package:flow_tasks/features/tasks/presentation/widgets/quick_add_bar.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Check auth on mount
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authStateProvider.notifier).checkAuth();
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(selectedSidebarIndexProvider);
    final colors = context.flowColors;

    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          _Sidebar(
            selectedIndex: selectedIndex,
            onItemTap: (index) {
              ref.read(selectedSidebarIndexProvider.notifier).state = index;
            },
          ),

          // Main content
          Expanded(
            child: Column(
              children: [
                // Header
                _Header(),

                // Task list
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: FlowSpacing.taskListMaxWidth,
                      ),
                      child: Column(
                        children: [
                          // Quick add bar
                          const QuickAddBar(),

                          // Tasks
                          Expanded(
                            child: _buildTaskList(selectedIndex),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList(int selectedIndex) {
    switch (selectedIndex) {
      case 0: // Inbox
        return const TaskList(type: TaskListType.inbox);
      case 1: // Today
        return const TaskList(type: TaskListType.today);
      case 2: // Upcoming
        return const TaskList(type: TaskListType.upcoming);
      case 3: // Completed
        return const TaskList(type: TaskListType.completed);
      default:
        return const TaskList(type: TaskListType.inbox);
    }
  }
}

class _Header extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(selectedSidebarIndexProvider);
    final colors = context.flowColors;

    final titles = ['Inbox', 'Today', 'Upcoming', 'Completed'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.divider, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Text(
            titles[selectedIndex],
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              // TODO: Open settings
            },
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemTap;

  const _Sidebar({
    required this.selectedIndex,
    required this.onItemTap,
  });

  static const _items = [
    _SidebarItem(icon: Icons.inbox_rounded, label: 'Inbox'),
    _SidebarItem(icon: Icons.today_rounded, label: 'Today'),
    _SidebarItem(icon: Icons.calendar_month_rounded, label: 'Upcoming'),
    _SidebarItem(icon: Icons.check_circle_outline_rounded, label: 'Completed'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return Container(
      width: FlowSpacing.sidebarWidth,
      decoration: BoxDecoration(
        color: colors.sidebar,
        border: Border(
          right: BorderSide(color: colors.divider, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.all(FlowSpacing.lg),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: FlowColors.primary,
                  size: 28,
                ),
                const SizedBox(width: FlowSpacing.sm),
                Text(
                  'Flow',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),

          // Navigation items
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                final isSelected = index == selectedIndex;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Material(
                    color: isSelected
                        ? colors.sidebarSelected
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
                    child: InkWell(
                      onTap: () => onItemTap(index),
                      borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              item.icon,
                              size: 20,
                              color: isSelected
                                  ? colors.primary
                                  : colors.textSecondary,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: isSelected
                                    ? colors.textPrimary
                                    : colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem {
  final IconData icon;
  final String label;

  const _SidebarItem({required this.icon, required this.label});
}
