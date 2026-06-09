import os
import shutil

source_dir = "docs"
target_dir = "docs_md"

for root, dirs, files in os.walk(source_dir):
    # Create corresponding directory in the target
    relative_path = os.path.relpath(root, source_dir)
    target_path = os.path.join(target_dir, relative_path)
    os.makedirs(target_path, exist_ok=True)

    for file in files:
        if file.endswith(".mdx"):
            source_file_path = os.path.join(root, file)
            # Change extension to .md
            new_file_name = os.path.splitext(file)[0] + ".md"
            target_file_path = os.path.join(target_path, new_file_name)
            shutil.copy2(source_file_path, target_file_path)
