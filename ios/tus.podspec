#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint tus.podspec' to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'tus'
  s.version          = '0.0.1'
  s.summary          = 'Flutter Client for tus.io'
  s.description      = <<-DESC
Tus Flutter Client
                       DESC
  s.homepage         = 'https://github.com/frusdelion/tus-flutter-client'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Lionell Yip' => 'watonly.me@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.dependency 'TUSKit'
  s.platform = :ios, '8.0'

  # Flutter.framework does not contain a i386 slice. Only x86_64 simulators are supported.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'VALID_ARCHS[sdk=iphonesimulator*]' => 'x86_64' }
end
