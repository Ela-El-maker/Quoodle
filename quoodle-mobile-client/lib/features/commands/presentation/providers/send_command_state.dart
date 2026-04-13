class SendCommandState {
  const SendCommandState({
    required this.selectedMethodId,
    required this.sensitiveOverride,
    required this.showPolicyPanel,
    required this.submitting,
  });

  factory SendCommandState.initial() {
    return const SendCommandState(
      selectedMethodId: 'screenshot_capture',
      sensitiveOverride: false,
      showPolicyPanel: true,
      submitting: false,
    );
  }

  final String selectedMethodId;
  final bool sensitiveOverride;
  final bool showPolicyPanel;
  final bool submitting;

  SendCommandState copyWith({
    String? selectedMethodId,
    bool? sensitiveOverride,
    bool? showPolicyPanel,
    bool? submitting,
  }) {
    return SendCommandState(
      selectedMethodId: selectedMethodId ?? this.selectedMethodId,
      sensitiveOverride: sensitiveOverride ?? this.sensitiveOverride,
      showPolicyPanel: showPolicyPanel ?? this.showPolicyPanel,
      submitting: submitting ?? this.submitting,
    );
  }
}
