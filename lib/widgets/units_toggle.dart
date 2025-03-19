// lib/widgets/units_toggle.dart
// Widget for toggling between metric and imperial units

import 'package:flutter/material.dart';

/// A widget that toggles between metric and imperial units
class UnitsToggle extends StatelessWidget {
  final bool isMetric;
  final Function(bool) onChanged;

  const UnitsToggle({
    Key? key,
    required this.isMetric,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Unit System',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Divider(),
            Text(
              'Choose between metric and imperial units',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            SizedBox(height: 8),
            Center(
              child: ToggleButtons(
                isSelected: [isMetric, !isMetric],
                onPressed: (int index) {
                  onChanged(index == 0);
                },
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(Icons.straighten),
                        SizedBox(width: 4),
                        Text('Metric (mm)')
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(Icons.straighten),
                        SizedBox(width: 4),
                        Text('Imperial (in)')
                      ],
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
}