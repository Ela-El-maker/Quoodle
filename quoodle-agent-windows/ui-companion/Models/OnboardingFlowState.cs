namespace Quoodle.Agent.UiCompanion.Models;

public sealed record OnboardingFlowState(
    OnboardingStage Stage,
    OnboardingDetectState DetectState,
    OnboardingPairMode PairMode,
    OnboardingPairState PairState,
    OnboardingConfirmState ConfirmState,
    string TokenDigits,
    string PairingString,
    string PairError,
    DateTimeOffset? EnrolledAtUtc)
{
    public static OnboardingFlowState CreateInitial() => new(
        Stage: OnboardingStage.Detect,
        DetectState: OnboardingDetectState.Idle,
        PairMode: OnboardingPairMode.Token,
        PairState: OnboardingPairState.TokenEntry,
        ConfirmState: OnboardingConfirmState.Registering,
        TokenDigits: string.Empty,
        PairingString: string.Empty,
        PairError: string.Empty,
        EnrolledAtUtc: null);
}

