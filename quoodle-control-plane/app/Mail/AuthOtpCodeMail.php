<?php

namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

class AuthOtpCodeMail extends Mailable
{
    use Queueable;
    use SerializesModels;

    public function __construct(
        public readonly string $code,
        public readonly int $expiresInMinutes,
    ) {
    }

    public function envelope(): Envelope
    {
        return new Envelope(
            subject: 'Your Quoodle verification code',
        );
    }

    public function content(): Content
    {
        return new Content(
            view: 'emails.auth-otp',
        );
    }
}

