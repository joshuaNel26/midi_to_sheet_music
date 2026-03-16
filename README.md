# MIDI to Drum

Windows desktop app for converting a MIDI drum part into readable five-line drum staff notation with a live preview and PDF export.

## Current workflow

1. Open a `.mid` or `.midi` file.
2. Let the app start from the General MIDI drum map.
3. Adjust each detected MIDI note to the drum instrument you want.
4. Review the generated notation preview.
5. Export the preview to PDF.

## What is implemented

- Windows desktop Flutter application scaffold
- MIDI file selection
- In-project MIDI parser for standard MIDI files
- Automatic fallback to all note events when channel 10 percussion is not present
- Editable drum note mapping
- Live score preview on a five-line percussion staff
- PDF export that matches the on-screen preview

## Current notation assumptions

- Rhythms are quantized to a readable 16th-note grid
- The first detected tempo and time signature are used
- The renderer focuses on a clean single-staff drum chart, not full multi-voice engraving
- Drum noteheads, staff positions, ledger lines, accents, and basic flags are supported

## Local validation

- `dart analyze`
- `flutter test`

## Windows build requirement

`flutter build windows` is currently blocked on this machine because Visual Studio is not installed.

To build the desktop executable, install:

- Visual Studio
- The `Desktop development with C++` workload

After that, run:

```powershell
flutter build windows
```
