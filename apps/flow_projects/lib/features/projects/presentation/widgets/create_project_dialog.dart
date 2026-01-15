import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flow_projects/core/constants/app_colors.dart';
import 'package:flow_projects/core/constants/app_spacing.dart';
import 'package:flow_projects/core/providers/providers.dart';
import 'package:flow_projects/core/theme/flow_theme.dart';
import 'package:intl/intl.dart';

class CreateProjectDialog extends ConsumerStatefulWidget {
  const CreateProjectDialog({super.key});

  @override
  ConsumerState<CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends ConsumerState<CreateProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final service = ref.read(projectsServiceProvider);
      await service.create(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        startDate: _startDate,
        targetDate: _endDate,
      );

      ref.invalidate(projectsProvider);
      ref.invalidate(activeProjectsProvider);

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final colors = context.flowColors;
    final initialDate = isStart
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? _startDate ?? DateTime.now());

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: isStart
          ? DateTime.now().subtract(const Duration(days: 365))
          : (_startDate ?? DateTime.now()),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: colors.primary,
                ),
          ),
          child: child!,
        );
      },
    );

    if (date != null) {
      setState(() {
        if (isStart) {
          _startDate = date;
          // Reset end date if it's before start date
          if (_endDate != null && _endDate!.isBefore(date)) {
            _endDate = null;
          }
        } else {
          _endDate = date;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final dateFormat = DateFormat('MMM d, yyyy');

    return Dialog(
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(FlowSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Text(
                    'Create New Project',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: FlowSpacing.lg),

              // Error
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(FlowSpacing.sm),
                  decoration: BoxDecoration(
                    color: FlowColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: FlowColors.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: FlowColors.error, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: FlowSpacing.md),
              ],

              // Name field
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Project Name',
                  hintText: 'Enter project name',
                ),
                autofocus: true,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a project name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: FlowSpacing.md),

              // Description field
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'Brief description of the project',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: FlowSpacing.lg),

              // Date range
              Text(
                'Timeline',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: FlowSpacing.sm),

              Row(
                children: [
                  // Start date
                  Expanded(
                    child: InkWell(
                      onTap: () => _selectDate(context, true),
                      borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: FlowSpacing.md,
                          vertical: FlowSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: colors.border),
                          borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today_outlined,
                              size: 18,
                              color: colors.textTertiary,
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Start Date',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.textTertiary,
                                  ),
                                ),
                                Text(
                                  _startDate != null
                                      ? dateFormat.format(_startDate!)
                                      : 'Not set',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: _startDate != null
                                        ? colors.textPrimary
                                        : colors.textPlaceholder,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: FlowSpacing.md),
                  Icon(Icons.arrow_forward, size: 18, color: colors.textTertiary),
                  const SizedBox(width: FlowSpacing.md),
                  // End date
                  Expanded(
                    child: InkWell(
                      onTap: () => _selectDate(context, false),
                      borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: FlowSpacing.md,
                          vertical: FlowSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: colors.border),
                          borderRadius: BorderRadius.circular(FlowSpacing.radiusSm),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.event_outlined,
                              size: 18,
                              color: colors.textTertiary,
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'End Date',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.textTertiary,
                                  ),
                                ),
                                Text(
                                  _endDate != null
                                      ? dateFormat.format(_endDate!)
                                      : 'Not set',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: _endDate != null
                                        ? colors.textPrimary
                                        : colors.textPlaceholder,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FlowSpacing.xl),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: FlowSpacing.sm),
                  FilledButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Create Project'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
