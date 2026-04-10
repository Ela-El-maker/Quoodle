import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/features/commands/presentation/providers/send_command_state.dart';

class SendCommandController extends AutoDisposeNotifier<SendCommandState> {
  @override
  SendCommandState build() {
    return SendCommandState.initial();
  }

  void selectMethod(String methodId) {
    state = state.copyWith(
      selectedMethodId: methodId,
      sensitiveOverride: false,
    );
  }

  void toggleSensitiveOverride() {
    state = state.copyWith(sensitiveOverride: !state.sensitiveOverride);
  }

  void togglePolicyPanel() {
    state = state.copyWith(showPolicyPanel: !state.showPolicyPanel);
  }

  void showTwoFactor() {
    state = state.copyWith(show2FA: true);
  }

  void confirmSensitiveAndShowTwoFactor() {
    state = state.copyWith(sensitiveOverride: true, show2FA: true);
  }

  void clearOtpError() {
    if (state.otpError) {
      state = state.copyWith(otpError: false);
    }
  }

  void cancelTwoFactor() {
    state = state.copyWith(
      show2FA: false,
      submitting: false,
      otpError: false,
    );
  }

  Future<bool> verifyOtp(String otp) async {
    final value = otp.trim();
    if (value.length < 6) {
      state = state.copyWith(otpError: true);
      return false;
    }

    state = state.copyWith(submitting: true, otpError: false);
    await Future<void>.delayed(const Duration(seconds: 1));
    state = state.copyWith(submitting: false);
    return true;
  }
}

final sendCommandControllerProvider =
    AutoDisposeNotifierProvider<SendCommandController, SendCommandState>(
  SendCommandController.new,
);
