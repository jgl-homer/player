import 'dart:io';
void main() async {
  var res = await Process.run('dart', ['analyze']);
  File('out.log').writeAsStringSync(res.stdout.toString() + "\n" + res.stderr.toString());
}
