#!/usr/bin/env ruby
require 'digest'
require 'tmpdir'
require 'rbconfig'
require 'xcodeproj'
require 'json'
require 'open3'
root = File.expand_path('..', __dir__)
Dir.mktmpdir('nianbox-project-check') do |directory|
  project = File.join(directory, 'NianBox.xcodeproj')
  generate = lambda do
    abort 'Generation failed' unless system(RbConfig.ruby, File.join(__dir__, 'generate_project.rb'), '--output', project)
    Dir.glob("#{project}/**/*").select { |f| File.file?(f) }.sort.map { |f| File.binread(f) }.join
  end
  first = generate.call
  abort 'Non-deterministic generation' unless first == generate.call
  abort 'Obsolete platform/capability' if first.match?(/Mobile|iphone|CloudKit|ICLOUD|APS_ENVIRONMENT|HR24WHR326|emanueledipietro/i)
  targets = Xcodeproj::Project.open(project).targets
  abort 'Unexpected targets' unless targets.map(&:name).sort == %w[NianBox NianBoxTests NianBoxUITests]
  abort 'Non-macOS target' unless targets.all? { |t| t.platform_name == :osx }
  checked_in = File.join(root, 'NianBox.xcodeproj')
  abort 'Regenerate the checked-in project' unless Dir.glob("#{checked_in}/**/*").select { |f| File.file?(f) }.sort.map { |f| File.binread(f) }.join == first
end
output, status = Open3.capture2('plutil', '-convert', 'json', '-o', '-', File.join(root, 'NianBox/NianBox.entitlements'))
abort 'Invalid entitlements' unless status.success?
abort 'Unexpected entitlement' unless JSON.parse(output) == {'com.apple.security.app-sandbox'=>true,'com.apple.security.network.client'=>true}
puts 'PASS: deterministic macOS-only project, current sources, no paid capabilities'
