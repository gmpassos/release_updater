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
