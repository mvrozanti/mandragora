{ pkgs }:

pkgs.python3.withPackages (p: [
  p.httpx
  p.pillow
  p.av
  p.rapidocr-onnxruntime
  p.piexif
])
