// lib/widgets/manual_contour_dialog.dart
// Dialog to prompt users to draw slab contour manually

import 'package:flutter/material.dart';

class ManualContourDialog extends StatelessWidget {
  final VoidCallback onManualDraw;
  final VoidCallback onCancel;

  const ManualContourDialog({
    Key? key,
    required this.onManualDraw,
    required this.onCancel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Slab Detection Failed'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            color: Colors.orange,
            size: 48,
          ),
          SizedBox(height: 16),
          Text(
            'We weren\'t able to detect the edges of the slab automatically.',
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),
          Text(
            'Would you like to manually draw the slab outline?',
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: onManualDraw,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
          ),
          child: Text('Draw Manually'),
        ),
      ],
    );
  }
}