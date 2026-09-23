require 'xcodeproj'
project_path = 'KollektivApp.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'KollektivApp' }

# Update Bundle ID
target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'no.aktivovergang'
end

# Add Assets.xcassets
group = project.main_group
file_ref = group.files.find { |f| f.path == 'Assets.xcassets' }
if file_ref.nil?
    file_ref = group.new_file('Assets.xcassets')
end

resources_build_phase = target.resources_build_phase
unless resources_build_phase.files_references.include?(file_ref)
    resources_build_phase.add_file_reference(file_ref)
end

project.save
