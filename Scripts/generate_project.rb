#!/usr/bin/env ruby
# frozen_string_literal: true

require 'xcodeproj'
require 'fileutils'
require 'optparse'
require 'securerandom'
require 'tmpdir'

ROOT = File.expand_path('..', __dir__)
DEFAULT_PROJECT_PATH = File.join(ROOT, 'NianBox.xcodeproj')
options = { project_path: DEFAULT_PROJECT_PATH }

OptionParser.new do |parser|
  parser.banner = 'Usage: ruby Scripts/generate_project.rb [options]'
  parser.on('--output PATH', 'Write the generated project to PATH') do |path|
    options[:project_path] = File.expand_path(path)
  end
  parser.on('-h', '--help', 'Show this help without changing the project') do
    puts parser
    exit
  end
end.parse!

project_path = options.fetch(:project_path)
FileUtils.mkdir_p(File.dirname(project_path))
staging_directory = Dir.mktmpdir('.nianbox-project-', File.dirname(project_path))
at_exit { FileUtils.rm_rf(staging_directory) if File.exist?(staging_directory) }
staged_project_path = File.join(staging_directory, File.basename(project_path))
# xcodeproj 1.27 can emit Xcode 16 projects but does not expose Apple's
# compatibility object version 71 as a constructor option. Generate using its
# supported format, then normalize the serialized project below.
project = Xcodeproj::Project.new(staged_project_path, false, 77)
project.root_object.attributes['LastSwiftUpdateCheck'] = '2660'
project.root_object.attributes['LastUpgradeCheck'] = '2660'
project.add_build_configuration('Local', :debug)

app = project.new_target(:application, 'NianBox', :osx, '14.0')
unit_tests = project.new_target(:unit_test_bundle, 'NianBoxTests', :osx, '14.0')
ui_tests = project.new_target(:ui_test_bundle, 'NianBoxUITests', :osx, '14.0')
unit_tests.add_dependency(app)
ui_tests.add_dependency(app)

def add_swift_sources(project, target, group_name, directory)
  group = project.main_group.new_group(group_name, group_name)
  Dir.glob(File.join(ROOT, directory, '**', '*.swift')).sort.each do |path|
    relative = path.delete_prefix("#{ROOT}/")
    reference = group.new_file(relative.delete_prefix("#{group_name}/"))
    target.source_build_phase.add_file_reference(reference)
  end
  group
end

app_group = add_swift_sources(project, app, 'NianBox', 'NianBox')
tests_group = add_swift_sources(project, unit_tests, 'NianBoxTests', 'NianBoxTests')
ui_tests_group = add_swift_sources(project, ui_tests, 'NianBoxUITests', 'NianBoxUITests')
assets = app_group.new_file('Resources/Assets.xcassets')
app.resources_build_phase.add_file_reference(assets)
app.resources_build_phase.add_file_reference(app_group.new_file('Resources/PrivacyInfo.xcprivacy'))
app_group.new_file('NianBox.entitlements')
app_group.new_file('Info.plist')
project.build_configurations.each do |config|
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
end
[app, unit_tests, ui_tests].each do |target|
  target.build_configurations.each do |config|
    settings = config.build_settings
    settings['PRODUCT_BUNDLE_IDENTIFIER'] = "org.nianbox.#{target.name}"
    settings['SWIFT_VERSION'] = '5.0'
    settings['SWIFT_STRICT_CONCURRENCY'] = 'minimal'
    settings['CODE_SIGN_IDENTITY'] = '-'
    settings['CODE_SIGN_STYLE'] = 'Manual'
    settings['GENERATE_INFOPLIST_FILE'] = target == app ? 'NO' : 'YES'
  end
end
app.build_configurations.each do |config|
  settings = config.build_settings
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['INFOPLIST_FILE'] = 'NianBox/Info.plist'
  settings['CODE_SIGN_ENTITLEMENTS'] = 'NianBox/NianBox.entitlements'
  settings['ENABLE_APP_SANDBOX'] = 'YES'
  settings['ENABLE_HARDENED_RUNTIME'] = 'YES'
  settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
  settings['MARKETING_VERSION'] = '0.1.0'
  settings['CURRENT_PROJECT_VERSION'] = '1'
end
unit_tests.build_configurations.each do |config|
  config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/NianBox.app/Contents/MacOS/NianBox'
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
end
ui_tests.build_configurations.each do |config|
  config.build_settings['TEST_TARGET_NAME'] = 'NianBox'
end

# xcodeproj includes the current random project/target UUIDs in proxy paths when
# predictabilizing target dependencies. Stable placeholders remove that random
# input; the real deterministic UUIDs are restored immediately afterwards.
target_proxies = project.objects.grep(Xcodeproj::Project::Object::PBXContainerItemProxy)
proxy_targets = target_proxies.to_h do |proxy|
  target = project.targets.find { |candidate| candidate.uuid == proxy.remote_global_id_string }
  abort "Missing target for dependency proxy #{proxy.uuid}" unless target

  [proxy, target]
end
proxy_targets.each_with_index do |(proxy, _target), index|
  proxy.container_portal = 'PROJECT'
  proxy.remote_global_id_string = "DEPENDENCY_TARGET_#{index}"
end
project.predictabilize_uuids
proxy_targets.each do |proxy, target|
  proxy.container_portal = project.root_object.uuid
  proxy.remote_global_id_string = target.uuid
end

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.launch_action.build_configuration = 'Local'
scheme.add_test_target(unit_tests)
scheme.add_test_target(ui_tests)
scheme.test_action.environment_variables = Xcodeproj::XCScheme::EnvironmentVariables.new([
  { key: 'NIANBOX_TESTING', value: '1', enabled: true }
])
scheme.save_as(staged_project_path, 'NianBox', true)

project.save

project_file = File.join(staged_project_path, 'project.pbxproj')
project_contents = File.read(project_file)
project_contents.sub!("\tobjectVersion = 77;", "\tobjectVersion = 71;")
project_contents.gsub!(/^\s*minimizedProjectReferenceProxies = 0;\n/, '')
project_contents.gsub!(/^\s*preferredProjectObjectVersion = 77;\n/, '')
File.write(project_file, project_contents)

Xcodeproj::Project.open(staged_project_path)

backup_path = "#{project_path}.backup-#{Process.pid}-#{SecureRandom.hex(4)}"
FileUtils.mv(project_path, backup_path) if File.exist?(project_path)
begin
  FileUtils.mv(staged_project_path, project_path)
rescue StandardError
  FileUtils.mv(backup_path, project_path) if File.exist?(backup_path) && !File.exist?(project_path)
  raise
ensure
  FileUtils.rm_rf(backup_path) if File.exist?(project_path)
  FileUtils.rm_rf(staging_directory)
end

puts "Generated #{project_path}"
