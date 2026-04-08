using Quoodle.Agent.UiCompanion.Infrastructure;
using Quoodle.Agent.UiCompanion.Models;
using Quoodle.Agent.UiCompanion.Services;

namespace Quoodle.Agent.UiCompanion.ViewModels;

public sealed class OnboardingViewModel : ObservableObject
{
    private readonly AgentStateStore _store;
    private int _step;
    private bool _isPaired;
    private string _pairingToken = string.Empty;
    private string _hintText = string.Empty;

    public OnboardingViewModel(AgentStateStore store)
    {
        _store = store;
        _store.SnapshotChanged += HandleSnapshotChanged;
        NextCommand = new RelayCommand(() => _store.AdvanceOnboardingStep(), () => !_isPaired && _step < 6);
        BackCommand = new RelayCommand(() => _store.PreviousOnboardingStep(), () => !_isPaired && _step > 1);
        CompleteCommand = new RelayCommand(() => _store.CompleteOnboarding(PairingToken), () => !_isPaired && _step >= 5);

        Apply(_store.Snapshot);
    }

    public RelayCommand NextCommand { get; }

    public RelayCommand BackCommand { get; }

    public RelayCommand CompleteCommand { get; }

    public int Step
    {
        get => _step;
        private set => SetProperty(ref _step, value);
    }

    public bool IsPaired
    {
        get => _isPaired;
        private set => SetProperty(ref _isPaired, value);
    }

    public string PairingToken
    {
        get => _pairingToken;
        set => SetProperty(ref _pairingToken, value);
    }

    public string HintText
    {
        get => _hintText;
        private set => SetProperty(ref _hintText, value);
    }

    public string StepTitle => Step switch
    {
        1 => "Welcome",
        2 => "Verify Device",
        3 => "Connection Check",
        4 => "Policy Preview",
        5 => "Confirm Pairing",
        _ => "Paired"
    };

    public double ProgressPercent => (Math.Max(1, Step) / 6.0) * 100.0;

    private void HandleSnapshotChanged(object? sender, AgentStateSnapshot snapshot) => Apply(snapshot);

    private void Apply(AgentStateSnapshot snapshot)
    {
        Step = snapshot.OnboardingStep;
        IsPaired = snapshot.IsPaired;
        HintText = snapshot.IsPaired
            ? $"Device enrolled as {snapshot.DeviceId}."
            : "Use Next/Back to simulate guided onboarding, then complete pairing.";

        RaisePropertyChanged(nameof(StepTitle));
        RaisePropertyChanged(nameof(ProgressPercent));

        NextCommand.RaiseCanExecuteChanged();
        BackCommand.RaiseCanExecuteChanged();
        CompleteCommand.RaiseCanExecuteChanged();
    }
}
