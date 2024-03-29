#!/bin/bash

# https://github.com/markus-perl/ffmpeg-build-script

VERSION=1.4
CWD=$(pwd)
PACKAGES="$CWD/packages"
DOWNLOADS="$CWD/downloads"
WORKSPACE="$CWD/workspace"
CC=clang
LDFLAGS="-L${WORKSPACE}/lib -lm"
CFLAGS="-I${WORKSPACE}/include"
PKG_CONFIG_PATH="${WORKSPACE}/lib/pkgconfig"
ADDITIONAL_CONFIGURE_OPTIONS=""

# Speed up the process
# Env Var NUMJOBS overrides automatic detection
if [[ -n $NUMJOBS ]]; then
    MJOBS=$NUMJOBS
elif [[ -f /proc/cpuinfo ]]; then
    MJOBS=$(grep -c processor /proc/cpuinfo)
elif [[ "$OSTYPE" == "darwin"* ]]; then
	MJOBS=$(sysctl -n machdep.cpu.thread_count)
	ADDITIONAL_CONFIGURE_OPTIONS="--enable-videotoolbox"
else
    MJOBS=4
fi

make_dir () {
	if [ ! -d $1 ]; then
		if ! mkdir $1; then
			printf "\n Failed to create dir %s" "$1";
			exit 1
		fi
	fi
}

remove_dir () {
	if [ -d $1 ]; then
		rm -r "$1"
	fi
}

download () {
	DOWNLOAD_PATH=$PACKAGES;
	if [ ! -z "$3" ]; then
		mkdir -p $PACKAGES/$3
		DOWNLOAD_PATH=$PACKAGES/$3
	fi;
    
    if ! tar -xvf "$DOWNLOADS/$2" -C "$DOWNLOAD_PATH" 2>/dev/null >/dev/null; then
        echo "Failed to extract $2";
        exit 1
    fi
}

execute () {
	echo "$ $*"

	OUTPUT=$($@ 2>&1)

	if [ $? -ne 0 ]; then
        echo "$OUTPUT"
        echo ""
        echo "Failed to Execute $*" >&2
        exit 1
    fi
}

build () {
	echo ""
	echo "building $1"
	echo "======================="

	if [ -f "$PACKAGES/$1.done" ]; then
		echo "$1 already built. Remove $PACKAGES/$1.done lockfile to rebuild it."
		return 1
	fi

	return 0
}

command_exists() {
    if ! [[ -x $(command -v "$1") ]]; then
        return 1
    fi

    return 0
}


build_done () {
	touch "$PACKAGES/$1.done"
}

echo "ffmpeg-build-script v$VERSION"
echo "========================="
echo ""

case "$1" in
"--cleanup")
	remove_dir $PACKAGES
	remove_dir $WORKSPACE
	echo "Cleanup done."
	echo ""
	exit 0
    ;;
"--build")

    ;;
*)
    echo "Usage: $0"
    echo "   --build: start building process"
    echo "   --cleanup: remove all working dirs"
    echo "   --help: show this help"
    echo ""
    exit 0
    ;;
esac

echo "Using $MJOBS make jobs simultaneously."

make_dir $PACKAGES
make_dir $WORKSPACE

export PATH=${WORKSPACE}/bin:$PATH

if ! command_exists "make"; then
    echo "make not installed.";
    exit 1
fi

if ! command_exists "g++"; then
    echo "g++ not installed.";
    exit 1
fi

if ! command_exists "curl"; then
    echo "curl not installed.";
    exit 1
fi

if build "yasm"; then
	download "http://www.tortall.net/projects/yasm/releases/yasm-1.3.0.tar.gz" "yasm-1.3.0.tar.gz"
	cd $PACKAGES/yasm-1.3.0 || exit
	execute ./configure --prefix=${WORKSPACE}
	execute make -j $MJOBS
	execute make install
	build_done "yasm"
fi

