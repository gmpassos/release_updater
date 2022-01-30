## 1.0.21

- Added support for `ReleaseManifest` and save it as `release-manifest.json`.
- crypto: ^3.0.1
- base_codecs: ^1.0.1

## 1.0.20

- Handle `HttpClient` exceptions and added retries.
- `ReleaseStorageDirectory`:
  - Added `installNewReleaseFiles`, to allow self directory storage mode.
- `ReleaseBundleZip` now stores the mode (`755`) for executable files.

## 1.0.19

- `update`:
  - Added optional parameter `force`.
  - If the current version is the same of the target version, returns `null`.

## 1.0.18

- `checkForUpdate`:
  - new parameter `currentRelease` to allow check fo current release context, and not only from local file. 

## 1.0.17

- `release_updater_server`:
  - Sort entries for routes: `RELEASES-FILES` and `RELEASES-URLS`.

## 1.0.16

- `release_updater_server`:
  - Info routes: `RELEASES`, `RELEASES-FILES` and `RELEASES-URLS`. 

## 1.0.15

- `ReleaseUpdater`:
  - Added `startPeriodicUpdateChecker` and `spawnPeriodicUpdateCheckerIsolate`.

## 1.0.14

- Fix upload of raw data.
- mercury_client: ^2.1.3

## 1.0.13

- Fix upload of release file format: platform as missing.

## 1.0.12

- Improved commands logging.
- Fix passing of release bundle to finalize commands.
- Handler `URL` request errors.
- `ReleasePackerCommandUploadReleaseBundle``:
  - Fix parameter `file` format.
  - Fix parameter `release`.
- Server:
  - Fix parse of request credential.
  - Append uploaded releases to `releases-file`.

## 1.0.11

- `ReleasePackerCommandURL`:
  - Added request logging.
- `release_packer`:
  - Improve command `info`.
  - Log prepare/finalize commands.

## 1.0.10

- Fix `ReleasePackerCommandURL` `Credential` parser.

## 1.0.9

- `release_updater_server`:
  - Upload support.
  - Block of IP by request errors or high volume of requests. 

## 1.0.8

- `ReleasePacker`:
  - Allow properties in config JSON. 
  - New commands:
    - `ReleasePackerCommandURL`
    - `ReleasePackerCommandUploadReleaseBundle`

## 1.0.7

- `ReleasePackerCommand`:
  - Improved commands error logging.
- Fix `ReleasePackerProcessCommand` execution on `Windows`.

## 1.0.6

- `ReleasePacker`:
  - Added `prepareCommands` and `finalizeCommands`.
- New `ReleasePackerCommand`:
  - `ReleasePackerCommandDelete`
  - `ReleasePackerProcessCommand`
  - `ReleasePackerDartCommand`
- Improved `README.md`:
  - Added executables usage description.
- Improved `ReleasePacker` build tests:
  - Added commands.
  - Added `prepare` and `finalize`.

## 1.0.5

- Improved path resolution, to work at `Windows` and `Linux/POSIX` transparently.

## 1.0.4

- Improved CLI executables:
  - `release_packer`:
    - Added usage message.
    - now can auto compile Dart scripts.
  - `release_updater`:
    - Added usage message.

## 1.0.3

- `ReleaseBundleZip` now can generate the `zipBytes`.
- Added `ReleasePacker`.
  - Added executable `release_packer`.
- `ReleasePlatform`: ensure that `x86_64` is treated as `x64`.
- Improved tests.
- yaml: ^3.1.0

## 1.0.2

- Added `currentReleaseFilePath` and `currentReleaseFile`.
- When loading a `ReleaseBundle` from a Zip, detected executables by file extension.
- When storing a `ReleaseFile`, ensure that the `executable` permission is set.
- Added `startReleaseProcess` and `runReleaseProcess`.
- collection: ^1.15.0

## 1.0.1

- Added support for `ReleaseBundle` from Zip file.
- Added executables:
  - `release_updater`.
  - `release_updater_server.dart`.

## 1.0.0

- Initial version.
