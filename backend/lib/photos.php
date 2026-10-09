<?php
/**
 * SecurePark - image data URLs sent by the apps (visitor vehicle photos).
 */

const SP_PHOTO_MAX_BYTES = 600000;

/**
 * Returns a clean 'data:image/jpeg|png;base64,...' string when $value is a valid JPEG or PNG of at most
 * SP_PHOTO_MAX_BYTES, otherwise null. Anything else (an asset path, a URL, garbage, an oversized picture) is
 * ignored rather than refused: a photo problem must never stop a pass from being issued at the gate.
 */
function validImageDataUrl($value) {
    if (!is_string($value) || $value === '') return null;
    $raw = $value;
    if (preg_match('#^data:image/(?:jpeg|jpg|png);base64,#i', $raw, $m)) {
        $raw = substr($raw, strlen($m[0]));
    } elseif (strpos($raw, 'data:') === 0 || strpos($raw, '/') !== false && strlen($raw) < 300) {
        return null; // another kind of data URL, or a file path / URL
    }
    $bin = base64_decode(str_replace(["\r", "\n", ' '], '', $raw), true);
    if ($bin === false || $bin === '' || strlen($bin) > SP_PHOTO_MAX_BYTES) return null;
    $isJpeg = substr($bin, 0, 3) === "\xFF\xD8\xFF";
    $isPng = substr($bin, 0, 8) === "\x89PNG\r\n\x1a\n";
    if (!$isJpeg && !$isPng) return null;
    return 'data:image/' . ($isPng ? 'png' : 'jpeg') . ';base64,' . base64_encode($bin);
}
