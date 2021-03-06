#! /bin/bash

set -xe

# if this is a tag build, we can use the tag name as the version
if [ "$TRAVIS_TAG" != "" ]; then
    export VERSION="$TRAVIS_TAG"
fi

# if $VERSION is set, build AppImage for that specific version, otherwise use latest version
if (grep -q "BETA" <<< "$VERSION"); then
    URL="https://download.ultimaker.com/Cura_open_beta/Cura-${VERSION}.AppImage"
else
    URLS=$(curl -s https://api.github.com/repos/Ultimaker/Cura/releases | grep browser_download_url | cut -d: -f2- | cut -d'"' -f2 | grep -E '.AppImage' | grep -v '.asc')
    if [ "$VERSION" == "" ]; then
        URL=$(echo "$URLS" | head -n1)
        export VERSION=$(echo "$URL" | python3 -c "import re, sys; print(re.search('Cura-([\d\.]+)\.AppImage', sys.stdin.read()).group(1))")
    else
        URL=$(echo "$URLS" | grep "$VERSION" | head -n1)
    fi

    if [ "$URL" == "" ]; then
        URL="https://download.ultimaker.com/cura/Ultimaker_Cura-${VERSION}.AppImage"
        curl -I -q "$URL" || URL=""
    fi
fi

if [ "$URL" == "" ]; then
    if [ "$VERSION" != "" ]; then
        echo "Error: could not find URL for user-specified version $VERSION"
    else
        echo "Error: could not determine URL for latest version"
    fi
    exit 1
fi

# use RAM disk if possible
if [ "$CI" == "" ] && [ -d /dev/shm ]; then
    TEMP_BASE=/dev/shm
else
    TEMP_BASE=/tmp
fi

BUILD_DIR=$(mktemp -d -p "$TEMP_BASE" cura-type2-appimages-build-XXXXXX)

cleanup () {
    if [ -d "$BUILD_DIR" ]; then
        rm -rf "$BUILD_DIR"
    fi
}

trap cleanup EXIT

# store repo root as variable
REPO_ROOT=$(readlink -f $(dirname "$0"))
OLD_CWD=$(readlink -f .)

pushd "$BUILD_DIR"

wget -c "$URL"

# ensure consistent filename
filename=$(ls -1 *Cura*.AppImage | head -n1)
if echo "$filename" | grep -q '^Ultimaker_'; then
    new_filename=$(echo "$filename" | cut -d_ -f2-)
    mv "$filename" "$new_filename"
    filename="$new_filename"
fi

xorriso -indev "$filename" -osirrox on -extract / AppDir

# must clean up before building new AppImage so that we won't accidentally move it to $OLD_CWD like the real AppImage
rm "$filename"

wget -c https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
chmod +x appimagetool-x86_64.AppImage

export UPD_INFO="gh-releases-zsync|TheAssassin|cura-type2-appimages|latest|Cura*-x86_64.AppImage.zsync"
./appimagetool-x86_64.AppImage -u "$UPD_INFO" AppDir

mv Cura*.AppImage* "$OLD_CWD"
