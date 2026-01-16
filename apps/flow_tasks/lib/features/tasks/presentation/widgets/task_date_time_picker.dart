import 'package:flutter/material.dart';
import 'package:flow_tasks/core/theme/flow_theme.dart';
import 'package:intl/intl.dart';

/// Google Tasks-style date picker dialog
class TaskDateTimePicker extends StatefulWidget {
  final DateTime? initialDate;
  final TimeOfDay? initialTime;
  final ValueChanged<DateTime?> onDateSelected;

  const TaskDateTimePicker({
    super.key,
    this.initialDate,
    this.initialTime,
    required this.onDateSelected,
  });

  /// Shows the date picker dialog and returns the selected date
  /// If onClear is provided, it will be called when the user clicks Clear
  static Future<DateTime?> show(
    BuildContext context, {
    DateTime? initialDate,
    TimeOfDay? initialTime,
    VoidCallback? onClear,
  }) async {
    return showDialog<DateTime?>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => _DatePickerDialog(
        initialDate: initialDate,
        initialTime: initialTime,
        onClear: onClear,
      ),
    );
  }

  @override
  State<TaskDateTimePicker> createState() => _TaskDateTimePickerState();
}

class _TaskDateTimePickerState extends State<TaskDateTimePicker> {
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _showTimePicker = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    if (widget.initialDate != null) {
      _selectedTime = TimeOfDay(
        hour: widget.initialDate!.hour,
        minute: widget.initialDate!.minute,
      );
      _showTimePicker =
          widget.initialDate!.hour != 0 || widget.initialDate!.minute != 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    // This widget is kept for backwards compatibility
    // Use TaskDateTimePicker.show() for the new dialog
    return const SizedBox.shrink();
  }
}

class _DatePickerDialog extends StatefulWidget {
  final DateTime? initialDate;
  final TimeOfDay? initialTime;
  final VoidCallback? onClear;

  const _DatePickerDialog({
    this.initialDate,
    this.initialTime,
    this.onClear,
  });

  @override
  State<_DatePickerDialog> createState() => _DatePickerDialogState();
}

class _DatePickerDialogState extends State<_DatePickerDialog> {
  late DateTime _displayMonth;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _showTime = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = widget.initialDate;
    _displayMonth = widget.initialDate ?? now;

