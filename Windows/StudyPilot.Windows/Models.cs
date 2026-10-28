using System.Text.Json.Serialization;

namespace StudyPilot.Windows;

public sealed class StudyPilotState
{
    public int SchemaVersion { get; set; } = 1;
    public List<Assignment> Assignments { get; set; } = [];
    public List<StudyNote> Notes { get; set; } = [];
    public List<StudyBlock> StudyBlocks { get; set; } = [];
    public int FocusMinutesCompleted { get; set; }
}

public sealed class Assignment
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string Title { get; set; } = "";
    public string Subject { get; set; } = "General";
    public DateTime DueDate { get; set; } = DateTime.Today;
    public int EstimatedMinutes { get; set; } = 60;
    public string Priority { get; set; } = "Medium";
    public bool IsDone { get; set; }
    [JsonIgnore] public string Subtitle => $"{Subject} · {EstimatedMinutes} min · {Priority}";
    [JsonIgnore] public string DueLabel => IsDone ? "Completed" : DueDate.Date == DateTime.Today ? "Today" : DueDate.Date == DateTime.Today.AddDays(1) ? "Tomorrow" : DueDate.ToString("MMM d");
}

public sealed class StudyNote
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string Title { get; set; } = "Untitled note";
    public string Subject { get; set; } = "General";
    public string Body { get; set; } = "";
    public DateTime UpdatedAt { get; set; } = DateTime.Now;
    [JsonIgnore] public string Preview => string.IsNullOrWhiteSpace(Body) ? "Empty note" : Body.Replace("\r", " ").Replace("\n", " ");
    [JsonIgnore] public string UpdatedLabel => $"{Subject} · Updated {UpdatedAt:g}";
}

public sealed class StudyBlock
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string AssignmentId { get; set; } = "";
    public string Title { get; set; } = "Study session";
    public string Subject { get; set; } = "General";
    public DateTime Start { get; set; }
    public int DurationMinutes { get; set; } = 45;
    public bool IsDone { get; set; }
    [JsonIgnore] public DateTime End => Start.AddMinutes(DurationMinutes);
    [JsonIgnore] public string TimeLabel => $"{Start:ddd, MMM d · h:mm tt}–{End:h:mm tt}";
    [JsonIgnore] public string DurationLabel => $"{DurationMinutes} min";
}