if build "nasm"; then
	download "https://www.nasm.us/pub/nasm/releasebuilds/2.14.02/nasm-2.14.02.tar.gz" "nasm.tar.gz"
	cd $PACKAGES/nasm-2.14.02 || exit
	execute ./configure --prefix=${WORKSPACE} --disable-shared --enable-static
	execute make -j $MJOBS
	execute make install
	build_done "nasm"
fi

if build "opencore"; then
	download "http://downloads.sourceforge.net/project/opencore-amr/opencore-amr/opencore-amr-0.1.5.tar.gz?r=http%3A%2F%2Fsourceforge.net%2Fprojects%2Fopencore-amr%2Ffiles%2Fopencore-amr%2F&ts=1442256558&use_mirror=netassist" "opencore-amr-0.1.5.tar.gz"
	cd $PACKAGES/opencore-amr-0.1.5 || exit
	execute ./configure --prefix=${WORKSPACE} --disable-shared --enable-static
	execute make -j $MJOBS
	execute make install
	build_done "opencore"
fi

if build "libvpx"; then
    download "https://github.com/webmproject/libvpx/archive/v1.7.0.tar.gz" "libvpx-1.7.0.tar.gz"
    cd $PACKAGES/libvpx-*0 || exit

    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "Applying Darwin patch"
        sed "s/,--version-script//g" build/make/Makefile > build/make/Makefile.patched
        sed "s/-Wl,--no-undefined -Wl,-soname/-Wl,-undefined,error -Wl,-install_name/g" build/make/Makefile.patched > build/make/Makefile
    fi

	execute ./configure --prefix=${WORKSPACE} --disable-unit-tests --disable-shared
	execute make -j $MJOBS
	execute make install
	build_done "libvpx"
fi

if build "lame"; then
	download "http://kent.dl.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz" "lame-3.100.tar.gz"
	cd $PACKAGES/lame-3.100 || exit
	execute ./configure --prefix=${WORKSPACE} --disable-shared --enable-static
	execute make -j $MJOBS
	execute make install
	build_done "lame"
fi

if build "xvidcore"; then
	download "https://downloads.xvid.com/downloads/xvidcore-1.3.5.tar.gz" "xvidcore-1.3.5.tar.gz"
	cd $PACKAGES/xvidcore  || exit
	cd build/generic  || exit
	execute ./configure --prefix=${WORKSPACE} --disable-shared --enable-static
	execute make -j $MJOBS
	execute make install

	if [[ -f ${WORKSPACE}/lib/libxvidcore.4.dylib ]]; then
	    execute rm "${WORKSPACE}/lib/libxvidcore.4.dylib"
	fi

	build_done "xvidcore"
fi

if build "x264"; then
	download "http://ftp.videolan.org/pub/x264/snapshots/x264-snapshot-20190204-2245-stable.tar.bz2" "last_x264.tar.bz2"
	cd $PACKAGES/x264-snapshot-* || exit

	if [[ "$OSTYPE" == "linux-gnu" ]]; then
		execute ./configure --prefix=${WORKSPACE} --enable-static --enable-pic CXXFLAGS="-fPIC"
    else
        execute ./configure --prefix=${WORKSPACE} --enable-static --enable-pic
    fi

    execute make -j $MJOBS
	execute make install
	execute make install-lib-static
	build_done "x264"
fi

if build "libogg"; then
	download "http://downloads.xiph.org/releases/ogg/libogg-1.3.3.tar.gz" "libogg-1.3.3.tar.gz"
	cd $PACKAGES/libogg-1.3.3 || exit
	execute ./configure --prefix=${WORKSPACE} --disable-shared --enable-static
	execute make -j $MJOBS
	execute make install
	build_done "libogg"
fi

if build "libvorbis"; then
	download "http://downloads.xiph.org/releases/vorbis/libvorbis-1.3.6.tar.gz" "libvorbis-1.3.6.tar.gz"
	cd $PACKAGES/libvorbis-1.3.6 || exit
	execute ./configure --prefix=${WORKSPACE} --with-ogg-libraries=${WORKSPACE}/lib --with-ogg-includes=${WORKSPACE}/include/ --enable-static --disable-shared --disable-oggtest
	execute make -j $MJOBS
	execute make install
	build_done "libvorbis"
