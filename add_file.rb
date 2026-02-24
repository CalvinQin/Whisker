require 'xcodeproj'

project_path = 'Whisker.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.first
group = project.main_group.find_subpath(File.join('Whisker'), true)

file_path = 'UpdateManager.swift'
file_ref = group.new_file(file_path)

target.add_file_references([file_ref])

project.save
