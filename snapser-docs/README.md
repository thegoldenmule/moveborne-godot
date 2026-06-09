# Snapser Documents and APIs

This repository includes the latest Snapser documents and APIs

## Helper script

### Generate Index
This script allows you to generate a Annoy index for the Snapser docs.

### Search
Helper script to test the functionality


## Steps
1. Go to `/Users/Ajinkya/Development/SnapserEngine/services` and git checkout the release branch
2. Come to the root of the docs repo `/Users/Ajinkya/Development/SnapserEngine/docs`
3. Run ./copy_swaggers.sh
4. Manually copy docs folder from `/Users/Ajinkya/Development/SnapserEngine/snapser/pages/docs` to the `/Users/Ajinkya/Development/SnapserEngine/docs/docs` folder
5. Run `python generate_index.py`