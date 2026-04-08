using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using System.Windows.Input;

namespace Quoodle.Agent.UiCompanion.Controls;

public sealed partial class ActionButtonBar : UserControl
{
    public static readonly DependencyProperty PrimaryTextProperty = DependencyProperty.Register(
        nameof(PrimaryText), typeof(string), typeof(ActionButtonBar), new PropertyMetadata("Action", OnTextChanged));

    public static readonly DependencyProperty SecondaryTextProperty = DependencyProperty.Register(
        nameof(SecondaryText), typeof(string), typeof(ActionButtonBar), new PropertyMetadata("Secondary", OnTextChanged));

    public static readonly DependencyProperty PrimaryCommandProperty = DependencyProperty.Register(
        nameof(PrimaryCommand), typeof(ICommand), typeof(ActionButtonBar), new PropertyMetadata(null));

    public static readonly DependencyProperty SecondaryCommandProperty = DependencyProperty.Register(
        nameof(SecondaryCommand), typeof(ICommand), typeof(ActionButtonBar), new PropertyMetadata(null));

    public ActionButtonBar()
    {
        InitializeComponent();
        Render();
    }

    public string PrimaryText
    {
        get => (string)GetValue(PrimaryTextProperty);
        set => SetValue(PrimaryTextProperty, value);
    }

    public string SecondaryText
    {
        get => (string)GetValue(SecondaryTextProperty);
        set => SetValue(SecondaryTextProperty, value);
    }

    public ICommand? PrimaryCommand
    {
        get => (ICommand?)GetValue(PrimaryCommandProperty);
        set => SetValue(PrimaryCommandProperty, value);
    }

    public ICommand? SecondaryCommand
    {
        get => (ICommand?)GetValue(SecondaryCommandProperty);
        set => SetValue(SecondaryCommandProperty, value);
    }

    private static void OnTextChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        (d as ActionButtonBar)?.Render();
    }

    private void Render()
    {
        PrimaryButton.Content = PrimaryText;
        SecondaryButton.Content = SecondaryText;
    }
}