fi

if build "libtheora"; then
	download "http://downloads.xiph.org/releases/theora/libtheora-1.1.1.tar.gz" "libtheora-1.1.1.tar.bz"
	cd $PACKAGES/libtheora-1.1.1 || exit
	sed "s/-fforce-addr//g" configure > configure.patched
	chmod +x configure.patched
	mv configure.patched configure
	execute ./configure --prefix=${WORKSPACE} --with-ogg-libraries=${WORKSPACE}/lib --with-ogg-includes=${WORKSPACE}/include/ --with-vorbis-libraries=${WORKSPACE}/lib --with-vorbis-includes=${WORKSPACE}/include/ --enable-static --disable-shared --disable-oggtest --disable-vorbistest --disable-examples --disable-asm --disable-spec
	execute make -j $MJOBS
	execute make install
	build_done "libtheora"
fi

if build "pkg-config"; then
	download "http://pkgconfig.freedesktop.org/releases/pkg-config-0.29.2.tar.gz" "pkg-config-0.29.2.tar.gz"
	cd $PACKAGES/pkg-config-0.29.2 || exit
	execute ./configure --silent --prefix=${WORKSPACE} --with-pc-path=${WORKSPACE}/lib/pkgconfig --with-internal-glib
	execute make -j $MJOBS
	execute make install
	build_done "pkg-config"
fi


if build "cmake"; then
	download "https://cmake.org/files/v3.11/cmake-3.11.3.tar.gz" "cmake-3.11.3.tar.gz"
	cd $PACKAGES/cmake-3.11.3  || exit
	rm Modules/FindJava.cmake
	perl -p -i -e "s/get_filename_component.JNIPATH/#get_filename_component(JNIPATH/g" Tests/CMakeLists.txt
	perl -p -i -e "s/get_filename_component.JNIPATH/#get_filename_component(JNIPATH/g" Tests/CMakeLists.txt
    echo "" > Tests/RunCMake/CMakeLists.txt
    echo "" > Tests/CMakeLists.txt
	execute ./configure --prefix=${WORKSPACE} --no-system-libs --no-qt-gui 
	execute make -j $MJOBS
	execute make install
	build_done "cmake"
fi

if build "vid_stab"; then
	download "https://github.com/georgmartius/vid.stab/archive/v1.1.0.tar.gz" "georgmartius-vid.stab-v1.1.0-0-g60d65da.tar.tgz"
	cd $PACKAGES/vid.stab-1.1.0 || exit
	execute ${WORKSPACE}/bin/cmake -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX:PATH=${WORKSPACE} -DUSE_OMP=OFF -DENABLE_SHARED:bool=off .
	execute make
	execute make install
	build_done "vid_stab"
fi

if build "x265"; then
	download "https://bitbucket.org/multicoreware/x265/downloads/x265_3.0.tar.gz" "x265-3.0.tar.gz"
	cd $PACKAGES/x265_* || exit
	cd source || exit
	execute ${WORKSPACE}/bin/cmake -DCMAKE_INSTALL_PREFIX:PATH=${WORKSPACE} -DENABLE_SHARED:bool=off .
	execute make -j $MJOBS
	execute make install
	sed "s/-lx265/-lx265 -lstdc++/g" "$WORKSPACE/lib/pkgconfig/x265.pc" > "$WORKSPACE/lib/pkgconfig/x265.pc.tmp"
	mv "$WORKSPACE/lib/pkgconfig/x265.pc.tmp" "$WORKSPACE/lib/pkgconfig/x265.pc"
	build_done "x265"
fi

