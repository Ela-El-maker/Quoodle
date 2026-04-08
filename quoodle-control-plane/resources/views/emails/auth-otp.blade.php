<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Quoodle Verification Code</title>
</head>
<body style="font-family: Arial, sans-serif; color: #111827; line-height: 1.4;">
    <p>Your Quoodle verification code is:</p>
    <p style="font-size: 24px; font-weight: 700; letter-spacing: 4px; margin: 12px 0;">
        {{ $code }}
    </p>
    <p>This code expires in {{ $expiresInMinutes }} minutes.</p>
    <p>If you did not request this code, you can ignore this email.</p>
</body>
</html>

