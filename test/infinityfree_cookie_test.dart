import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:encrypt/encrypt.dart';

void main() {
  test('Solves InfinityFree AES challenge correctly', () {
    const htmlSample = '''<html><body><script type="text/javascript" src="/aes.js" ></script><script>function toNumbers(d){var e=[];d.replace(/(..)/g,function(d){e.push(parseInt(d,16))});return e}function toHex(){for(var d=[],d=1==arguments.length&&arguments[0].constructor==Array?arguments[0]:arguments,e="",f=0;f<d.length;f++)e+=(16>d[f]?"0":"")+d[f].toString(16);return e.toLowerCase()}var a=toNumbers("f655ba9d09a112d4968c63579db590b4"),b=toNumbers("98344c2eee86c3994890592585b49f80"),c=toNumbers("c41b9f57e0d97c665fac856c10845130");document.cookie="__test="+toHex(slowAES.decrypt(c,2,a,b))+"; max-age=21600; expires=Thu, 31-Dec-37 23:55:55 GMT; path=/"; location.href="http://ncstparking-test.rf.gd/?i=1";</script></body></html>''';

    final regA = RegExp(r'var a=toNumbers\("([0-9a-fA-F]+)"\)');
    final regB = RegExp(r'b=toNumbers\("([0-9a-fA-F]+)"\)');
    final regC = RegExp(r'c=toNumbers\("([0-9a-fA-F]+)"\)');

    final matchA = regA.firstMatch(htmlSample);
    final matchB = regB.firstMatch(htmlSample);
    final matchC = regC.firstMatch(htmlSample);

    expect(matchA, isNotNull);
    expect(matchB, isNotNull);
    expect(matchC, isNotNull);

    final keyHex = matchA!.group(1)!;
    final ivHex = matchB!.group(1)!;
    final cipherHex = matchC!.group(1)!;

    final key = Key.fromBase16(keyHex);
    final iv = IV.fromBase16(ivHex);

    // Convert hex string to bytes
    final cipherBytes = <int>[];
    for (int i = 0; i < cipherHex.length; i += 2) {
      cipherBytes.add(int.parse(cipherHex.substring(i, i + 2), radix: 16));
    }

    final encrypter = Encrypter(AES(key, mode: AESMode.cbc, padding: null));
    final decrypted = encrypter.decryptBytes(Encrypted(Uint8List.fromList(cipherBytes)), iv: iv);

    final cookieVal = decrypted.map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toLowerCase();

    // Known cookie from python test: 4a00c8d54c015bb3975329c369793ac0
    expect(cookieVal, equals('4a00c8d54c015bb3975329c369793ac0'));
  });
}
