/// Enum to track the current state of marker selection in the UI
enum MarkerSelectionState {
  /// Selecting the origin marker (bottom left)
  origin,
  
  /// Selecting the X-axis marker (bottom right)
  xAxis,
  
  /// Selecting the Scale/Y-axis marker (top left)
  scale,
  
  /// Selecting the slab seed point
  slab,
  
  /// Selecting the spillboard seed point
  spillboard,
  
  /// All selections complete
  complete
}