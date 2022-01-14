# release_updater

[![pub package](https://img.shields.io/pub/v/release_updater.svg?logo=dart&logoColor=00b9fc)](https://pub.dev/packages/release_updater)
[![Null Safety](https://img.shields.io/badge/null-safety-brightgreen)](https://dart.dev/null-safety)
[![Codecov](https://img.shields.io/codecov/c/github/gmpassos/release_updater)](https://app.codecov.io/gh/gmpassos/release_updater)
[![CI](https://img.shields.io/github/workflow/status/gmpassos/release_updater/Dart%20CI/master?logo=github-actions&logoColor=white)](https://github.com/gmpassos/release_updater/actions)
[![GitHub Tag](https://img.shields.io/github/v/tag/gmpassos/release_updater?logo=git&logoColor=white)](https://github.com/gmpassos/release_updater/releases)
[![New Commits](https://img.shields.io/github/commits-since/gmpassos/release_updater/latest?logo=git&logoColor=white)](https://github.com/gmpassos/release_updater/network)
[![Last Commits](https://img.shields.io/github/last-commit/gmpassos/release_updater?logo=git&logoColor=white)](https://github.com/gmpassos/release_updater/commits/master)
[![Pull Requests](https://img.shields.io/github/issues-pr/gmpassos/release_updater?logo=github&logoColor=white)](https://github.com/gmpassos/release_updater/pulls)
[![Code size](https://img.shields.io/github/languages/code-size/gmpassos/release_updater?logo=github&logoColor=white)](https://github.com/gmpassos/release_updater)
[![License](https://img.shields.io/github/license/gmpassos/release_updater?logo=open-source-initiative&logoColor=green)](https://github.com/gmpassos/release_updater/blob/master/LICENSE)

This package brings a simple way to update release/installation files in a local directory.

## API Documentation

See the [API Documentation][api_doc] for a full list of functions, classes and extension.

[api_doc]: https://pub.dev/documentation/release_updater/latest/

## Usage

```dart
import 'dart:io';

import 'package:release_updater/release_updater_io.dart';

void main() async {
  var storage = ReleaseStorageDirectory('appx', Directory('/install/path'));
  var provider =
  ReleaseProviderHttp.baseURL('https://your.domain/appx/releases');

  var releaseUpdater = ReleaseUpdater(storage, provider);

  var version = await releaseUpdater.update();

  print('-- Updated to version: $version');
}
```

## ReleaseProvider

You can implement your own `ReleaseProvider` or use just the built-in [ReleaseProviderHttp][ReleaseProviderHttp_class] class.

[ReleaseProviderHttp_class]: https://pub.dev/documentation/release_updater/latest/release_updater/ReleaseProviderHttp-class.html

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
