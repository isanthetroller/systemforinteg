// Unit tests for web-app-admin/js/inputs.js (Philippine mobile and driver's license rules). Run: node tests/inputs_formats.cjs
const assert = require('assert');
const path = require('path');
const { normalizePhone, normalizeLicense, formatPhoneLive, formatLicenseLive } = require(path.join(__dirname, '..', 'web-app-admin', 'js', 'inputs.js'));

let passed = 0;
const eq = (name, actual, expected) => { assert.strictEqual(actual, expected, `${name}: got ${JSON.stringify(actual)}, expected ${JSON.stringify(expected)}`); passed++; };

// ---- phone: valid forms all become +63 927 910 0511
for (const given of ['09279100511', '0927 910 0511', '+639279100511', '+63 927 910 0511', '639279100511', '9279100511', '0927-910-0511', '(0927) 910-0511', ' 09279100511 ']) {
  eq(`phone ${given}`, normalizePhone(given), '+63 927 910 0511');
}
eq('empty phone is allowed', normalizePhone(''), '');
eq('blank phone is allowed', normalizePhone('   '), '');
for (const bad of ['0927 910 051', '0927 910 05112', '0827 910 0511', '02-8123-4567', 'abc', '09279100511x', '+63 8279100511', '555-1234', '+1 202 555 0143', '927910051', '63927910051']) {
  eq(`phone ${bad} is invalid`, normalizePhone(bad), null);
}

// ---- license
for (const given of ['N01-23-456789', 'n0123456789', 'N01 23 456789', ' d12-34-567890 ', 'N0-123-456789']) {
  eq(`license ${given}`, normalizeLicense(given), given.trim().toUpperCase().replace(/[\s-]/g, '').replace(/^(.{3})(.{2})(.{6})$/, '$1-$2-$3'));
}
eq('blank license is "none"', normalizeLicense(''), '');
eq('N/A is "none"', normalizeLicense('N/A'), '');
eq('na is "none"', normalizeLicense('na'), '');
for (const bad of ['N01-23-45678', 'N01-23-4567890', '101-23-456789', 'NO-12883166', 'N01 23 45678A', 'NN1-23-456789']) {
  eq(`license ${bad} is invalid`, normalizeLicense(bad), null);
}

// ---- live typing: the field never shows characters or lengths that cannot be valid
eq('local number grouped', formatPhoneLive('09279100511'), '0927 910 0511');
eq('local number is capped at 11 digits', formatPhoneLive('0927910051199999'), '0927 910 0511');
eq('letters are dropped', formatPhoneLive('09a27b9'), '0927 9');
eq('international is capped at 12 digits', formatPhoneLive('+63927910051188'), '+63 927 910 0511');
eq('typing 63 starts the international form', formatPhoneLive('639'), '+63 9');
eq('a lone plus stays', formatPhoneLive('+'), '+');
eq('ten digit form is capped at 10', formatPhoneLive('92791005119'), '927 910 0511');
eq('empty stays empty', formatPhoneLive(''), '');
eq('license grouped', formatLicenseLive('n0123456789'), 'N01-23-456789');
eq('license is capped at 11 characters', formatLicenseLive('N0123456789999'), 'N01-23-456789');
eq('license must start with a letter', formatLicenseLive('1N0123'), 'N01-23');
eq('license letters after the first are dropped', formatLicenseLive('NAB123'), 'N12-3');
eq('license typed while partial', formatLicenseLive('N01-2'), 'N01-2');
eq('license empty', formatLicenseLive(''), '');
// a complete typed value is valid
eq('typed phone round trip', normalizePhone(formatPhoneLive('09279100511')), '+63 927 910 0511');
eq('typed license round trip', normalizeLicense(formatLicenseLive('N0123456789')), 'N01-23-456789');

console.log(`${passed} input checks passed`);
