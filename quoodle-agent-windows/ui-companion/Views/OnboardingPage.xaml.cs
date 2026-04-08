using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Quoodle.Agent.UiCompanion.ViewModels;

namespace Quoodle.Agent.UiCompanion.Views;

public sealed partial class OnboardingPage : Page
{
    private readonly OnboardingViewModel _vm;

    public OnboardingPage()
    {
        InitializeComponent();
        _vm = new OnboardingViewModel(App.StateStore);
        _vm.PropertyChanged += (_, _) => Render();

        Actions.PrimaryCommand = _vm.NextCommand;
        Actions.SecondaryCommand = _vm.BackCommand;
        CompleteButton.Command = _vm.CompleteCommand;

        Render();
    }

    private void Render()
    {
        StepTitleText.Text = $"Step {_vm.Step}: {_vm.StepTitle}";
        StepProgress.Value = _vm.ProgressPercent;
        StepHintText.Text = _vm.HintText;

        UpdateStepChips();

        PairTokenBox.IsEnabled = !_vm.IsPaired;
        CompleteButton.IsEnabled = _vm.CompleteCommand.CanExecute(null);
    }

    private void UpdateStepChips()
    {
        ApplyStepTone(Step1Chip, _vm.Step >= 1);
        ApplyStepTone(Step2Chip, _vm.Step >= 3);
        ApplyStepTone(Step3Chip, _vm.Step >= 5);
    }

    private static void ApplyStepTone(Border chip, bool active)
    {
        var bgKey = active ? "ChipSuccessBackgroundBrush" : "SurfaceAltBrush";
        var borderKey = active ? "SuccessBrush" : "BorderBrush";

        if (Application.Current.Resources.TryGetValue(bgKey, out var bgObj) && bgObj is Brush bg)
        {
            chip.Background = bg;
        }

        if (Application.Current.Resources.TryGetValue(borderKey, out var borderObj) && borderObj is Brush border)
        {
            chip.BorderBrush = border;
        }
    }

    private void OnPairingTokenChanged(object sender, TextChangedEventArgs e)
    {
        _vm.PairingToken = PairTokenBox.Text;
    }
}
