import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_tasks/core/providers/providers.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';

/// Bottom sheet picker to move a task to a list
class MoveToListPicker extends ConsumerStatefulWidget {
  final Task task;
  final ValueChanged<TaskList> onListSelected;

  const MoveToListPicker({
    super.key,
    required this.task,
    required this.onListSelected,
  });

  /// Show the picker as a bottom sheet
  static Future<TaskList?> show(BuildContext context, Task task) async {
    TaskList? result;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MoveToListPicker(
        task: task,
        onListSelected: (list) {
          result = list;
          Navigator.of(context).pop();
        },
      ),
    );

    return result;
  }

  @override
  ConsumerState<MoveToListPicker> createState() => _MoveToListPickerState();
}

class _MoveToListPickerState extends ConsumerState<MoveToListPicker> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final listTree = ref.watch(listTreeProvider);

    // Filter lists based on search
    final filteredLists = _searchQuery.isEmpty
        ? listTree
        : _filterLists(listTree, _searchQuery);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: colors.textTertiary.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  'Move to list',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ),

          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search lists...',
                hintStyle: TextStyle(color: colors.textPlaceholder),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: colors.textSecondary,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.primary, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value.toLowerCase());
              },
            ),
          ),

          const Divider(height: 1),

          // List options
          Flexible(
            child: filteredLists.isEmpty
                ? _buildEmptyState(colors)
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: filteredLists.length,
                    itemBuilder: (context, index) {
                      final list = filteredLists[index];
                      return _ListTile(
                        list: list,
                        currentListId: widget.task.groupId,
                        onTap: () => widget.onListSelected(list),
                      );
                    },
                  ),
          ),

          // Create new list option
          Padding(
            padding: const EdgeInsets.all(16),
            child: InkWell(
              onTap: () => _showCreateListDialog(context),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: colors.border, style: BorderStyle.solid),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_rounded,
                      size: 20,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Create new list',
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(FlowColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_open_rounded,
            size: 48,
            color: colors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty ? 'No lists yet' : 'No matching lists',
            style: TextStyle(
              fontSize: 16,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isEmpty
                ? 'Create a list to organize your tasks'
                : 'Try a different search term',
            style: TextStyle(
              fontSize: 14,
              color: colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  List<TaskList> _filterLists(List<TaskList> lists, String query) {
    final results = <TaskList>[];

    for (final list in lists) {
      if (list.name.toLowerCase().contains(query) ||
          list.fullPath.toLowerCase().contains(query)) {
        results.add(list);
      }

      // Also check children
      if (list.children.isNotEmpty) {
        final matchingChildren = _filterLists(list.children, query);
        results.addAll(matchingChildren);
      }
    }

    return results;
  }

  Future<void> _showCreateListDialog(BuildContext context) async {
    final colors = context.flowColors;
    final nameController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create new list'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'List name',
            prefixText: '# ',
            prefixStyle: TextStyle(color: colors.primary),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.of(context).pop(value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.of(context).pop(name);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      try {
        final service = ref.read(tasksServiceProvider);
        final newList = await service.createList(name: result);

        // Refresh lists
        ref.invalidate(listsProvider);
        ref.invalidate(listTreeProvider);

        // Select the new list
        widget.onListSelected(newList);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create list: $e')),
          );
        }
      }
    }
  }
}

class _ListTile extends StatelessWidget {
  final TaskList list;
  final String? currentListId;
  final VoidCallback onTap;

  const _ListTile({
    required this.list,
    required this.currentListId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final isCurrentList = currentListId == list.id;

    return InkWell(
      onTap: isCurrentList ? null : onTap,
      child: Container(
        padding: EdgeInsets.only(
          left: 16 + (list.depth * 24.0),
          right: 16,
          top: 12,
          bottom: 12,
        ),
        child: Row(
          children: [
            Icon(
              list.isRoot ? Icons.tag_rounded : Icons.subdirectory_arrow_right_rounded,
              size: 20,
              color: isCurrentList ? colors.primary : colors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    list.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: isCurrentList ? FontWeight.w600 : FontWeight.w500,
                      color: isCurrentList ? colors.primary : colors.textPrimary,
                    ),
                  ),
                  if (list.taskCount > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${list.taskCount} task${list.taskCount == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isCurrentList)
              Icon(
                Icons.check_rounded,
                size: 20,
                color: colors.primary,
              ),
          ],
        ),
      ),
    );
  }
}
