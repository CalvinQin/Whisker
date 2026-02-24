import re

proj_file = "/Users/haoqiqin/Desktop/Whisker/Whisker/Whisker.xcodeproj/project.pbxproj"

with open(proj_file, 'r') as f:
    content = f.read()

# Generate fake UUIDs
file_ref_id = "UPDATE0123456789ABCDEF0"
build_file_id = "UPDATE0123456789ABCDEF1"

if "UpdateManager.swift" in content:
    print("Already in project")
    exit(0)

# Add PBXBuildFile
content = re.sub(r'(/\* Begin PBXBuildFile section \*/\n)', r'\1\t\t' + build_file_id + r' /* UpdateManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = ' + file_ref_id + r' /* UpdateManager.swift */; };\n', content)

# Add PBXFileReference
content = re.sub(r'(/\* Begin PBXFileReference section \*/\n)', r'\1\t\t' + file_ref_id + r' /* UpdateManager.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = UpdateManager.swift; sourceTree = "<group>"; };\n', content)

# Add to PBXGroup (Whisker)
# Find the Whisker group UUID
import uuid

group_match = re.search(r'([A-Z0-9]+) /\* Whisker \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n', content)
if group_match:
    group_id = group_match.group(1)
    content = re.sub(r'(' + group_id + r' /\* Whisker \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n)', r'\1\t\t\t\t' + file_ref_id + r' /* UpdateManager.swift */,\n', content)
else:
    print("Could not find Whisker group")

# Add to PBXSourcesBuildPhase
sources_match = re.search(r'([A-Z0-9]+) /\* Sources \*/ = \{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = [0-9]+;\n\t\t\tfiles = \(\n', content)
if sources_match:
    sources_id = sources_match.group(1)
    content = re.sub(r'(' + sources_id + r' /\* Sources \*/ = \{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = [0-9]+;\n\t\t\tfiles = \(\n)', r'\1\t\t\t\t' + build_file_id + r' /* UpdateManager.swift in Sources */,\n', content)
else:
    print("Could not find Sources Build Phase")

with open(proj_file, 'w') as f:
    f.write(content)

print("Added UpdateManager.swift to pbxproj")
