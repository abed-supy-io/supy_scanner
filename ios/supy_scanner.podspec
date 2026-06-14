Pod::Spec.new do |s|
  s.name             = 'supy_scanner'
  s.version          = '0.1.0'
  s.summary          = 'Supy first-party Flutter scanning library (barcode + document).'
  s.description      = <<-DESC
Native-backed Flutter scanner that replaces Scanbot SDK in Supy apps.
                       DESC
  s.homepage         = 'https://supy.io'
  s.license          = { :type => 'Proprietary', :text => 'Copyright (c) Supy Technologies. All rights reserved.' }
  s.author           = { 'Supy' => 'engineering@supy.io' }
  s.source           = { :path => '.' }

  # Swift/ObjC plugin sources + v1.1 C++ core (shared with Android via
  # ../native). See docs/V1.1_PLAN.md for the architecture decision.
  # The shared C++ core lives in ../native/{src,include}/ so Android JNI,
  # iOS, and (eventually) dart:ffi share one source of truth. The actual
  # compile of the .cpp on iOS happens via SupyNativeCoreImpl.mm, which
  # #includes the parent-dir .cpp — CocoaPods is unreliable about pulling
  # source files from a parent directory into the build phase, but it's
  # always reliable about compiling files inside Classes/.
  s.source_files = 'Classes/**/*.{swift,h,m,mm}'
  # The Obj-C `SupyNativeCoreBridge` is the only public surface Swift needs
  # to reach the C core. The C header itself is intentionally NOT public —
  # CocoaPods can't reliably fold parent-directory headers into the umbrella
  # module, and having it in the umbrella was what caused Swift to fail to
  # see `supy_core_*` symbols. The .mm file pulls it in directly via
  # HEADER_SEARCH_PATHS.
  s.public_header_files = 'Classes/nativecore/SupyNativeCoreBridge.h'
  # Keep the parent-dir sources resolvable via HEADER_SEARCH_PATHS and the
  # #include in SupyNativeCoreImpl.mm.
  s.preserve_paths = '../native/include/*.h', '../native/src/*.cpp'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/../native/include"',
    # Required so Swift can see the C symbols from supy_scanner_core.h
    # via the umbrella module.
    'SWIFT_INCLUDE_PATHS' => '"$(PODS_TARGET_SRCROOT)/../native/include"',
  }

  s.dependency       'Flutter'
  s.platform         = :ios, '16.0'
  s.swift_version    = '5.9'

  # Pure-logic XCTest suite. Run via `pod lib lint` or
  # `xcodebuild test -scheme supy_scanner-Unit-Tests`. UI/AVCapture-bound
  # classes are NOT covered here — they need a simulator.
  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'Tests/**/*.swift'
    test_spec.platforms = { :ios => '16.0' }
  end
end
