require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'rbconfig'
require 'xcodeproj'

class GeneratedBrandingTest < Minitest::Test
  def test_regeneration_keeps_app_icon_and_accent_on_both_platforms
    Dir.mktmpdir('formula-live-project') do |root|
      FileUtils.mkdir_p(File.join(root, 'Scripts'))
      FileUtils.mkdir_p(File.join(root, 'App', 'Assets.xcassets'))
      FileUtils.cp(File.join(__dir__, 'generate-project.rb'), File.join(root, 'Scripts'))
      assert system(RbConfig.ruby, File.join(root, 'Scripts', 'generate-project.rb'))
      target = Xcodeproj::Project.open(File.join(root, 'FormulaLive.xcodeproj')).targets.first
      assert_includes target.resources_build_phase.files_references.map(&:path), 'App/Assets.xcassets'
      target.build_configurations.each do |config|
        assert_equal 'AppIcon', config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'], config.name
        assert_equal 'AccentColor', config.build_settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'], config.name
        assert_includes config.build_settings['SUPPORTED_PLATFORMS'].split, 'macosx'
        assert_includes config.build_settings['SUPPORTED_PLATFORMS'].split, 'iphoneos'
      end
    end
  end
end
