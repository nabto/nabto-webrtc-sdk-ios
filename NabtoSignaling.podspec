Pod::Spec.new do |s|
    s.name             = 'NabtoSignaling'
    s.version          = '0.1.0'
    s.summary          = 'Nabto Signaling client SDK for iOS.'
    s.homepage         = 'https://www.nabto.com/'
    s.license          = { :type => 'MIT', :file => 'LICENSE.md' }
    s.author           = { 'nabto' => 'apps@nabto.com' }
    s.source           = { :git => 'https://github.com/nabto/nabto-signaling-swift-sdk.git', :tag => s.version.to_s }
    s.ios.deployment_target = '13.0'
    s.swift_version = '5.0'
    s.source_files = 'Sources/NabtoSignaling/**/*'
end
