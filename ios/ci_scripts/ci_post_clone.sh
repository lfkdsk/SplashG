#!/bin/sh
# Xcode Cloud post-clone hook. The .xcodeproj is generated from
# project.yml (and gitignored), so recreate it before the build.
set -e
brew install xcodegen
cd "$CI_PRIMARY_REPOSITORY_PATH/ios"
xcodegen generate
