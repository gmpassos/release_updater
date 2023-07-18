# release_updater

[![pub package](https://img.shields.io/pub/v/release_updater.svg?logo=dart&logoColor=00b9fc)](https://pub.dev/packages/release_updater)
[![Null Safety](https://img.shields.io/badge/null-safety-brightgreen)](https://dart.dev/null-safety)
[![Codecov](https://img.shields.io/codecov/c/github/gmpassos/release_updater)](https://app.codecov.io/gh/gmpassos/release_updater)
[![Dart CI](https://github.com/gmpassos/release_updater/actions/workflows/dart.yml/badge.svg?branch=master)](https://github.com/gmpassos/release_updater/actions/workflows/dart.yml)
[![GitHub Tag](https://img.shields.io/github/v/tag/gmpassos/release_updater?logo=git&logoColor=white)](https://github.com/gmpassos/release_updater/releases)
[![New Commits](https://img.shields.io/github/commits-since/gmpassos/release_updater/latest?logo=git&logoColor=white)](https://github.com/gmpassos/release_updater/network)
[![Last Commits](https://img.shields.io/github/last-commit/gmpassos/release_updater?logo=git&logoColor=white)](https://github.com/gmpassos/release_updater/commits/master)
[![Pull Requests](https://img.shields.io/github/issues-pr/gmpassos/release_updater?logo=github&logoColor=white)](https://github.com/gmpassos/release_updater/pulls)
[![Code size](https://img.shields.io/github/languages/code-size/gmpassos/release_updater?logo=github&logoColor=white)](https://github.com/gmpassos/release_updater)
[![License](https://img.shields.io/github/license/gmpassos/release_updater?logo=open-source-initiative&logoColor=green)](https://github.com/gmpassos/release_updater/blob/master/LICENSE)

This package brings a simple way to automatically update release/installation files in a local directory.

It also comes with built-in [CLI tools](#cli-tools) to easily generate a release bundle (Zip file) or
serve release files for multiple platforms.

## Motivation

Since [Dart][dart_overview_platforms] can run in many native platforms (Linux/x64, macOS/x64/arm64, Windows/x86),
it's not simple to manage all the different `releases`+`platforms` files that a
[compiled Dart application][dart_compile] can have.

In the same way that modern Browsers, and many other applications,
can have automatic builds and updates for multiple platforms, this package
provides [tools](#cli-tools) and an [API][api_doc] to easily achieve that.

[dart_overview_platforms]: https://dart.dev/overview#platform
[dart_compile]: https://dart.dev/tools/dart-compile

## API Documentation

See the [API Documentation][api_doc] for a full list of functions, classes and extension.

[api_doc]: https://pub.dev/documentation/release_updater/latest/

## Usage

```dart
import 'dart:io';

import 'package:release_updater/release_updater_io.dart';

void main() async {
  var storage = ReleaseStorageDirectory('appx', Directory('/install/path'));
  
  var provider = ReleaseProviderHttp.baseURL('https://your.domain/appx/releases');

  var releaseUpdater = ReleaseUpdater(storage, provider);

  var version = await releaseUpdater.update();

  print('-- Updated to version: $version');

  var runResult = await releaseUpdater.runReleaseProcess('run.exe', ['-a']);

  var exitCode = runResult!.exitCode;
  
  print('-- Exit code: $exitCode');
  print('-- Result: ${runResult.stdout}');

  exit(exitCode);
}
```

## ReleaseProvider

You can implement your own `ReleaseProvider` or use just the built-in [ReleaseProviderHttp][ReleaseProviderHttp_class] class.

[ReleaseProviderHttp_class]: https://pub.dev/documentation/release_updater/latest/release_updater.io/ReleaseProviderHttp-class.html

## CLI Tools

- `release_updater`: A `CLI` updater. 

- `release_updater_server`: A simple HTTP server to provide releases using the [shelf package][shelf].

[shelf]: https://pub.dev/packages/shelf

### release_updater

The `release_updater` is a **CLI** for the [ReleaseUpdater class][ReleaseUpdater_class].

To build a release:

```shell
$> release_packer release_packer.json build ./source-dir ./releases-dir -Pupload-url=http://your-server:8090/ -Pupload-user=userx -Pupload-pass=pass123
```

- The `-P` arguments are properties to the JSON configuration file (see `%UPLOAD_URL%` below).

Example of a `release_packer.json` file:

```json
{
  "name": "appx",
  "version_from": "pubspec.yaml",
  "prepare": [
    "dart_pub_get",
    {"dart_compile_exe": "bin/foo.dart"}
  ],
  "finalize": [
    {"rm": "bin/foo.exe"},
    {
      "upload_release": {
        "url": "%UPLOAD_URL%",
        "authorization": {
          "user": "%UPLOAD_USER%",
          "pass": "%UPLOAD_PASS%"
        }
      }
    }
  ],
  "files": [
    "README.md",
    {"hello.txt": "hello-world.txt"},
    {"bin/foo.exe": "."},
    {"libfoo-arm64.dylib": ".", "platform":  "^macos-arm64$"},
    {"libfoo-x64.dylib": ".", "platform":  "^macos-x64$"},
    {"libfoo.so": ".", "platform":  "^linux.*$"},
    {"libfoo.dll": ".", "platform":  "^windows.*$"}
  ]
}
```

#### JSON Format:

- `name`: the application name, for the [Release][Release_class] name.

- `version`: the version of the [Release][Release_class].

- `version_from`: the `JSON` or `YAML` file to provide the field `version` (if the parameter `field` is not provided).

- `platform`: is a `RegExp` string to match the building platform. See the [ReleasePlatform class][ReleasePlatform_class].

- Command types:
  - `dart_pub_get`: performs a `dart pub get`.
  - `dart_compile_exe`: performs a `dart compile exe %dart_script`.
  - `dart`: performs a `dart %command`.
  - `command`: performs a shell `%command`.
  - `rm`: Deletes a file.
  - `upload_release`: uploads the generated release.
    - `url`: release server base URL.
    - `authorization`: HTTP basic authorization.
      - `username`: authentication username.
      - `password`: authentication password.

- `files`: each entry of `files` can be:
  - A `String` with a file path:
    ```JSON
    "file/path.txt"
    ```
  - A `Map` with extra parameters:
    - A file with a renamed path and a specific platform.
      ```JSON
      {"source/file/path.txt": "release/file/path", "platform": "^regexp"}
      ```
    - A file without rename it:
      ```JSON
      {"source/file/path.txt": "."}
      ```
    - A directory tree:
      ```JSON
      {"lib/resources/": "packages/pack_name/resources/"}
      ```
    - A file from a `dart_compile_exe` command:
      ```JSON
      {"bin/client.exe": "client.exe", "dart_compile_exe": "bin/client.dart"}
      ```

[Release_class]: https://pub.dev/documentation/release_updater/latest/release_updater.io/Release-class.html  
[ReleasePlatform_class]: https://pub.dev/documentation/release_updater/latest/release_updater.io/ReleasePlatform-class.html
[ReleaseUpdater_class]: https://pub.dev/documentation/release_updater/latest/release_updater.io/ReleaseUpdater-class.html

### release_updater_server

To serve a release directory:
```shell
$> release_updater_server releases-server-config.json
```

Config file:
```JSON
{
  "releases-directory": "/path/to/releases",
  "port": 8090,
  "address": "0.0.0.0",
  "upload-user": "userx",
  "upload-pass": "123456"
}
```

- If the properties `upload-user` and `upload-pass` (with length `>= 6`) are defined,
  upload of files will be allowed.
  - All files are saved in the `releases-directory` without
    any sub-directory.
  - Upload errors can block an `IP` for **30min**.
- A high volume of requests can block an `IP` for **2min**. 

## Source

The official source code is [hosted @ GitHub][github_release_updater]:

- https://github.com/gmpassos/release_updater

[github_release_updater]: https://github.com/gmpassos/release_updater

# Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

# Contribution

Any help from the open-source community is always welcome and needed:
- Found an issue?
    - Please fill a bug report with details.
- Wish a feature?
    - Open a feature request with use cases.
- Are you using and liking the project?
    - Promote the project: create an article, do a post or make a donation.
- Are you a developer?
    - Fix a bug and send a pull request.
    - Implement a new feature, like other training algorithms and activation functions.
    - Improve the Unit Tests.
- Have you already helped in any way?
    - **Many thanks from me, the contributors and everybody that uses this project!**

*If you donate 1 hour of your time, you can contribute a lot,
because others will do the same, just be part and start with your 1 hour.*

[tracker]: https://github.com/gmpassos/release_updater/issues

# Author

Graciliano M. Passos: [gmpassos@GitHub][github].

[github]: https://github.com/gmpassos

## License

[Apache License - Version 2.0][apache_license]

[apache_license]: https://www.apache.org/licenses/LICENSE-2.0.txt
