import 'dart:html';

/** Just hello world! */
String greetingWords = 'Hello world!';

void main() {
  var content = querySelector('#content');
  content.text = greetingWords;
}
