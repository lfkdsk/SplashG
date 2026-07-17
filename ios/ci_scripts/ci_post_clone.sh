#!/bin/sh
# Xcode Cloud post-clone hook. The .xcodeproj is generated from
# project.yml (and gitignored), so recreate it before the build.
set -e
brew install xcodegen
cd "$CI_PRIMARY_REPOSITORY_PATH/ios"
xcodegen generate

# Xcode Cloud disables automatic SPM resolution and expects a pinned
# Package.resolved inside the (generated, uncommitted) project. Ship the
# committed copy into place.
mkdir -p SplashG.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
cp Package.resolved SplashG.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
