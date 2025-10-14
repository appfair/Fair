#!/bin/sh -ex
# Builds and packages the fairtool executable for macOS and Linux
# Requires that Swiftly and the Static Linux SDK be installed:
# https://www.swift.org/documentation/articles/static-linux-getting-started.html

TOOLNAME="fairtool"
CONFIGURATION=${CONFIGURATION:-"release"}

# cleanup previous runs
rm -rf ${TOOLNAME}-bin

# Static Linux build
for ARCH in "x86_64" "aarch64"; do
    swiftly run swift build --swift-sdk "${ARCH}-swift-linux-musl" --configuration "${CONFIGURATION}" --product ${TOOLNAME}
    mkdir -p ${TOOLNAME}-bin/Linux/${ARCH}
    cp -a .build/${ARCH}-swift-linux-musl/${CONFIGURATION}/${TOOLNAME} ${TOOLNAME}-bin/Linux/${ARCH}/
done

# macOS build
for ARCH in "x86_64" "arm64"; do
    swiftly run swift build --arch "${ARCH}" --configuration "${CONFIGURATION}" --product ${TOOLNAME}
    mkdir -p ${TOOLNAME}-bin/Darwin/${ARCH}
    cp -a .build/${ARCH}-apple-macosx/${CONFIGURATION}/${TOOLNAME} ${TOOLNAME}-bin/Darwin/${ARCH}/
done

# alternatively, create a single "universal" binary for macOS
#mkdir -p ${TOOLNAME}-bin/Darwin
#lipo -create -output ${TOOLNAME}-bin/Darwin/${TOOLNAME} .build/arm64-apple-macosx/${CONFIGURATION}/${TOOLNAME} .build/x86_64-apple-macosx/${CONFIGURATION}/${TOOLNAME}

# make a shell script that launches the right binary
cat > ${TOOLNAME}-bin/${TOOLNAME} << "EOF"
#!/bin/bash
# This scipt invokes the tool named after the script
# in the appropriate OS and architecture sub-folder
set -e
TOOLNAME="$(basename "${BASH_SOURCE[0]}")"
TOOLPATH="$(dirname "${BASH_SOURCE[0]}")"
OS="$(uname -s)"
ARCH="$(uname -m)"
PROGRAM="${TOOLPATH}"/"${OS}"/"${ARCH}"/"${TOOLNAME}"
if [ "${OS}" = "Darwin" ]; then xattr -c "${PROGRAM}"; fi
"${PROGRAM}" "${@}"
EOF
chmod +x ${TOOLNAME}-bin/${TOOLNAME}

# make sure the script works
${TOOLNAME}-bin/${TOOLNAME} --help

zip -9 --symlinks -r ${TOOLNAME}-bin.zip ${TOOLNAME}-bin

