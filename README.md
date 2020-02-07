# Dart LSIF indexer

Visit https://lsif.dev/ to learn about LSIF.

## Installation

Required tools:

- [Dart SDK](https://dart.dev/get-dart)

## Indexing your repository

Install dependencies:

```
cd $HOME/your-dart-project
pub get
```

Run lsif-dart:

```
cd $HOME
git clone https://github.com/sourcegraph/lsif-dart
cd lsif-dart
pub get
pub run crossdart --input $HOME/your-dart-project
```

## Historical notes

lsif-dart builds off of [crossdart](https://github.com/astashov/crossdart) for language analysis and adds an LSIF output mode.
