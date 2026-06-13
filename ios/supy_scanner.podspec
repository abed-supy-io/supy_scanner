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
  s.source_files     = 'Classes/**/*.{swift,h,m}'
  s.dependency       'Flutter'
  s.platform         = :ios, '16.0'
  s.swift_version    = '5.9'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