if build "fdk_aac"; then
	download "http://downloads.sourceforge.net/project/opencore-amr/fdk-aac/fdk-aac-0.1.6.tar.gz?r=https%3A%2F%2Fsourceforge.net%2Fprojects%2Fopencore-amr%2Ffiles%2Ffdk-aac%2F&ts=1457561564&use_mirror=kent" "fdk-aac-0.1.6.tar.gz"
	cd $PACKAGES/fdk-aac-0.1.6 || exit
	execute ./configure --prefix=${WORKSPACE} --disable-shared --enable-static
	execute make -j $MJOBS
	execute make install
	build_done "fdk_aac"
fi

if build "av1"; then
	download "https://aomedia.googlesource.com/aom/+archive/52ea88fd18719bac1acfa6847f834ae6d2ae136f.tar.gz" "av1.tar.gz" "av1"
	cd $PACKAGES/av1 || exit
	mkdir -p $PACKAGES/aom_build
	cd $PACKAGES/aom_build
	execute ${WORKSPACE}/bin/cmake -DENABLE_TESTS=0 -DCMAKE_INSTALL_PREFIX:PATH=${WORKSPACE} $PACKAGES/av1
	execute make -j $MJOBS
	execute make install
	build_done "av1"
fi


build "ffmpeg"
download "http://ffmpeg.org/releases/ffmpeg-4.1.4.tar.bz2" "ffmpeg-4.1.4.tar.bz2"
cd $PACKAGES/ffmpeg-4.1.4 || exit
./configure $ADDITIONAL_CONFIGURE_OPTIONS \
    --pkgconfigdir="$WORKSPACE/lib/pkgconfig" \
    --prefix=${WORKSPACE} \
    --pkg-config-flags="--static" \
    --extra-cflags="-I$WORKSPACE/include" \
    --extra-ldflags="-L$WORKSPACE/lib" \
    --extra-libs="-lpthread -lm" \
	--enable-static \
	--disable-debug \
	--disable-shared \
	--disable-ffplay \
	--disable-lzma \
	--disable-sdl2 \
	--disable-bzlib \
	--disable-zlib \
	--disable-iconv \
	--disable-doc \
	--enable-gpl \
	--enable-version3 \
	--enable-nonfree \
	--enable-pthreads \
	--enable-libvpx \
	--enable-libmp3lame \
	--enable-libtheora \
	--enable-libvorbis \
	--enable-libx264 \
	--enable-libx265 \
	--enable-runtime-cpudetect \
	--enable-libfdk-aac \
	--enable-avfilter \
	--enable-libopencore_amrwb \
	--enable-libopencore_amrnb \
	--enable-filters \
	--enable-libvidstab \
	--enable-libaom

execute make -j $MJOBS
execute make install

    INSTALL_FOLDER="/usr/bin"
if [[ "$OSTYPE" == "darwin"* ]]; then
INSTALL_FOLDER="/usr/local/bin"
fi

echo ""
echo "Building done. The binary can be found here: $WORKSPACE/bin/ffmpeg"
echo ""


if [[ $AUTOINSTALL == "yes" ]]; then
	if command_exists "sudo"; then
		sudo cp "$WORKSPACE/bin/ffmpeg" "$INSTALL_FOLDER/ffmpeg"
		sudo cp "$WORKSPACE/bin/ffprobe" "$INSTALL_FOLDER/ffprobe"
		echo "Done. ffmpeg is now installed to your system"
	fi
elif [[ ! $SKIPINSTALL == "yes" ]]; then
	if command_exists "sudo"; then

		read -r -p "Install the binary to your $INSTALL_FOLDER folder? [Y/n] " response

		case $response in
    		[yY][eE][sS]|[yY])
        		sudo cp "$WORKSPACE/bin/ffmpeg" "$INSTALL_FOLDER/ffmpeg"
        		sudo cp "$WORKSPACE/bin/ffprobe" "$INSTALL_FOLDER/ffprobe"
        		echo "Done. ffmpeg is now installed to your system"
        		;;
		esac
	fi
fi

exit 0
