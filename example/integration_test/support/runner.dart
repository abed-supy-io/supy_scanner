// Shared toggles for the integration_test/ harness.
//
// `runOnDevice` is read from the `SUPY_SCANNER_DEVICE_TEST` dart-define. CI
// runs in headless mode by default; emulator/device jobs set it to true:
//
//   flutter test integration_test/ \
//     --dart-define=SUPY_SCANNER_DEVICE_TEST=true -d <device_id>
//
// Anything gated by `runOnDevice` will be skipped on host machines so the
// drivers stay green on the CI matrix without a connected device.

const bool runOnDevice = bool.fromEnvironment(
  'SUPY_SCANNER_DEVICE_TEST',
  defaultValue: false,
);
