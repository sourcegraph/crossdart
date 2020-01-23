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
  var projectId = await emit({
    "type": 'vertex',
    "label": 'project',
    "kind": 'dart',
  });
  await emit({
    "type": 'vertex',
    "label": '\$event',
    "kind": 'begin',
    "scope": 'project',
    "data": projectId,
  });
  await inside();
  await emit({
    "data": projectId,
    "type": 'vertex',
    "label": '\$event',
    "kind": 'end',
    "scope": 'project',
  });
}

Future<void> withinDocuments(
    Future<String> Function(Map<String, Object>) emit,
    Iterable<String> documents,
    Future<Map<String, List<String>>> Function() inside) async {
  Map<String, String> docToID = {};
  await Future.forEach(documents, (String doc) async {
    docToID[doc] = await emit({
      "type": 'vertex',
      "label": 'document',
      "uri": 'file://' + doc,
      "languageId": 'dart',
    });
    await emit({
      "data": docToID[doc],
      "type": 'vertex',
      "label": '\$event',
      "kind": 'begin',
      "scope": 'document',
    });
  });
  Map<String, List<String>> docToRanges = await inside();
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
      "label": '\$event',
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
        "projectRoot": "file://${_environment.config.output}",
        "version": '0.4.0',
        "positionEncoding": 'utf-16',
        "toolInfo": {"name": 'crossdart', "args": [], "version": 'dev'}
      });
      await withinProject(emit, () async {
        await withinDocuments(emit, _parsedData.files.keys, () async {
          Map<Declaration, String> declarationToId = new Map();
          List<Declaration> declarations = _parsedData.files.values
              .expand<Entity>((entries) => entries)
              .expand<Declaration>(
                  (entry) => entry is Declaration ? [entry] : [])
              .toList();
          List<Reference> references = _parsedData.files.values
              .expand<Entity>((entries) => entries)
              .expand<Reference>((entry) => entry is Reference ? [entry] : [])
              .toList();
          Map<String, List<String>> docToRanges = Map.fromIterable(declarations,
              key: (declaration) => declaration.location.file,
              value: (key) => []);

          await Future.forEach<Declaration>(declarations, (declaration) async {
            print(
                "DEF ${declaration.location.file}:${declaration.lineNumber.toString()} ${declaration.name}");

            var hoverId = await emit({
              "type": "vertex",
              "label": "hoverResult",
              "result": {
                'contents': {
                  'kind': 'markdown',
                  'value': "Hovering over: ${declaration.name}",
                }
              }
            });
            var resultSetId = await emit({
              "type": "vertex",
              "label": "resultSet",
            });

            await emit({
              "type": "edge",
              "label": "textDocument/hover",
              "outV": resultSetId,
              "inV": hoverId
            });
            var rangeId = await emit({
              "type": "vertex",
              "label": "range",
              "start": {
                "line":
                    declaration.lineNumber != null ? declaration.lineNumber : 0,
                "character":
                    declaration.lineOffset != null ? declaration.lineOffset : 0,
              },
              "end": {
                "line":
                    declaration.lineNumber != null ? declaration.lineNumber : 0,
                "character": (declaration.lineOffset != null
                        ? declaration.lineOffset
                        : 0) +
                    5,
              },
            });
            await emit({
              "type": "edge",
              "label": "next",
              "outV": rangeId,
              "inV": resultSetId
            });

            docToRanges[declaration.location.file].add(rangeId);

            declarationToId.putIfAbsent(declaration, () => resultSetId);
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
          return docToRanges;
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
