#!/bin/sh -ex
# Builds and packages the fairtool executable for macOS and Linux
# Requires that Swiftly and the Static Linux SDK be installed:
# https://www.swift.org/documentation/articles/static-linux-getting-started.html
CONFIGURATION=${CONFIGURATION:-"release"}

# cleanup previous runs
rm -rf fairtool-bin

# Static Linux build
for ARCH in "x86_64" "aarch64"; do
    swiftly run swift build --swift-sdk "${ARCH}-swift-linux-musl" --configuration "${CONFIGURATION}" --product fairtool
    mkdir -p fairtool-bin/Linux/${ARCH}
    cp -a .build/${ARCH}-swift-linux-musl/${CONFIGURATION}/fairtool fairtool-bin/Linux/${ARCH}/
done

# macOS build
for ARCH in "x86_64" "arm64"; do
    swiftly run swift build --arch "${ARCH}" --configuration "${CONFIGURATION}" --product fairtool
    mkdir -p fairtool-bin/Darwin/${ARCH}
    cp -a .build/${ARCH}-apple-macosx/${CONFIGURATION}/fairtool fairtool-bin/Darwin/${ARCH}/
done

# alternatively, create a single "universal" binary for macOS
#mkdir -p fairtool-bin/Darwin
#lipo -create -output fairtool-bin/Darwin/fairtool .build/arm64-apple-macosx/${CONFIGURATION}/fairtool .build/x86_64-apple-macosx/${CONFIGURATION}/fairtool

# make a shell script that launches the right binary
cat > fairtool-bin/fairtool << "EOF"
#!/bin/bash
# This scipt invokes the tool named after the script
# in the appropriate OS and architecture sub-folder
set -e
TOOLNAME="$(basename "${BASH_SOURCE[0]}")"
TOOLDIR="$(dirname "${BASH_SOURCE[0]}")"
OS="$(uname -s)"
ARCH="$(uname -m)"
PROGRAM="${TOOLDIR}"/"${OS}"/"${ARCH}"/"${TOOLNAME}"
if [ "${OS}" = "Darwin" ]; then xattr -c "${PROGRAM}"; fi
"${PROGRAM}" "${@}"
EOF
chmod +x fairtool-bin/fairtool

# make sure the script works
fairtool-bin/fairtool --help

zip -9 --symlinks -r fairtool-bin.zip fairtool-bin

