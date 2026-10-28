using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Win32;

namespace StudyPilot.Windows;

public partial class MainWindow : Window
{
    private readonly LocalStore _store = new();
    private readonly ObservableCollection<Assignment> _assignments = [];
    private readonly ObservableCollection<StudyNote> _notes = [];
    private readonly ObservableCollection<StudyBlock> _blocks = [];
    private readonly DispatcherTimer _focusTimer;
    private TimeSpan _focusRemaining = TimeSpan.FromMinutes(25);
    private int _focusMinutesCompleted;
    private bool _timerRunning;

    public MainWindow()
    {
        InitializeComponent();
        DateLabel.Text = DateTime.Today.ToString("dddd, MMMM d");
        DataPathLabel.Text = _store.FilePath;
        _focusTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _focusTimer.Tick += FocusTimer_Tick;
        LoadWorkspace();
        var moved = StudyPlanner.RescheduleOverdue(_blocks, DateTime.Now);
        if (moved > 0)
        {
            RescheduleNoticeText.Text = $"StudyPilot moved {moved} missed study block{(moved == 1 ? "" : "s")} to the next available time.";
            RescheduleNotice.Visibility = Visibility.Visible;
            SaveWorkspace();
        }
        ShowSection(TodayView, TodayNav, "Today", "Your work, shaped into a clear day.");
        RefreshAll();
    }

    private void LoadWorkspace()
    {
        try
        {
            var state = _store.Load();
            ReplaceCollections(state);
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "Could not load StudyPilot", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private void ReplaceCollections(StudyPilotState state)
    {
        _assignments.Clear();
        foreach (var item in state.Assignments.OrderBy(x => x.IsDone).ThenBy(x => x.DueDate)) _assignments.Add(item);
        _notes.Clear();
        foreach (var item in state.Notes.OrderByDescending(x => x.UpdatedAt)) _notes.Add(item);
        _blocks.Clear();
        foreach (var item in state.StudyBlocks.OrderBy(x => x.IsDone).ThenBy(x => x.Start)) _blocks.Add(item);
        _focusMinutesCompleted = state.FocusMinutesCompleted;
    }

    private StudyPilotState CurrentState() => new()
    {
        Assignments = _assignments.ToList(),
        Notes = _notes.ToList(),
        StudyBlocks = _blocks.ToList(),
        FocusMinutesCompleted = _focusMinutesCompleted
    };

    private void SaveWorkspace()
    {
        try { _store.Save(CurrentState()); }
        catch (Exception error) { MessageBox.Show($"StudyPilot could not save this change.\n\n{error.Message}", "Save failed", MessageBoxButton.OK, MessageBoxImage.Error); }
    }

    private void RefreshAll()
    {
        var now = DateTime.Now;
        DueCount.Text = _assignments.Count(x => !x.IsDone && x.DueDate.Date <= DateTime.Today.AddDays(7)).ToString();
        DoneCount.Text = _assignments.Count(x => x.IsDone).ToString();
        BlockCount.Text = _blocks.Count(x => !x.IsDone).ToString();
        FocusMinutesLabel.Text = $"{_focusMinutesCompleted} min";

        var todayAssignments = _assignments.Where(x => !x.IsDone).OrderBy(x => x.DueDate).Take(6).ToList();
        TodayAssignmentList.ItemsSource = todayAssignments;
        TodayEmpty.Visibility = todayAssignments.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

        var nextBlocks = _blocks.Where(x => !x.IsDone && x.End > now).OrderBy(x => x.Start).Take(5).ToList();
        TodayBlockList.ItemsSource = nextBlocks;
        TodayBlocksEmpty.Visibility = nextBlocks.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

        RefreshAssignmentSearch();
        var orderedBlocks = _blocks.OrderBy(x => x.IsDone).ThenBy(x => x.Start).ToList();
        BlockList.ItemsSource = orderedBlocks;
        PlanEmpty.Visibility = orderedBlocks.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        var plannedMinutes = _blocks.Where(x => !x.IsDone).Sum(x => x.DurationMinutes);
        PlanSummary.Text = $"{_blocks.Count(x => !x.IsDone)} sessions · {plannedMinutes} minutes remaining";

        NoteList.ItemsSource = _notes.OrderByDescending(x => x.UpdatedAt).ToList();
        NotesEmpty.Visibility = _notes.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        var selectedId = (FocusTaskPicker.SelectedItem as Assignment)?.Id;
        var focusTasks = _assignments.Where(x => !x.IsDone).OrderBy(x => x.DueDate).ToList();
        FocusTaskPicker.ItemsSource = focusTasks;
        FocusTaskPicker.SelectedItem = focusTasks.FirstOrDefault(x => x.Id == selectedId) ?? focusTasks.FirstOrDefault();
    }

    private void RefreshAssignmentSearch()
    {
        if (!IsInitialized || AssignmentList is null || AssignmentEmpty is null) return;
        var query = AssignmentSearch.Text?.Trim() ?? "";
        var items = _assignments.Where(x => query.Length == 0 || x.Title.Contains(query, StringComparison.OrdinalIgnoreCase) || x.Subject.Contains(query, StringComparison.OrdinalIgnoreCase)).OrderBy(x => x.IsDone).ThenBy(x => x.DueDate).ToList();
        AssignmentList.ItemsSource = items;
        AssignmentEmpty.Visibility = items.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void AddAssignment_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new AddAssignmentWindow { Owner = this };
        if (dialog.ShowDialog() != true || dialog.Result is null) return;
        _assignments.Add(dialog.Result);
        SaveWorkspace();
        RefreshAll();
    }

    private void CompleteAssignment_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not CheckBox { Tag: string id }) return;
        var assignment = _assignments.FirstOrDefault(x => x.Id == id);
        if (assignment is null) return;
        assignment.IsDone = !assignment.IsDone;
        if (assignment.IsDone)
        {
            foreach (var block in _blocks.Where(x => x.AssignmentId == assignment.Id).ToList()) _blocks.Remove(block);
        }
        SaveWorkspace();
        RefreshAll();
    }

