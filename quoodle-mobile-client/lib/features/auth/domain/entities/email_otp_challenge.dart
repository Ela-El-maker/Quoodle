class EmailOtpChallenge {
  const EmailOtpChallenge({
    required this.challengeId,
    required this.resendAfterSeconds,
  });

  final String challengeId;
  final int resendAfterSeconds;
}