    if (widget.initialDate != null) {
      final hasTime =
          widget.initialDate!.hour != 0 || widget.initialDate!.minute != 0;
      if (hasTime) {
        _showTime = true;
        _selectedTime = TimeOfDay(
          hour: widget.initialDate!.hour,
          minute: widget.initialDate!.minute,
        );
      }
    }
  }

  void _previousMonth() {
    setState(() {
      _displayMonth = DateTime(_displayMonth.year, _displayMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _displayMonth = DateTime(_displayMonth.year, _displayMonth.month + 1);
    });
  }

  void _selectDate(DateTime date) {
    setState(() => _selectedDate = date);
  }

  void _selectQuickAction(DateTime date) {
    setState(() {
      _selectedDate = date;
      _displayMonth = date;
    });
  }

  void _onClear() {
    widget.onClear?.call();
    Navigator.of(context).pop();
  }

  void _onCancel() {
    Navigator.of(context).pop();
  }

  void _onDone() {
    if (_selectedDate == null) {
      Navigator.of(context).pop(null);
      return;
    }

    DateTime result = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
    );

    if (_showTime && _selectedTime != null) {
      result = DateTime(
        result.year,
        result.month,
        result.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );
    }

    Navigator.of(context).pop(result);
  }

  Future<void> _showTimePickerDialog() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (time != null) {
      setState(() => _selectedTime = time);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Quick Actions Row
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _QuickActionButton(
                    icon: Icons.light_mode_outlined,
                    label: 'Today',
                    isSelected: _selectedDate != null &&
                        _isSameDay(_selectedDate!, today),
                    onTap: () => _selectQuickAction(today),
                  ),
                  _QuickActionButton(
                    icon: Icons.wb_twilight_outlined,
                    label: 'Tomorrow',
                    isSelected: _selectedDate != null &&
                        _isSameDay(
                            _selectedDate!, today.add(const Duration(days: 1))),
                    onTap: () =>
                        _selectQuickAction(today.add(const Duration(days: 1))),
                  ),
                  _QuickActionButton(
                    icon: Icons.date_range_outlined,
                    label: '+7 Days',
                    isSelected: _selectedDate != null &&
                        _isSameDay(
                            _selectedDate!, today.add(const Duration(days: 7))),
                    onTap: () =>
                        _selectQuickAction(today.add(const Duration(days: 7))),
                  ),
                  _QuickActionButton(
                    icon: Icons.nights_stay_outlined,
                    label: 'Evening',
                    isSelected: false,
                    onTap: () {
                      setState(() {
                        _selectedDate = today;
                        _displayMonth = today;
                        _showTime = true;
                        _selectedTime = const TimeOfDay(hour: 18, minute: 0);
                      });
                    },
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: colors.border.withOpacity(0.5)),

            // Month Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(Icons.chevron_left_rounded,
                        color: colors.textSecondary),
                    onPressed: _previousMonth,
                    splashRadius: 20,
                  ),
                  Text(
                    DateFormat('MMMM yyyy').format(_displayMonth),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.chevron_right_rounded,
                        color: colors.textSecondary),
                    onPressed: _nextMonth,
                    splashRadius: 20,
                  ),
                ],
              ),
            ),

            // Weekday Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                    .map((day) => SizedBox(
                          width: 36,
                          child: Center(
                            child: Text(
                              day,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: colors.textTertiary,
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),

            const SizedBox(height: 4),

            // Calendar Grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _buildCalendarGrid(colors, today),
            ),

            const SizedBox(height: 8),

            Divider(height: 1, color: colors.border.withOpacity(0.5)),

            // Time Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 20,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Add time',
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  if (_showTime && _selectedTime != null)
                    GestureDetector(
                      onTap: _showTimePickerDialog,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: colors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          _selectedTime!.format(context),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 28,
                    child: Switch(
                      value: _showTime,
                      onChanged: (value) {
                        setState(() {
                          _showTime = value;
                          if (value) {
                            _selectedTime ??=
                                const TimeOfDay(hour: 9, minute: 0);
                          }
                        });
                      },
                      activeColor: colors.primary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: colors.border.withOpacity(0.5)),

            // Footer Buttons
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (_selectedDate != null)
                    TextButton(
                      onPressed: _onClear,
                      child: Text(
                        'Clear',
                        style: TextStyle(
                          color: colors.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _onCancel,
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _selectedDate != null ? _onDone : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarGrid(FlowColorScheme colors, DateTime today) {
    final firstDayOfMonth =
        DateTime(_displayMonth.year, _displayMonth.month, 1);
    final lastDayOfMonth =
        DateTime(_displayMonth.year, _displayMonth.month + 1, 0);
    final startWeekday = firstDayOfMonth.weekday % 7; // Sunday = 0

    final daysInMonth = lastDayOfMonth.day;
    final totalCells = ((startWeekday + daysInMonth) / 7).ceil() * 7;

    return Column(
      children: List.generate((totalCells / 7).ceil(), (weekIndex) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(7, (dayIndex) {
            final cellIndex = weekIndex * 7 + dayIndex;
            final dayNumber = cellIndex - startWeekday + 1;

            if (dayNumber < 1 || dayNumber > daysInMonth) {
              return const SizedBox(width: 36, height: 36);
            }

            final date =
                DateTime(_displayMonth.year, _displayMonth.month, dayNumber);
            final isToday = _isSameDay(date, today);
            final isSelected =
                _selectedDate != null && _isSameDay(date, _selectedDate!);
            final isPast = date.isBefore(today);

            return GestureDetector(
              onTap: () => _selectDate(date),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? colors.primary
                      : isToday
                          ? colors.primary.withOpacity(0.1)
                          : null,
                ),
                child: Center(
                  child: Text(
                    dayNumber.toString(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isToday || isSelected ? FontWeight.w600 : null,
                      color: isSelected
                          ? Colors.white
                          : isToday
                              ? colors.primary
                              : isPast
                                  ? colors.textTertiary
                                  : colors.textPrimary,
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      }),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.flowColors;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected
                  ? colors.primary.withOpacity(0.15)
                  : colors.surfaceVariant.withOpacity(0.5),
              border: isSelected
                  ? Border.all(color: colors.primary, width: 1.5)
                  : null,
            ),
            child: Icon(
              icon,
              size: 20,
              color: isSelected ? colors.primary : colors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isSelected ? colors.primary : colors.textTertiary,
              fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
