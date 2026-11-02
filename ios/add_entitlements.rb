require 'xcodeproj'

proj = Xcodeproj::Project.open('ios/Runner.xcodeproj')
target = proj.targets.find { |t| t.name == 'Runner' }
group = proj.main_group['Runner']

unless group.files.any? { |f| f.path == 'Runner.entitlements' }
  group.new_file('Runner.entitlements')
end

target.build_configurations.each do |c|
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

proj.save
puts 'Runner.entitlements linked'