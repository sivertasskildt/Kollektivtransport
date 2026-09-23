require 'xcodeproj'
project_path = 'KollektivApp.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'KollektivApp' }
group = project.main_group
file_ref = group.new_file('TransitMapViewModel.swift')
target.add_file_references([file_ref])
project.save
