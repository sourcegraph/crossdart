library crossdart.args;

import 'package:args/args.dart';
import 'package:crossdart/src/config.dart';
import 'package:path/path.dart' as p;

abstract class Args {
  final List<String> _args;
  List<String> get requiredKeys;
  String get description;

  final ArgParser parser;

  Args(this._args) :
      this.parser = new ArgParser() {
    parser.addFlag("help", help: "Show help.", negatable: false);
  }

  Map<String, Object> _getResults() {
    var argsResults = parser.parse(_args);
    return argsResults.options.fold({}, (memo, option) {
      memo[option] = argsResults[option];
      return memo;
    });
  }

  Map<String, Object> _results;
  Map<String, Object> get results {
    if (_results == null) {
      _results = _getResults();
    }
    return _results;
  }

  bool get shouldShowHelp {
    return results["help"] == true;
  }

  Iterable<String> get missingRequiredKeys {
    return requiredKeys.where((k) => results[k] == null);
  }

  void showHelp([String error]) {
    print("Crossdart - Dart hyperlinked source code generator.\n");
    print("$description\n");
    if (error != null) {
      print("${error}\n");
    }
    print("Available options:");
    print(parser.usage);
  }

  void addDbArgsOptions() {
    parser.addOption(Config.DB_LOGIN, help: "Database login. Default is 'root'.");
    parser.addOption(Config.DB_PASSWORD, help: "Database password. Default is ''.");
    parser.addOption(Config.DB_HOST, help: "Database host. Default is localhost.");
    parser.addOption(Config.DB_PORT, help: "Database port. Default is 3306.");
    parser.addOption(Config.DB_NAME, help: "Database name. Default is 'crossdart'.");
  }

  void addSdkArgsOptions() {
    parser.addOption(Config.SDK_PATH, help: "Path where Dart SDK at. Required.");
  }

  bool runChecks() {
    if (shouldShowHelp) {
      showHelp();
      return false;
    } else if (missingRequiredKeys.isNotEmpty) {
      showHelp("Missing required keys: ${missingRequiredKeys.join(", ")}.");
      return false;
    } else {
      return true;
    }
  }
}

class MigrationArgs extends Args {
  List<String> get requiredKeys => [];
  String get description => "migration.dart wipes out all the data from the database and recreates its structure.";

  MigrationArgs(List<String> args) : super(args) {
    addDbArgsOptions();
  }
}

class ParsePackagesArgs extends Args {
  List<String> get requiredKeys => [Config.SDK_PATH, Config.INSTALL_PATH];
  String get description {
    return "parse_packages.dart analyzes all the packages from the pub " +
        "and stores the analyze information in the database.";
  }

  ParsePackagesArgs(List<String> args) : super(args) {
    addSdkArgsOptions();
    addDbArgsOptions();
    parser.addOption(Config.PACKAGES_PATH,
        help: "Path where the all the dependent packages will be placed at. Default is {installpath}/packages.");
    parser.addOption(Config.INSTALL_PATH, help: "Path where every package to analyze will be installed at. Required.");
  }

  Map<String, Object> _getResults() {
    var theResults = super._getResults();
    if (theResults[Config.INSTALL_PATH] != null && theResults[Config.PACKAGES_PATH] == null) {
      theResults[Config.PACKAGES_PATH] = p.join(theResults[Config.INSTALL_PATH], "packages");
    }
    return theResults;
  }
}

class CrossdartArgs extends Args {
  List<String> get requiredKeys => [Config.SDK_PATH, Config.PROJECT_PATH];
  String get description {
    return "crosdart.dart analyzes all the files of the given project, " +
        "and stores the analyze information in the crossdart.json file.";
  }

  CrossdartArgs(List<String> args) : super(args) {
    addSdkArgsOptions();
    addDbArgsOptions();
    parser.addOption(Config.OUTPUT_PATH,
        help: "Path where the crossdart.json will be generated at. Default is {projectpath}");
    parser.addOption(Config.PACKAGES_PATH,
        help: "Path where the all the dependent packages will be placed at. Default is {projectpath}/packages.");
    parser.addOption(Config.PROJECT_PATH, help: "Path where the project is located at. Required.");
  }

  Map<String, Object> _getResults() {
    var theResults = super._getResults();
    if (theResults[Config.PROJECT_PATH] != null) {
      if (theResults[Config.PACKAGES_PATH] == null) {
        theResults[Config.PACKAGES_PATH] = p.join(theResults[Config.PROJECT_PATH], "packages");
      }
      if (theResults[Config.OUTPUT_PATH] == null) {
        theResults[Config.OUTPUT_PATH] = theResults[Config.PROJECT_PATH];
      }
    }
    return theResults;
  }
}

class GeneratePackagesHtmlArgs extends Args {
  List<String> get requiredKeys => [Config.SDK_PATH, Config.OUTPUT_PATH, Config.PACKAGES_PATH, Config.TEMPLATES_PATH];
  String get description {
    return "generate_packages_html.dart reads the analysis data from the database, " +
        "and generates HTML files with the hyperlinked source code.";
  }

  GeneratePackagesHtmlArgs(List<String> args) : super(args) {
    addSdkArgsOptions();
    addDbArgsOptions();
    parser.addOption(Config.OUTPUT_PATH,
        help: "Path where the HTML files will be generated at. Required");
    parser.addOption(Config.PACKAGES_PATH,
        help: "Path where the all the packages with the source placed are. Required.");
    parser.addOption(Config.TEMPLATES_PATH,
        help: "Path where the all the auxiliary JS/CSS files are. " +
              "Usually this is just 'template' dir in the crossdart repo. Required.");
  }
}