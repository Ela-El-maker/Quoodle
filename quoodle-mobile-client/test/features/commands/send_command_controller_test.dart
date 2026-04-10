import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_device_control/features/commands/presentation/providers/send_command_controller.dart';

void main() {
  test('SendCommandController handles selection, policy and otp state',
      () async {
    final container = ProviderContainer();
    final sub = container.listen(
      sendCommandControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);
    addTearDown(container.dispose);

    final controller = container.read(sendCommandControllerProvider.notifier);

    controller.selectMethod('policy_sync');
    expect(container.read(sendCommandControllerProvider).selectedMethodId,
        'policy_sync');

    controller.togglePolicyPanel();
    expect(
        container.read(sendCommandControllerProvider).showPolicyPanel, isFalse);

    final invalid = await controller.verifyOtp('12');
    expect(invalid, isFalse);
    expect(container.read(sendCommandControllerProvider).otpError, isTrue);

    final valid = await controller.verifyOtp('123456');
    expect(valid, isTrue);
    expect(container.read(sendCommandControllerProvider).submitting, isFalse);
  });
}
