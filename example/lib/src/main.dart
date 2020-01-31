import 'dart:html';

/** Just hello world! */
String greetingWords = 'Hello world!';

void main() {
  var content = querySelector('#content');
  content.text = greetingWords;
  var config = new Config._(output: "some output", format: OutputFormat.LSIF);
  print(config);
}

/** Holds information about a foo. */
class Config {
  /** Absolute path to the output directory, comes from --output, defaults to --input */
  final String output;
  /** Some format. */
  final OutputFormat format;

  /** A static string. */
  static const String DART_SDK = "dart-sdk";

  Config._({this.output, this.format});
}

/** JSON, HTML, GitHub, LSIF. */
enum OutputFormat { JSON, HTML, GITHUB, LSIF }
