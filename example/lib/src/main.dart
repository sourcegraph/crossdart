import 'dart:html';

String greetingWords = 'Hello world!';

void main() {
  var content = querySelector('#content');
  content.text = greetingWords;
}
