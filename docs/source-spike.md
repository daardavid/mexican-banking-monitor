# First implementation spike: CNBV source contract

The repository deliberately does not guess the layout or hidden download URLs of the CNBV exports.
The first functional milestone is a small, auditable spike using three adjacent reporting periods.

## Acceptance criteria

- Download an official historical-series CSV/XLSX, monthly bulletin XLSX, and ICAP PDF.
- Store retrieval time, final URL, SHA-256, reporting period, and parser version.
- Reject HTML responses, empty files, unexpected formats, and period mismatches.
- Identify stable institution codes rather than joining on display names.
- Map the exact CNBV concepts needed by the ten metrics.
- Convert YTD result lines to monthly flows before calculating TTM values.
- Reconcile selected calculated values against the CNBV bulletin.
- Fail on unmapped institutions or schema drift; do not silently default.

Only after this spike passes should the scheduled refresh command be enabled in
`.github/workflows/refresh.yml`.
