# StudyPilot for Windows

StudyPilot for Windows is a separate native desktop edition built with WPF and .NET 8. Its source, version number, build output, and local data are independent from the macOS application.

## Included in Windows 1.0.0

- A polished Windows workspace with Today, Assignments, Study Plan, Notes, Focus, and Settings views
- Assignments with subject, due date, priority, and estimated study time
- One-click study planning that splits work into focused sessions
- Automatic rescheduling for unchecked study blocks after their scheduled time ends
- Completion tracking; completing an assignment removes all related study blocks
- Personal study notes written and stored locally
- A 25-minute focus timer with a locally stored focus total
- JSON backup export and import
- Automatic migration from the earlier Windows preview's `assignments.json`
- Local persistence under `%LOCALAPPDATA%\StudyPilot\workspace.json`

This first release intentionally avoids pretending to provide feature parity where Windows-specific integrations are not ready. Google Calendar and downloadable local language models remain macOS-only for now.

## Build on Windows

Install the [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0), then run from PowerShell:

```powershell
.\Windows\build.ps1
```

The self-contained application is written to:

```text
Windows\dist\win-x64\StudyPilot.exe
```

It does not require a separate .NET installation on the destination computer.

For development in Visual Studio 2022, open `Windows\StudyPilot.Windows\StudyPilot.Windows.csproj`.

## Continuous build

The `Build StudyPilot for Windows` GitHub Actions workflow builds the Windows source separately and uploads `StudyPilot-Windows-x64.zip` as a workflow artifact. It only runs for changes under `Windows/` or when started manually.

## Isolation from macOS

The Windows project does not modify or compile any Swift, Xcode, Sparkle, appcast, entitlement, or macOS version file. Windows currently uses version `1.0.0`; the macOS application remains on its existing release line.
