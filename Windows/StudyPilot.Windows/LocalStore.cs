using System.IO;
using System.Text.Json;

namespace StudyPilot.Windows;

public sealed class LocalStore
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true, PropertyNameCaseInsensitive = true };
    public string FolderPath { get; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "StudyPilot");
    public string FilePath => Path.Combine(FolderPath, "workspace.json");

    public StudyPilotState Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<StudyPilotState>(File.ReadAllText(FilePath), JsonOptions) ?? new StudyPilotState();
            var legacyPath = Path.Combine(FolderPath, "assignments.json");
            if (File.Exists(legacyPath))
            {
                var assignments = JsonSerializer.Deserialize<List<Assignment>>(File.ReadAllText(legacyPath), JsonOptions) ?? [];
                return new StudyPilotState { Assignments = assignments };
            }
        }
        catch (Exception error)
        {
            throw new IOException("StudyPilot could not read its local workspace. The original file was not changed.", error);
        }
        return new StudyPilotState();
    }

    public void Save(StudyPilotState state)
    {
        Directory.CreateDirectory(FolderPath);
        var temporaryPath = FilePath + ".tmp";
        File.WriteAllText(temporaryPath, JsonSerializer.Serialize(state, JsonOptions));
        File.Move(temporaryPath, FilePath, true);
    }

    public void Export(string destination, StudyPilotState state) => File.WriteAllText(destination, JsonSerializer.Serialize(state, JsonOptions));
    public StudyPilotState Import(string source) => JsonSerializer.Deserialize<StudyPilotState>(File.ReadAllText(source), JsonOptions) ?? throw new InvalidDataException("That file does not contain a StudyPilot workspace.");
}
