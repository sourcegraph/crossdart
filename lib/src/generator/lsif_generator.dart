library crossdart.generator.lsif_generator;

import 'dart:io';
import 'dart:convert';
import 'package:crossdart/src/entity.dart';
import 'package:crossdart/src/package.dart';
import 'package:crossdart/src/environment.dart';
import 'package:crossdart/src/parsed_data.dart';
import 'package:path/path.dart' as path;
import 'package:logging/logging.dart';

var _logger = new Logger("lsif_generator");

class Emitter {
  final File file;
  Emitter(this.file);
}

void withIOSink(File file, Future Function(IOSink) f) async {
  var sink = file.openWrite();
  await f(sink);
  await sink.flush();
  await sink.close();
}

Future<String> Function(Map<String, Object>) mkEmit(IOSink sink) {
  int entryCount = 0;
  return (Map<String, Object> entry) async {
    String id = entryCount.toString();
    entryCount++;
    entry.putIfAbsent("id", () => id);
    await sink.writeln(jsonEncode(entry));
    return id;
  };
}

Future<void> withinProject(Future<String> Function(Map<String, Object>) emit,
    Future Function() inside) async {
  await emit({
    "data": 'project',
    "type": 'vertex',
    "label": 'event',
    "kind": 'begin',
    "scope": 'project',
  });
  await emit({
    "type": 'vertex',
    "label": 'project',
    "kind": 'dart',
  });
  await inside();
  await emit({
    "data": 'project',
    "type": 'vertex',
    "label": 'event',
    "kind": 'end',
    "scope": 'project',
  });
}

Future<void> withinDocuments(
    Future<String> Function(Map<String, Object>) emit,
    Iterable<String> documents,
    Future<List<String>> Function(String) inside) async {
  Map<String, String> docToID = {};
  await Future.forEach(documents, (String doc) async {
    docToID[doc] = await emit({
      "type": 'vertex',
      "label": 'document',
      // TODO needs to be relative to project root
      "uri": 'file:///' + doc,
      "languageId": 'dart',
    });
    await emit({
      "data": docToID[doc],
      "type": 'vertex',
      "label": 'event',
      "kind": 'begin',
      "scope": 'document',
    });
  });
  Map<String, List<String>> docToRanges = {};
  await Future.forEach(documents, (String doc) async {
    docToRanges[doc] = await inside(doc);
  });
  await Future.forEach(documents, (String doc) async {
    await emit({
      "type": 'edge',
      "label": 'contains',
      "outV": docToID[doc],
      "inVs": docToRanges[doc],
    });
    await emit({
      "data": docToID[doc],
      "type": 'vertex',
      "label": 'event',
      "kind": 'end',
      "scope": 'document',
    });
  });
}

class LsifGenerator {
  final Environment _environment;
  final ParsedData _parsedData;
  LsifGenerator(this._environment, this._parsedData);

  void generate() async {
    _logger.info("Generating LSIF output");
    new Directory(_environment.config.output).createSync(recursive: true);
    var file = new File(path.join(_environment.config.output, "dump.lsif"));
    var pubspecLockPath = path.join(_environment.config.input, "pubspec.lock");
    await withIOSink(file, (sink) async {
      var emit = mkEmit(sink);
      await emit({
        "id": 'meta',
        "type": 'vertex',
        "label": 'metaData',
        "projectRoot": 'file:///',
        "version": '0.4.0',
        "positionEncoding": 'utf-16',
        "toolInfo": {"name": 'crossdart', "args": [], "version": 'dev'}
      });
      await withinProject(emit, () async {
        await withinDocuments(emit, _parsedData.files.keys, (String doc) async {
          await Future.forEach(_parsedData.files.entries,
              (MapEntry<String, Set<Entity>> entry) async {
            var absolutePath = doc;
            var entities = _parsedData.files[doc];
            await emit({
              "type": "vertex",
              "label": "document",
              "uri": 'lalala',
              "languageId": 'dart'
            });
            // String relativePath = _environment.package is Sdk ?
            //   entities.first.location.package.relativePath(absolutePath) :
            //   path.join("lib", entities.first.location.package.relativePath(absolutePath));
            // result[relativePath] = {
            //   "references": _getReferencesValues(pubspecLockPath, entities, _environment.package is Sdk, isForGithub).toList()
            // };
            // if (isForGithub) {
            //   result[relativePath]["declarations"] = _getDeclarationsValues(pubspecLockPath, entities, _environment.package is Sdk).toList();
            // }
          });
          return [];
        });
      });
    });
    _logger.info("Saved LSIF output to ${file.path}");
  }

  Iterable<Map<String, Object>> _getReferencesValues(String pubspecLockPath,
      Set<Entity> entities, bool isSdk, bool isForGithub) {
    var references = entities.where((e) {
      return e is Reference &&
          (isSdk ? e.location.package is Sdk : e.location.package is Project);
    }).toList();
    references.sort((a, b) => Comparable.compare(a.offset, b.offset));
    return references.map((reference) {
      var declaration = _parsedData.references[reference];
      Map<String, Object> value = {};

      if (isForGithub) {
        value["line"] = reference.lineNumber + 1;
        value["offset"] = reference.lineOffset;
        value["length"] = reference.end - reference.offset;
        value["remotePath"] = declaration.location
            .githubRemotePath(declaration.lineNumber, pubspecLockPath, isSdk);
      } else {
        value["offset"] = reference.offset;
        value["end"] = reference.end;
        value["remotePath"] = declaration.location.crossdartRemotePath(
            declaration.lineNumber, pubspecLockPath, isSdk);
      }
      return value;
    });
  }

  Iterable<Map<String, Object>> _getDeclarationsValues(
      String pubspecLockPath, Set<Entity> entities, bool isSdk) {
    var declarations = entities.where((e) {
      return e is Declaration &&
          (isSdk ? e.location.package is Sdk : e.location.package is Project) &&
          e.offset != null;
    }).toList();
    declarations.sort((a, b) => Comparable.compare(a.offset, b.offset));
    return declarations.map((declaration) {
      var references = _parsedData.declarations[declaration];
      Map<String, Object> value = {
        "line": declaration.lineNumber + 1,
        "offset": declaration.lineOffset,
        "length": declaration.end - declaration.offset,
      };
      value["references"] = references.map((reference) {
        return {
          "remotePath": reference.location
              .githubRemotePath(reference.lineNumber, pubspecLockPath, isSdk)
        };
      }).toList();
      return value;
    });
  }
}
