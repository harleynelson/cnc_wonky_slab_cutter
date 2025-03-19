// // lib/widgets/horizontal_progress_indicator.dart
// import 'package:flutter/material.dart';
// import '../services/processing/processing_flow_manager.dart';

// class HorizontalProgressIndicator extends StatelessWidget {
//   final ProcessingState currentState;
//   final Function(ProcessingState) onStepTapped;

//   const HorizontalProgressIndicator({
//     Key? key, 
//     required this.currentState,
//     required this.onStepTapped,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       height: 70,
//       decoration: BoxDecoration(
//         color: Colors.white,
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black12,
//             blurRadius: 4,
//             offset: Offset(0, 2),
//           )
//         ],
//       ),
//       child: Row(
//         children: [
//           _buildStep(
//             context, 
//             ProcessingState.notStarted, 
//             "Capture", 
//             Icons.camera_alt
//           ),
//           _buildDivider(),
//           _buildStep(
//             context, 
//             ProcessingState.imageProcessing, 
//             "Process", 
//             Icons.auto_fix_high
//           ),
//           _buildDivider(),
//           _buildStep(
//             context, 
//             ProcessingState.gcodeGeneration, 
//             "G-code", 
//             Icons.code
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildStep(
//     BuildContext context,
//     ProcessingState state,
//     String label,
//     IconData icon,
//   ) {
//     final isActive = currentState == state;
//     final isCompleted = _getStepIndex(currentState) > _getStepIndex(state);
    
//     return Expanded(
//       child: InkWell(
//         onTap: () => onStepTapped(state),
//         child: Container(
//           padding: EdgeInsets.symmetric(vertical: 8),
//           color: isActive 
//               ? Colors.blue.withOpacity(0.1) 
//               : Colors.transparent,
//           child: Column(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               Container(
//                 width: 36,
//                 height: 36,
//                 decoration: BoxDecoration(
//                   shape: BoxShape.circle,
//                   color: isCompleted
//                       ? Colors.green
//                       : isActive
//                           ? Colors.blue
//                           : Colors.grey.shade300,
//                 ),
//                 child: Center(
//                   child: isCompleted
//                       ? Icon(Icons.check, color: Colors.white, size: 20)
//                       : Icon(icon, 
//                           color: isActive ? Colors.white : Colors.grey.shade700,
//                           size: 20),
//                 ),
//               ),
//               SizedBox(height: 4),
//               Text(
//                 label,
//                 style: TextStyle(
//                   fontSize: 12,
//                   fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
//                   color: isActive ? Colors.blue : Colors.black87,
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildDivider() {
//     return Container(
//       width: 20,
//       height: 1,
//       color: Colors.grey.shade300,
//     );
//   }
  
//   int _getStepIndex(ProcessingState state) {
//     switch (state) {
//       case ProcessingState.notStarted:
//         return 0;
//       case ProcessingState.imageProcessing:
//         return 1;
//       case ProcessingState.gcodeGeneration:
//       case ProcessingState.completed:
//         return 2;
//       case ProcessingState.error:
//         return 0;
//       case ProcessingState.markerDetection:
//         // TODO: Handle this case.
//         throw UnimplementedError();
//       case ProcessingState.slabDetection:
//         // TODO: Handle this case.
//         throw UnimplementedError();
//     }
//   }
// }