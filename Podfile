# Uncomment the next line to define a global platform for your project
platform :ios, '15.0'

target 'VoiceToPlist' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for VoiceToPlist

  # Note: ffmpeg-kit has been retired (Jan 2025)
  # Using AVFoundation for audio processing instead
  # SILK codec will be implemented natively using C library wrapper

end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    end
  end
end
