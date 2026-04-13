using Quoodle.Agent.UiCompanion.Infrastructure;
using Quoodle.Agent.UiCompanion.Models;
using Quoodle.Agent.UiCompanion.Services;

namespace Quoodle.Agent.UiCompanion.ViewModels;

public sealed class OnboardingViewModel : ObservableObject, IDisposable
{
    private readonly AgentStateStore _store;
    private AgentStateSnapshot _snapshot;

    public OnboardingViewModel(AgentStateStore store)
    {
        _store = store;
        _snapshot = store.Snapshot;

        _store.SnapshotChanged += HandleSnapshotChanged;

        CheckEnrollmentCommand = new RelayCommand(() => _store.CheckEnrollmentStatus(), () => !IsPaired && IsDetectIdle);
        BeginPairingCommand = new RelayCommand(() => _store.BeginPairing(), () => !IsPaired && IsDetectNotEnrolled);
        SelectTokenModeCommand = new RelayCommand(() => _store.SelectPairMode(OnboardingPairMode.Token), () => !IsPaired && IsPairStage);
        SelectQrModeCommand = new RelayCommand(
            () =>
            {
                _store.SelectPairMode(OnboardingPairMode.Qr);
                _store.StartQrPairing();
            },
            () => !IsPaired && IsPairStage);
        VerifyTokenCommand = new RelayCommand(() => _store.VerifyTokenPairing(), () => !IsPaired && CanVerifyToken);
        RetryPairingCommand = new RelayCommand(() => _store.RetryPairing(), () => !IsPaired && IsTokenFailed);

        RefreshCommandStates();
    }

    public RelayCommand CheckEnrollmentCommand { get; }

    public RelayCommand BeginPairingCommand { get; }

    public RelayCommand SelectTokenModeCommand { get; }

    public RelayCommand SelectQrModeCommand { get; }

    public RelayCommand VerifyTokenCommand { get; }

    public RelayCommand RetryPairingCommand { get; }

    public bool IsPaired => _snapshot.IsPaired;

    public OnboardingFlowState Flow => _snapshot.Onboarding;

    public bool IsDetectStage => Flow.Stage == OnboardingStage.Detect;

    public bool IsPairStage => Flow.Stage == OnboardingStage.Pair;

    public bool IsConfirmStage => Flow.Stage == OnboardingStage.Confirm;

    public bool IsDetectIdle => IsDetectStage && Flow.DetectState == OnboardingDetectState.Idle;

    public bool IsDetectChecking => IsDetectStage && Flow.DetectState == OnboardingDetectState.Checking;

    public bool IsDetectNotEnrolled => IsDetectStage && Flow.DetectState == OnboardingDetectState.NotEnrolled;

    public bool IsPairTokenMode => IsPairStage && Flow.PairMode == OnboardingPairMode.Token;

    public bool IsPairQrMode => IsPairStage && Flow.PairMode == OnboardingPairMode.Qr;

    public bool IsTokenVerifying => IsPairStage && Flow.PairState == OnboardingPairState.TokenVerifying;

    public bool IsTokenFailed => IsPairStage && Flow.PairState == OnboardingPairState.TokenFailed;

    public bool IsQrWaiting => IsPairStage && Flow.PairState == OnboardingPairState.QrWaiting;

    public bool IsRegistering => IsConfirmStage && Flow.ConfirmState == OnboardingConfirmState.Registering;

    public bool IsEnrollmentComplete => IsConfirmStage && Flow.ConfirmState == OnboardingConfirmState.EnrollmentComplete;

    public bool IsStepDetectComplete => IsPairStage || IsConfirmStage || IsPaired;

    public bool IsStepPairComplete => IsConfirmStage || IsPaired;

    public bool IsStepConfirmComplete => IsEnrollmentComplete || IsPaired;

    public bool IsStepDetectCurrent => IsDetectStage;

    public bool IsStepPairCurrent => IsPairStage;

    public bool IsStepConfirmCurrent => IsConfirmStage;

    public string TokenDigits => Flow.TokenDigits;

    public bool CanVerifyToken => IsPairTokenMode && !IsTokenVerifying && TokenDigits.Length == 6;

    public string PairError => Flow.PairError;

    public string PairingString => Flow.PairingString;

    public string EnrollmentDeviceName => _snapshot.DeviceName;

    public string EnrollmentDeviceId => _snapshot.DeviceId;

    public string EnrollmentPlatform => Environment.OSVersion.VersionString;

    public string EnrollmentAgentVersion => _snapshot.AgentVersion;

