using System.Windows;

namespace StudyPilot.Windows;

public partial class AddNoteWindow : Window
{
    public StudyNote? Result { get; private set; }
    public AddNoteWindow() { InitializeComponent(); Loaded += (_, _) => TitleInput.Focus(); }
    private void Save_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(TitleInput.Text))
        {
            MessageBox.Show("Enter a title for this note.", "StudyPilot", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        Result = new StudyNote { Title = TitleInput.Text.Trim(), Subject = string.IsNullOrWhiteSpace(SubjectInput.Text) ? "General" : SubjectInput.Text.Trim(), Body = BodyInput.Text.Trim(), UpdatedAt = DateTime.Now };
        DialogResult = true;
    }
}
