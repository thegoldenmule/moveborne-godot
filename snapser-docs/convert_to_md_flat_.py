import os
import shutil

source_dir = "docs"
target_dir = "docs_md_flat"

os.makedirs(target_dir, exist_ok=True)

for root, _, files in os.walk(source_dir):
    for file in files:
        if file.endswith(".mdx"):
            source_file_path = os.path.join(root, file)

            # Create a unique flat filename using the relative path
            relative_path = os.path.relpath(source_file_path, source_dir)
            # Replace folder separators with _
            flat_name = relative_path.replace(os.sep, "_")
            new_file_name = os.path.splitext(
                flat_name)[0] + ".md"  # Change extension to .md

            target_file_path = os.path.join(target_dir, new_file_name)
            shutil.copy2(source_file_path, target_file_path)
