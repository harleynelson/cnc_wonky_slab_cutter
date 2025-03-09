import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A specialized text field for numeric settings
class SettingsTextField extends StatelessWidget {
  final String label;
  final double value;
  final Function(double) onChanged;
  final IconData? icon;
  final String? helperText;
  final double min;
  final double max;

  const SettingsTextField({
    Key? key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.icon,
    this.helperText,
    this.min = 0.1,
    this.max = 10000.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        initialValue: value.toString(),
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          helperText: helperText,
          prefixIcon: icon != null ? Icon(icon) : null,
        ),
        keyboardType: TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
        ],
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please enter a value';
          }
          final number = double.tryParse(value);
          if (number == null) {
            return 'Please enter a valid number';
          }
          if (number < min || number > max) {
            return 'Value must be between $min and $max';
          }
          return null;
        },
        onChanged: (value) {
          final number = double.tryParse(value);
          if (number != null) {
            onChanged(number);
          }
        },
      ),
    );
  }
}

/// A dropdown field for settings with predefined options
class SettingsDropdownField<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final Function(T?) onChanged;
  final IconData? icon;
  final String? helperText;

  const SettingsDropdownField({
    Key? key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.icon,
    this.helperText,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<T>(
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          helperText: helperText,
          prefixIcon: icon != null ? Icon(icon) : null,
        ),
        value: value,
        items: items,
        onChanged: onChanged,
        isExpanded: true,
      ),
    );
  }
}

/// A toggle switch for boolean settings
class SettingsToggle extends StatelessWidget {
  final String label;
  final bool value;
  final Function(bool) onChanged;
  final IconData? icon;
  final String? helperText;

  const SettingsToggle({
    Key? key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.icon,
    this.helperText,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon),
            SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (helperText != null)
                  Text(
                    helperText!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}