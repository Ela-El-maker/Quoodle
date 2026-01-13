<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

Artisan::command('jwt:generate-keys {--force : Overwrite existing keys}', function () {
    $privPath = (string) config('jwt.private_key_path');
    $pubPath = (string) config('jwt.public_key_path');

    if (! function_exists('openssl_pkey_new')) {
        $this->error('OpenSSL extension not available in PHP.');
        return 1;
    }

    $force = (bool) $this->option('force');
    if (! $force && (file_exists($privPath) || file_exists($pubPath))) {
        $this->error('JWT key(s) already exist. Use --force to overwrite.');
        $this->line("private: {$privPath}");
        $this->line("public : {$pubPath}");
        return 1;
    }

    $dir = dirname($privPath);
    if (! is_dir($dir)) {
        @mkdir($dir, 0775, true);
    }

    $this->info('Generating RSA keypair for PS256...');
    $res = openssl_pkey_new([
        'private_key_type' => OPENSSL_KEYTYPE_RSA,
        'private_key_bits' => 2048,
    ]);
    if ($res === false) {
        $this->error('openssl_pkey_new failed.');
        return 1;
    }

    $privPem = '';
    if (! openssl_pkey_export($res, $privPem)) {
        $this->error('openssl_pkey_export failed.');
        return 1;
    }

    $details = openssl_pkey_get_details($res);
    if (! is_array($details) || empty($details['key'])) {
        $this->error('openssl_pkey_get_details failed.');
        return 1;
    }
    $pubPem = (string) $details['key'];

    file_put_contents($privPath, $privPem);
    file_put_contents($pubPath, $pubPem);

    $this->info('JWT keys written:');
    $this->line("private: {$privPath}");
    $this->line("public : {$pubPath}");
    return 0;
})->purpose('Generate JWT signing keys for API tokens');
