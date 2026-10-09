<?php
/**
 * SecurePark - Minimal SMTP client (no Composer / PHPMailer needed)
 *
 * Configure in config/secret.php (all optional until you have an SMTP account):
 *   SP_SMTP_HOST      e.g. 'smtp.gmail.com'
 *   SP_SMTP_PORT      587 (STARTTLS) / 465 (SSL) / 25   (default 587)
 *   SP_SMTP_SECURE    'tls' (STARTTLS, default) | 'ssl' | 'none'
 *   SP_SMTP_USER / SP_SMTP_PASS   login (omit for an open relay)
 *   SP_MAIL_FROM      sender address, e.g. 'securepark@ncst.edu.ph'
 *   SP_MAIL_FROM_NAME display name (default 'NCST SecurePark')
 *
 * Nothing here ever throws into the caller: spSendMail() returns [ok, error].
 * Free hosts often block outbound SMTP; a failed send is recorded, never fatal.
 */

function spMailConfigured() {
    return defined('SP_SMTP_HOST') && trim((string)SP_SMTP_HOST) !== '' && defined('SP_MAIL_FROM') && trim((string)SP_MAIL_FROM) !== '';
}

function spMailHeaderSafe($value) {
    return trim(preg_replace('/[\r\n]+/', ' ', (string)$value));
}

function spSmtpRead($fp, &$error) {
    $code = null;
    $text = '';
    while (($line = fgets($fp, 1024)) !== false) {
        $text .= $line;
        if (strlen($line) >= 4 && $line[3] === ' ') {
            return [(int)substr($line, 0, 3), $text];
        }
        if (strlen($line) < 4) break;
    }
    $meta = stream_get_meta_data($fp);
    $error = !empty($meta['timed_out']) ? 'SMTP server timed out.' : 'SMTP connection closed unexpectedly.';
    return [0, $text];
}

function spSmtpCommand($fp, $command, array $expect, &$error) {
    if ($command !== null) fwrite($fp, $command . "\r\n");
    [$code, $text] = spSmtpRead($fp, $error);
    if (!in_array($code, $expect, true)) {
        if ($error === '' || $error === null) $error = 'SMTP error: ' . trim(substr($text, 0, 200));
        return [false, $text];
    }
    return [true, $text];
}

/**
 * Sends one e-mail. $text is the plain-text body, $html an optional HTML alternative.
 * Returns [true, ''] or [false, 'reason'].
 */
function spSendMail($to, $subject, $text, $html = null) {
    $to = spMailHeaderSafe($to);
    if (!filter_var($to, FILTER_VALIDATE_EMAIL)) return [false, 'Invalid recipient address.'];
    if (!spMailConfigured()) return [false, 'SMTP is not configured on this server.'];

    $host = trim((string)SP_SMTP_HOST);
    $port = defined('SP_SMTP_PORT') ? (int)SP_SMTP_PORT : 587;
    $secure = defined('SP_SMTP_SECURE') ? strtolower((string)SP_SMTP_SECURE) : 'tls';
    $user = defined('SP_SMTP_USER') ? (string)SP_SMTP_USER : '';
    $pass = defined('SP_SMTP_PASS') ? (string)SP_SMTP_PASS : '';
    $from = spMailHeaderSafe(SP_MAIL_FROM);
    $fromName = spMailHeaderSafe(defined('SP_MAIL_FROM_NAME') ? SP_MAIL_FROM_NAME : 'NCST SecurePark');

    $error = '';
    $context = stream_context_create(['ssl' => [
        'verify_peer' => !(defined('SP_SMTP_VERIFY_TLS') && SP_SMTP_VERIFY_TLS === false),
        'verify_peer_name' => !(defined('SP_SMTP_VERIFY_TLS') && SP_SMTP_VERIFY_TLS === false),
    ]]);
    $fp = @stream_socket_client(($secure === 'ssl' ? 'ssl://' : 'tcp://') . $host . ':' . $port, $errno, $errstr, 6, STREAM_CLIENT_CONNECT, $context);
    if (!$fp) return [false, "Could not connect to {$host}:{$port} ({$errstr})."];
    stream_set_timeout($fp, 8);

    $localName = $_SERVER['SERVER_NAME'] ?? 'securepark.local';
    try {
        [$ok] = spSmtpCommand($fp, null, [220], $error);
        if (!$ok) return [false, $error];
        [$ok, $caps] = spSmtpCommand($fp, 'EHLO ' . $localName, [250], $error);
        if (!$ok) return [false, $error];

        if ($secure === 'tls') {
            if (stripos($caps, 'STARTTLS') === false) return [false, 'The SMTP server does not offer STARTTLS.'];
            [$ok] = spSmtpCommand($fp, 'STARTTLS', [220], $error);
            if (!$ok) return [false, $error];
            if (!@stream_socket_enable_crypto($fp, true, STREAM_CRYPTO_METHOD_TLS_CLIENT)) return [false, 'TLS negotiation with the SMTP server failed.'];
            [$ok] = spSmtpCommand($fp, 'EHLO ' . $localName, [250], $error);
            if (!$ok) return [false, $error];
        }

        if ($user !== '') {
            [$ok] = spSmtpCommand($fp, 'AUTH LOGIN', [334], $error);
            if (!$ok) return [false, $error];
            [$ok] = spSmtpCommand($fp, base64_encode($user), [334], $error);
            if (!$ok) return [false, $error];
            [$ok] = spSmtpCommand($fp, base64_encode($pass), [235], $error);
            if (!$ok) return [false, 'SMTP login was refused (check SP_SMTP_USER / SP_SMTP_PASS).'];
        }

        [$ok] = spSmtpCommand($fp, "MAIL FROM:<{$from}>", [250], $error);
        if (!$ok) return [false, $error];
        [$ok] = spSmtpCommand($fp, "RCPT TO:<{$to}>", [250, 251], $error);
        if (!$ok) return [false, $error];
        [$ok] = spSmtpCommand($fp, 'DATA', [354], $error);
        if (!$ok) return [false, $error];

        $boundary = 'sp_' . bin2hex(random_bytes(8));
        $encodedSubject = '=?UTF-8?B?' . base64_encode(spMailHeaderSafe($subject)) . '?=';
        $headers = [
            'Date: ' . date('r'),
            'From: =?UTF-8?B?' . base64_encode($fromName) . "?= <{$from}>",
            "To: <{$to}>",
            "Subject: {$encodedSubject}",
            'Message-ID: <' . bin2hex(random_bytes(10)) . '@' . preg_replace('/[^A-Za-z0-9.-]/', '', $localName) . '>',
            'MIME-Version: 1.0',
        ];
        $body = chunk_split(base64_encode($text), 76, "\r\n");
        if ($html !== null) {
            $headers[] = "Content-Type: multipart/alternative; boundary=\"{$boundary}\"";
            $message = "--{$boundary}\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n" . $body
                . "--{$boundary}\r\nContent-Type: text/html; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n" . chunk_split(base64_encode($html), 76, "\r\n")
                . "--{$boundary}--\r\n";
        } else {
            $headers[] = 'Content-Type: text/plain; charset=UTF-8';
            $headers[] = 'Content-Transfer-Encoding: base64';
            $message = $body;
        }
        // Base64 lines never start with "." so no dot-stuffing is needed
        fwrite($fp, implode("\r\n", $headers) . "\r\n\r\n" . $message . "\r\n.\r\n");
        [$ok] = spSmtpCommand($fp, null, [250], $error);
        if (!$ok) return [false, $error];
        @spSmtpCommand($fp, 'QUIT', [221], $error);
        return [true, ''];
    } finally {
        @fclose($fp);
    }
}
