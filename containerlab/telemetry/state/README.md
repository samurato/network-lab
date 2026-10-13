Runtime only: gnmic writes the switches' state changes here (gnmi-state.json) and the collector
keeps its read offsets in otelcol/.  Both containers bind this folder; see docs/telemetry.md.
