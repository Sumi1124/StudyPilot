using System.Windows;
using System.Windows.Controls;

namespace StudyPilot.Windows;

public partial class AddAssignmentWindow : Window
{
    public Assignment? Result { get; private set; }

    public AddAssignmentWindow()
    {
        InitializeComponent();
        DueInput.SelectedDate = DateTime.Today.AddDays(1);
        Loaded += (_, _) => TitleInput.Focus();
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        var title = TitleInput.Text.Trim();
        if (title.Length == 0)
        {
            MessageBox.Show("Enter an assignment title.", "StudyPilot", MessageBoxButton.OK, MessageBoxImage.Information);
            TitleInput.Focus();
            return;
        }
        Result = new Assignment
        {
            Title = title,
            Subject = string.IsNullOrWhiteSpace(SubjectInput.Text) ? "General" : SubjectInput.Text.Trim(),
            DueDate = DueInput.SelectedDate ?? DateTime.Today.AddDays(1),
            Priority = (PriorityInput.SelectedItem as ComboBoxItem)?.Content?.ToString() ?? "Medium",
            EstimatedMinutes = int.TryParse((EstimateInput.SelectedItem as ComboBoxItem)?.Tag?.ToString(), out var minutes) ? minutes : 60
        };
        DialogResult = true;
    }
}
