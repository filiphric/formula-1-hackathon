require 'xcodeproj'
root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.new(File.join(root, 'FormulaLive.xcodeproj'))
target = project.new_target(:application, 'FormulaLive', :ios, '17.0')
group = project.main_group.new_group('Sources')
config_reference = project.main_group.new_file('Config.xcconfig')
Dir.glob(File.join(root, '{App,Core}', '*.swift')).sort.each do |path|
  reference = group.new_file(path.delete_prefix(root + '/'))
  target.source_build_phase.add_file_reference(reference)
end
target.build_configurations.each do |config|
  config.base_configuration_reference = config_reference
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'dev.formulalive.app',
    'PRODUCT_NAME' => 'FormulaLive',
    'MARKETING_VERSION' => '0.1.0',
    'CURRENT_PROJECT_VERSION' => '1',
    'SWIFT_VERSION' => '6.0',
    'SDKROOT' => 'auto',
    'SUPPORTED_PLATFORMS' => 'iphoneos iphonesimulator macosx',
    'TARGETED_DEVICE_FAMILY' => '1,2',
    'IPHONEOS_DEPLOYMENT_TARGET' => '17.0',
    'MACOSX_DEPLOYMENT_TARGET' => '14.0',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'INFOPLIST_KEY_CFBundleDisplayName' => 'Formula Live',
    'INFOPLIST_KEY_LSApplicationCategoryType' => 'public.app-category.sports',
    'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES',
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'YES',
    'INFOPLIST_KEY_NSLocalNetworkUsageDescription' => 'Connect to your Formula Live timing server on your local network.',
    'INFOPLIST_FILE' => 'App/Info.plist',
    'CODE_SIGN_STYLE' => 'Automatic',
    'ENABLE_APP_SANDBOX[sdk=macosx*]' => 'YES',
    'CODE_SIGN_ENTITLEMENTS[sdk=macosx*]' => 'App/FormulaLive.entitlements'
  })
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
scheme.save_as(project.path, 'FormulaLive', true)