    public string EnrollmentAt => (Flow.EnrolledAtUtc ?? DateTimeOffset.UtcNow).LocalDateTime.ToString("M/d/yyyy, h:mm:ss tt");

    public string EnrollmentPolicyHash => _snapshot.PolicyHash;

    public string StatusLine => _snapshot.CurrentActivity;

    public void SetTokenDigit(int index, string? value)
    {
        if (index < 0 || index > 5)
        {
            return;
        }

        var current = TokenDigits.PadRight(6).ToCharArray();
        var digit = (value ?? string.Empty).FirstOrDefault(char.IsDigit);
        current[index] = digit == default ? ' ' : digit;

        var next = new string(current).Replace(" ", string.Empty);
        _store.SetPairTokenDigits(next);
    }

    public void SetTokenDigits(string? tokenDigits)
    {
        var sanitized = new string((tokenDigits ?? string.Empty).Where(char.IsDigit).Take(6).ToArray());
        _store.SetPairTokenDigits(sanitized);
    }

    public void BackspaceTokenDigit(int index)
    {
        if (index < 0 || index > 5)
        {
            return;
        }

        var current = TokenDigits.PadRight(6).ToCharArray();
        current[index] = ' ';
        var next = new string(current).Replace(" ", string.Empty);
        _store.SetPairTokenDigits(next);
    }

    public string TokenDigitAt(int index)
    {
        if (index < 0 || index > 5)
        {
            return string.Empty;
        }

        if (TokenDigits.Length <= index)
        {
            return string.Empty;
        }

        return TokenDigits[index].ToString();
    }

    private void HandleSnapshotChanged(object? sender, AgentStateSnapshot snapshot)
    {
        _snapshot = snapshot;
        RaiseAllDerivedProperties();
        RefreshCommandStates();
    }

    private void RaiseAllDerivedProperties()
    {
        RaisePropertyChanged(nameof(IsPaired));
        RaisePropertyChanged(nameof(Flow));
        RaisePropertyChanged(nameof(IsDetectStage));
        RaisePropertyChanged(nameof(IsPairStage));
        RaisePropertyChanged(nameof(IsConfirmStage));
        RaisePropertyChanged(nameof(IsDetectIdle));
        RaisePropertyChanged(nameof(IsDetectChecking));
        RaisePropertyChanged(nameof(IsDetectNotEnrolled));
        RaisePropertyChanged(nameof(IsPairTokenMode));
        RaisePropertyChanged(nameof(IsPairQrMode));
        RaisePropertyChanged(nameof(IsTokenVerifying));
        RaisePropertyChanged(nameof(IsTokenFailed));
        RaisePropertyChanged(nameof(IsQrWaiting));
        RaisePropertyChanged(nameof(IsRegistering));
        RaisePropertyChanged(nameof(IsEnrollmentComplete));
        RaisePropertyChanged(nameof(IsStepDetectComplete));
        RaisePropertyChanged(nameof(IsStepPairComplete));
        RaisePropertyChanged(nameof(IsStepConfirmComplete));
        RaisePropertyChanged(nameof(IsStepDetectCurrent));
        RaisePropertyChanged(nameof(IsStepPairCurrent));
        RaisePropertyChanged(nameof(IsStepConfirmCurrent));
        RaisePropertyChanged(nameof(TokenDigits));
        RaisePropertyChanged(nameof(CanVerifyToken));
        RaisePropertyChanged(nameof(PairError));
        RaisePropertyChanged(nameof(PairingString));
        RaisePropertyChanged(nameof(EnrollmentDeviceName));
        RaisePropertyChanged(nameof(EnrollmentDeviceId));
        RaisePropertyChanged(nameof(EnrollmentPlatform));
        RaisePropertyChanged(nameof(EnrollmentAgentVersion));
        RaisePropertyChanged(nameof(EnrollmentAt));
        RaisePropertyChanged(nameof(EnrollmentPolicyHash));
        RaisePropertyChanged(nameof(StatusLine));
    }

    private void RefreshCommandStates()
    {
        CheckEnrollmentCommand.RaiseCanExecuteChanged();
        BeginPairingCommand.RaiseCanExecuteChanged();
        SelectTokenModeCommand.RaiseCanExecuteChanged();
        SelectQrModeCommand.RaiseCanExecuteChanged();
        VerifyTokenCommand.RaiseCanExecuteChanged();
        RetryPairingCommand.RaiseCanExecuteChanged();
    }

    public void Dispose()
    {
        _store.SnapshotChanged -= HandleSnapshotChanged;
    }
}
