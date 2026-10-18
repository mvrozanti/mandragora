{ writers }:
writers.writePython3Bin "du-exporter" { } (
  builtins.readFile ../../../.local/lib/mandragora/du-exporter.py
)
