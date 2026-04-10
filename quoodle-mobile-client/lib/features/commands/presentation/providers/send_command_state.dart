class SendCommandState {
  const SendCommandState({
    required this.selectedMethodId,
    required this.sensitiveOverride,
    required this.showPolicyPanel,
    required this.submitting,
    required this.show2FA,
    required this.otpError,
  });

  factory SendCommandState.initial() {
    return const SendCommandState(
      selectedMethodId: 'screenshot_capture',
      sensitiveOverride: false,
      showPolicyPanel: true,
      submitting: false,
      show2FA: false,
      otpError: false,
    );
  }

  final String selectedMethodId;
  final bool sensitiveOverride;
  final bool showPolicyPanel;
  final bool submitting;
  final bool show2FA;
  final bool otpError;

  SendCommandState copyWith({
    String? selectedMethodId,
    bool? sensitiveOverride,
    bool? showPolicyPanel,
    bool? submitting,
    bool? show2FA,
    bool? otpError,
  }) {
    return SendCommandState(
      selectedMethodId: selectedMethodId ?? this.selectedMethodId,
      sensitiveOverride: sensitiveOverride ?? this.sensitiveOverride,
      showPolicyPanel: showPolicyPanel ?? this.showPolicyPanel,
      submitting: submitting ?? this.submitting,
      show2FA: show2FA ?? this.show2FA,
      otpError: otpError ?? this.otpError,
    );
  }
}