    private void DeleteAssignment_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string id }) return;
        var assignment = _assignments.FirstOrDefault(x => x.Id == id);
        if (assignment is null) return;
        if (MessageBox.Show($"Delete “{assignment.Title}” and its study blocks?", "Delete assignment", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        _assignments.Remove(assignment);
        foreach (var block in _blocks.Where(x => x.AssignmentId == id).ToList()) _blocks.Remove(block);
        SaveWorkspace();
        RefreshAll();
    }

    private void AssignmentSearch_TextChanged(object sender, TextChangedEventArgs e) => RefreshAssignmentSearch();

    private void GeneratePlan_Click(object sender, RoutedEventArgs e)
    {
        if (_assignments.All(x => x.IsDone))
        {
            MessageBox.Show("Add an unfinished assignment first.", "Nothing to plan", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var created = StudyPlanner.Generate(_assignments, _blocks, DateTime.Now);
        SaveWorkspace();
        RefreshAll();
        MessageBox.Show(created == 0 ? "Your existing plan already covers the current estimates." : $"Added {created} study block{(created == 1 ? "" : "s")} around your assignments.", "Study plan ready", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private void CompleteBlock_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not CheckBox { Tag: string id }) return;
        var block = _blocks.FirstOrDefault(x => x.Id == id);
        if (block is null) return;
        block.IsDone = !block.IsDone;
        SaveWorkspace();
        RefreshAll();
    }

    private void MoveBlock_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string id }) return;
        var block = _blocks.FirstOrDefault(x => x.Id == id);
        if (block is null) return;
        block.Start = StudyPlanner.NextAvailableStart(_blocks.Where(x => x.Id != id), DateTime.Now, block.DurationMinutes);
        SaveWorkspace();
        RefreshAll();
    }

    private void DeleteBlock_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string id } && _blocks.FirstOrDefault(x => x.Id == id) is { } block)
        {
            _blocks.Remove(block);
            SaveWorkspace();
            RefreshAll();
        }
    }

    private void AddNote_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new AddNoteWindow { Owner = this };
        if (dialog.ShowDialog() != true || dialog.Result is null) return;
        _notes.Insert(0, dialog.Result);
        SaveWorkspace();
        RefreshAll();
    }

    private void DeleteNote_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string id } || _notes.FirstOrDefault(x => x.Id == id) is not { } note) return;
        if (MessageBox.Show($"Delete “{note.Title}”?", "Delete note", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        _notes.Remove(note);
        SaveWorkspace();
        RefreshAll();
    }

    private void StartPause_Click(object sender, RoutedEventArgs e)
    {
        _timerRunning = !_timerRunning;
        if (_timerRunning) _focusTimer.Start(); else _focusTimer.Stop();
        StartPauseButton.Content = _timerRunning ? "Pause" : "Start";
    }

    private void ResetTimer_Click(object sender, RoutedEventArgs e)
    {
        _focusTimer.Stop();
        _timerRunning = false;
        _focusRemaining = TimeSpan.FromMinutes(25);
        StartPauseButton.Content = "Start";
        UpdateTimerDisplay();
    }

    private void FocusTimer_Tick(object? sender, EventArgs e)
    {
        _focusRemaining = _focusRemaining.Subtract(TimeSpan.FromSeconds(1));
        if (_focusRemaining <= TimeSpan.Zero)
        {
            _focusTimer.Stop();
            _timerRunning = false;
            _focusMinutesCompleted += 25;
            SaveWorkspace();
            RefreshAll();
            MessageBox.Show("Focus session complete. Take a short break.", "Well done", MessageBoxButton.OK, MessageBoxImage.Information);
            _focusRemaining = TimeSpan.FromMinutes(25);
            StartPauseButton.Content = "Start";
        }
        UpdateTimerDisplay();
    }

    private void UpdateTimerDisplay()
    {
        TimerLabel.Text = $"{(int)_focusRemaining.TotalMinutes:00}:{_focusRemaining.Seconds:00}";
        TimerProgress.Value = 1500 - Math.Max(0, _focusRemaining.TotalSeconds);
    }

    private void Export_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new SaveFileDialog { Title = "Export StudyPilot backup", Filter = "StudyPilot backup (*.json)|*.json", FileName = $"StudyPilot-backup-{DateTime.Today:yyyy-MM-dd}.json" };
        if (dialog.ShowDialog() != true) return;
        try { _store.Export(dialog.FileName, CurrentState()); MessageBox.Show("Backup exported.", "StudyPilot", MessageBoxButton.OK, MessageBoxImage.Information); }
        catch (Exception error) { MessageBox.Show(error.Message, "Export failed", MessageBoxButton.OK, MessageBoxImage.Error); }
    }

    private void Import_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Title = "Import StudyPilot backup", Filter = "StudyPilot backup (*.json)|*.json" };
        if (dialog.ShowDialog() != true) return;
        if (MessageBox.Show("Importing replaces the current Windows workspace. Continue?", "Import backup", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        try { ReplaceCollections(_store.Import(dialog.FileName)); SaveWorkspace(); RefreshAll(); MessageBox.Show("Backup imported.", "StudyPilot", MessageBoxButton.OK, MessageBoxImage.Information); }
        catch (Exception error) { MessageBox.Show(error.Message, "Import failed", MessageBoxButton.OK, MessageBoxImage.Error); }
    }

    private void OpenDataFolder_Click(object sender, RoutedEventArgs e)
    {
        Directory.CreateDirectory(_store.FolderPath);
        Process.Start(new ProcessStartInfo { FileName = _store.FolderPath, UseShellExecute = true });
    }

    private void ShowSection(FrameworkElement section, Button nav, string title, string subtitle)
    {
        foreach (var view in new FrameworkElement[] { TodayView, AssignmentsView, PlannerView, NotesView, FocusView, SettingsView }) view.Visibility = Visibility.Collapsed;
        foreach (var button in new[] { TodayNav, AssignmentsNav, PlannerNav, NotesNav, FocusNav, SettingsNav })
        {
            button.Background = Brushes.Transparent;
            button.Foreground = new SolidColorBrush(Color.FromRgb(207, 217, 211));
        }
        section.Visibility = Visibility.Visible;
        nav.Background = new SolidColorBrush(Color.FromRgb(50, 71, 61));
        nav.Foreground = Brushes.White;
        ViewTitle.Text = title;
        ViewSubtitle.Text = subtitle;
    }

    private void Today_Click(object sender, RoutedEventArgs e) => ShowSection(TodayView, TodayNav, "Today", "Your work, shaped into a clear day.");
    private void Assignments_Click(object sender, RoutedEventArgs e) => ShowSection(AssignmentsView, AssignmentsNav, "Assignments", "Deadlines, estimates, and progress in one place.");
    private void Planner_Click(object sender, RoutedEventArgs e) => ShowSection(PlannerView, PlannerNav, "Study plan", "Turn unfinished work into focused sessions.");
    private void Notes_Click(object sender, RoutedEventArgs e) => ShowSection(NotesView, NotesNav, "Notes", "Capture what matters in your own words.");
    private void Focus_Click(object sender, RoutedEventArgs e) => ShowSection(FocusView, FocusNav, "Focus", "One task. Twenty-five quiet minutes.");
    private void Settings_Click(object sender, RoutedEventArgs e) => ShowSection(SettingsView, SettingsNav, "Settings & data", "Your workspace stays under your control.");
    private void Window_Closing(object? sender, CancelEventArgs e) => SaveWorkspace();
}
