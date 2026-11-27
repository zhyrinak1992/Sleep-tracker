bool shouldKeepClimatePollingInBackground({
  required bool audioObservationActive,
  required bool audioObservationPaused,
}) => audioObservationActive && !audioObservationPaused;
