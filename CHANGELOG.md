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
