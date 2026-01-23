import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_models/flow_models.dart';
import 'package:flow_tasks/core/providers/providers.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';
import 'package:intl/intl.dart';

/// Dialog for viewing and editing a user's AI profile
class UserAIProfileDialog extends ConsumerStatefulWidget {
  final String userId;
  final String userName;
  final String userEmail;

  const UserAIProfileDialog({
    super.key,
    required this.userId,
    required this.userName,
    required this.userEmail,
  });

  @override
  ConsumerState<UserAIProfileDialog> createState() => _UserAIProfileDialogState();
}

class _UserAIProfileDialogState extends ConsumerState<UserAIProfileDialog> {
  UserAIProfile? _profile;
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _error;
  String? _editingField;
  final _editController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final service = ref.read(tasksServiceProvider);
      final profile = await service.getUserAIProfile(widget.userId);
      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshProfile() async {
    setState(() {
      _isRefreshing = true;
      _error = null;
    });

    try {
      final service = ref.read(tasksServiceProvider);
      final profile = await service.refreshUserAIProfile(widget.userId);
      setState(() {
        _profile = profile;
        _isRefreshing = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isRefreshing = false;
      });
    }
  }

  Future<void> _saveField(String field, String value) async {
    try {
      final service = ref.read(tasksServiceProvider);
      await service.updateUserAIProfileField(widget.userId, field, value);
      await _loadProfile();
      setState(() => _editingField = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return Dialog(
      backgroundColor: colors.surface,
      child: Container(
        width: 600,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            _buildHeader(colors),

            // Content
            Flexible(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _buildError(colors)
                      : _buildContent(colors),
            ),

            // Footer
            _buildFooter(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(FlowColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceVariant.withValues(alpha: 0.3),
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          Icon(Icons.psychology, color: colors.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Profile',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${widget.userName.isNotEmpty ? widget.userName : 'User'} (${widget.userEmail})',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildError(FlowColorScheme colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colors.error),
            const SizedBox(height: 16),
            Text(
              'Failed to load profile',
              style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: colors.textTertiary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _loadProfile,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(FlowColorScheme colors) {
    if (_profile == null) {
      return _buildEmptyProfile(colors);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Refresh metadata
          _buildRefreshMetadata(colors),
          const SizedBox(height: 20),

          // Editable fields section
          _buildSectionHeader(colors, 'Editable Fields', Icons.edit_outlined),
          const SizedBox(height: 12),
          ...ProfileFieldMeta.editableFields.map(
            (meta) => _buildFieldCard(colors, meta),
          ),

          const SizedBox(height: 24),

          // Auto-generated fields section
          _buildSectionHeader(colors, 'Auto-Generated Fields', Icons.auto_awesome_outlined),
          const SizedBox(height: 12),
          ...ProfileFieldMeta.autoFields.map(
            (meta) => _buildFieldCard(colors, meta),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyProfile(FlowColorScheme colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_outline, size: 64, color: colors.textTertiary),
            const SizedBox(height: 16),
            Text(
              'No AI Profile Yet',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Generate a profile from the user\'s task history',
              style: TextStyle(color: colors.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isRefreshing ? null : _refreshProfile,
              icon: _isRefreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(_isRefreshing ? 'Generating...' : 'Generate Profile'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRefreshMetadata(FlowColorScheme colors) {
    final profile = _profile!;
    final dateFormat = DateFormat('MMM d, yyyy HH:mm');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceVariant.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.schedule, size: 14, color: colors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      'Last refreshed: ${dateFormat.format(profile.lastRefreshedAt)}',
                      style: TextStyle(color: colors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (profile.refreshTrigger != null) ...[
                      _TriggerBadge(trigger: profile.refreshTrigger!),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      '${profile.tasksSinceRefresh} tasks since refresh',
                      style: TextStyle(color: colors.textTertiary, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: _isRefreshing ? null : _refreshProfile,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: _isRefreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh, size: 16),
                      SizedBox(width: 6),
                      Text('Refresh'),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(FlowColorScheme colors, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: colors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildFieldCard(FlowColorScheme colors, ProfileFieldMeta meta) {
    final value = ProfileFieldMeta.getFieldValue(_profile!, meta.key);
    final isEmpty = value == null || value.isEmpty;
    final isEditing = _editingField == meta.key;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isEditing ? colors.primary : colors.divider,
          width: isEditing ? 2 : 1,
        ),
      ),
      child: isEditing
          ? _buildEditingField(colors, meta, value)
          : _buildReadOnlyField(colors, meta, value, isEmpty),
    );
  }

  Widget _buildReadOnlyField(
    FlowColorScheme colors,
    ProfileFieldMeta meta,
    String? value,
    bool isEmpty,
  ) {
    return InkWell(
      onTap: () {
        _editController.text = value ?? '';
        setState(() => _editingField = meta.key);
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        meta.label,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (meta.isAutoGenerated) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Auto',
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta.description,
                    style: TextStyle(color: colors.textTertiary, fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isEmpty ? '(empty)' : value!,
                    style: TextStyle(
                      color: isEmpty ? colors.textTertiary : colors.textSecondary,
                      fontSize: 13,
                      fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.edit_outlined, size: 16, color: colors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildEditingField(
    FlowColorScheme colors,
    ProfileFieldMeta meta,
    String? value,
  ) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                meta.label,
                style: TextStyle(
                  color: colors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (meta.isAutoGenerated) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Auto',
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _editController,
            maxLines: 3,
            maxLength: meta.maxLength,
            autofocus: true,
            style: TextStyle(color: colors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: meta.description,
              hintStyle: TextStyle(color: colors.textTertiary, fontSize: 13),
              filled: true,
              fillColor: colors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: colors.primary),
              ),
              contentPadding: const EdgeInsets.all(10),
              counterStyle: TextStyle(color: colors.textTertiary, fontSize: 10),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() => _editingField = null),
                child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _saveField(meta.key, _editController.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(FlowColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceVariant.withValues(alpha: 0.3),
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close', style: TextStyle(color: colors.textSecondary)),
          ),
        ],
      ),
    );
  }
}

/// Badge for refresh trigger type
class _TriggerBadge extends StatelessWidget {
  final String trigger;

  const _TriggerBadge({required this.trigger});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    IconData icon;

    switch (trigger) {
      case 'manual':
        color = Colors.purple;
        label = 'Manual';
        icon = Icons.touch_app;
        break;
      case 'scheduled':
        color = Colors.blue;
        label = 'Scheduled';
        icon = Icons.schedule;
        break;
      case 'task_milestone':
        color = Colors.green;
        label = 'Auto';
        icon = Icons.auto_awesome;
        break;
      default:
        color = Colors.grey;
        label = trigger;
        icon = Icons.info_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
