unset urls
unset files
unset log_files
unset LDFLAGS
unset CFLAGS

export ROOTDIR="${PWD}"
export BIN_NAME="hostapd"
export SD_DIR="App"
export FIN_BIN_DIR="/mnt/SDCARD/$SD_DIR/$BIN_NAME"
export CROSS_COMPILE="arm-linux-gnueabihf"
export AR=${CROSS_COMPILE}-ar
export AS=${CROSS_COMPILE}-as
export LD=${CROSS_COMPILE}-ld
export RANLIB=${CROSS_COMPILE}-ranlib
export CC=${CROSS_COMPILE}-gcc
export NM=${CROSS_COMPILE}-nm
export HOST=arm-linux-gnueabihf
export BUILD=x86_64-linux-gnu
export CFLAGS="-s -O3 -fPIC -pthread"
export CXXFLAGS="-s -O3 -fPIC -pthread"
export PATH="$PATH:$FIN_BIN_DIR/bin/"

#Copy these files to lib to stop some test failures on makes, not really needed in most cases - also stops pkgconfig working - could be ldflags
cp /opt/miyoomini-toolchain/arm-linux-gnueabihf/libc/lib/ld-linux-armhf.so.3 /lib/
cp /opt/miyoomini-toolchain/arm-linux-gnueabihf/libc/lib/libpthread.so.0 /lib/
cp /opt/miyoomini-toolchain/arm-linux-gnueabihf/libc/lib/libc.so.6 /lib/
cp /opt/miyoomini-toolchain/arm-linux-gnueabihf/libc/lib/libm.so.6 /lib/
cp /opt/miyoomini-toolchain/arm-linux-gnueabihf/libc/lib/libcrypt.so.1 /lib/
cp /opt/miyoomini-toolchain/arm-linux-gnueabihf/libc/lib/libdl.so.2 /lib/
cp /opt/miyoomini-toolchain/arm-linux-gnueabihf/libc/lib/libutil.so.1 /lib/
cp /opt/miyoomini-toolchain/arm-linux-gnueabihf/libc/lib/libstdc++.so.6 /lib/

export LOGFILE=./logs/buildtracker.txt # set a full log file
mkdir $ROOTDIR/logs

# Script header section

echo -e "\n \n -Personal hotspot dependency builder"

echo -e "-Building \033[32m"$BIN_NAME"\033[0m for: \033[32m"$CROSS_COMPILE "\033[0m"

echo -e "-Building with a prefix of \033[32m$FIN_BIN_DIR\033[0m"	

echo -e "-The build will use \033[32m"$(( $(nproc) - 2 ))"\033[0m cpu threads of the max: \033[32m"`nproc`"\033[0m"
echo  "-The script will output a list of failed makes at the end.."			
echo -e "\n"
echo -e "-Starting shortly - a full logfile with be in: \033[32m"$LOGFILE "\033[0m"
echo -e "\n"

for i in {5..1}; do
    echo -ne "Starting in $i\r"
    sleep 1
done

echo -e "\n\n\n"

while true; do # check if a build has already been completed, it may be best to do a fresh build if you've changed anything
    if [ -d "$ROOTDIR/$BIN_NAME" ]; then
        read -p "A previously completed build of $BIN_NAME already exists. Do you want to remove this & build fresh? (y/n)" rebuildq
        case "$rebuildq" in 
            y|Y ) 
                echo "Deleting previous build..."
                rm -rf $ROOTDIR/$BIN_NAME
                rm -rf $FIN_BIN_DIR
                rm -rf */ 
				rm -f wget-log*
                mkdir $ROOTDIR/logs
                mkdir -p $FIN_BIN_DIR
                break
                ;;
            n|N ) 
                echo "Rebuilding over the top of the last build..."
                break
                ;;
            * ) 
                echo "Invalid input. Please enter 'y' or 'n'."
                ;;
        esac
    else
        echo -e "\033[32mNo previous build detected, starting...\033[0m"
        break
    fi
done

cd ~/workspace/

# Start logging and begin
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1> >(tee -a "$LOGFILE") 2>&1					
# </Envsetup>

#Download everything, but check if it already exists.

urls=(
	"https://w1.fi/releases/hostapd-2.10.tar.gz"
	"https://ftp.gnu.org/gnu/m4/m4-latest.tar.xz"
	"https://www.infradead.org/~tgr/libnl/files/libnl-3.2.25.tar.gz"
	"https://pkgconfig.freedesktop.org/releases/pkg-config-0.29.2.tar.gz"
	"https://github.com/westes/flex/releases/download/v2.6.3/flex-2.6.3.tar.gz"
	"https://ftp.gnu.org/gnu/bison/bison-3.8.2.tar.xz"
	"https://www.openssl.org/source/openssl-3.1.0.tar.gz"
	"https://mirrors.edge.kernel.org/pub/software/network/iw/iw-5.9.tar.xz"
	"https://thekelleys.org.uk/dnsmasq/dnsmasq-2.89.tar.xz"
	
)

# Parallel download and wait until finished.
pids=()
for url in "${urls[@]}"; do
  file_name=$(basename "$url")
  if [ ! -f "$file_name" ]; then
    echo "Downloading $file_name..."
    wget -q "$url" &
    pids+=($!)
  else
    echo "$file_name already exists, skipping download..."
  fi
done

for pid in "${pids[@]}"; do
  wait $pid
done

echo -e "\n\n\033[32mAll downloads finished, now building..\033[0m\n\n"

# Check all files have downloaded before trying to build

files=(
    "hostapd-2.10.tar.gz"
	"m4-latest.tar.xz"
	"pkg-config-0.29.2.tar.gz"
	"libnl-3.2.25.tar.gz"
	"flex-2.6.3.tar.gz"
	"bison-3.8.2.tar.xz"
	"openssl-3.1.0.tar.gz"
	"iw-5.9.tar.xz"
	"dnsmasq-2.89.tar.xz"
)

missing_files=()
for file in "${files[@]}"; do
    if [ ! -f "$file" ]; then
        missing_files+=("$file")
    fi
done

if [ ${#missing_files[@]} -eq 0 ]; then
    echo -e "\033[32mAll files exist...\033[0m\n\n"
    sleep 1
else #check if any of the downloads failed, if they did try to redownload, if they still fail prompt for a new url with the filename..
    echo "Missing files: ${missing_files[@]}"
    echo "Trying to download again...."
    for file in "${missing_files[@]}"; do
        for url in "${urls[@]}"; do
            if [[ "$url" == *"$file"* ]]; then
                wget -q "$url"
                if [ $? -ne 0 ]; then
                    echo "Error downloading $file from $url"
                    read -p "Enter a new WORKING URL for $file: " new_url
                    wget -q "$new_url"
                fi
            fi
        done
    done
fi

## pkg config 
echo -e "-Compiling \033[32mpkconfig\033[0m"
tar -xf pkg-config-0.29.2.tar.gz &
wait $!
cd pkg-config-0.29.2
./configure CC=$CC AR=$AR RANLIB=$RANLIB LD=$LD --host=$HOST --build=$BUILD --target=$TARGET --prefix=$FIN_BIN_DIR --disable-shared --with-internal-glib glib_cv_stack_grows=no glib_cv_stack_grows=no glib_cv_uscore=no ac_cv_func_posix_getpwuid_r=yes ac_cv_func_posix_getgrgid_r=yes &
wait $!
make clean && make -j$(( $(nproc) - 2 )) && make install -j$(( $(nproc) - 2 )) > ../logs/pkgconfigbuildlog.txt 2>&1  &
wait $!
export PKG_CONFIG_PATH="$FIN_BIN_DIR/lib/pkgconfig"
export PKG_CONFIG="$FIN_BIN_DIR/bin/pkg-config"
cd ..

# m4 (required by autoconf for the M4_GNU var)
tar -xf m4-latest.tar.xz &
wait $!
cd m4-1.4.19
./configure CC=$CC --host=$HOST --build=$BUILD --prefix=$FIN_BIN_DIR --enable-shared &
wait $!
make clean && make -j$(( $(nproc) - 2 )) && make install -j$(( $(nproc) - 2 )) > ../logs/m4buildlog.txt 2>&1 &
wait $!
cd ..

# bison (required by hostapd)
echo -e "-Compiling \033[32mbison\033[0m"
tar -xf bison-3.8.2.tar.xz &
wait $!
cd bison-3.8.2
./configure CC=$CC --host=$HOST --build=$BUILD --prefix=$FIN_BIN_DIR --enable-shared &
wait $!
make clean && make -j$(( $(nproc) - 2 )) && make install -j$(( $(nproc) - 2 )) > ../logs/bisonbuildlog.txt 2>&1 &
wait $!
cd ..

# flex (required by hostapd) use flex 2.6.3 as 2.6.4 contains a segfault & dumps the core trying to make: https://lists.gnu.org/archive/html/help-octave/2017-12/msg00086.html
echo -e "-Compiling \033[32mflex\033[0m"
tar -xf flex-2.6.3.tar.gz &
wait $!
cd flex-2.6.3
CFLAGS='-g -O2 -D_GNU_SOURCE' ./configure CC=$CC --host=$HOST --build=$BUILD --prefix=$FIN_BIN_DIR --enable-shared &
wait $!
make clean && make -j$(( $(nproc) - 2 )) && make install -j$(( $(nproc) - 2 )) > ../logs/flexbuildlog.txt 2>&1 &
wait $!
cd ..

# compiles libnl (dependancy of hostapd)
echo -e "-Compiling \033[32mlibnl\033[0m"
tar -xf libnl-3.2.25.tar.gz &
wait $!
cd libnl-3.2.25
./configure CC=$CC LD=$LD --host=$HOST --build=$BUILD --target=$TARGET  --prefix=$FIN_BIN_DIR &
wait $!
make clean && make -j$(( $(nproc) - 2 )) && make install -j$(( $(nproc) - 2 )) > ../logs/libnl-3.2.25.txt 2>&1 &
wait $!
cd ..

# Compile OpenSSL (required by hostapd)
# You should be in openssl directory
echo -e "-Compiling \033[32mopenssl\033[0m"
export CROSS_COMPILE="" 
tar -xf openssl-3.1.0.tar.gz & 
wait $!
cd openssl-3.1.0
./Configure --prefix=$FIN_BIN_DIR --openssldir=$FIN_BIN_DIR linux-generic32 shared -DL_ENDIAN PROCESSOR=ARM &
wait $!
sed -i 's/-m64//g' Makefile
make clean && make -j$(( $(nproc) - 2 )) && make install -j$(( $(nproc) - 2 )) > ../logs/openssl.txt &
wait $!
cd ..
export CROSS_COMPILE="arm-linux-gnueabihf" 

# hostapd - starts the personal hotspot
echo -e "-Compiling \033[32mhostapd\033[0m"
tar -xf hostapd-2.10.tar.gz &
wait $!
cd hostapd-2.10
cd hostapd 
cp defconfig .config
sed -i '27s/.*/&\nCFLAGS += -I\/mnt\/SDCARD\/App\/hostapd\/include\//' Makefile # adds cflags
sed -i 's/export BINDIR ?= \/usr\/local\/bin/export BINDIR ?= \/mnt\/SDCARD\/App\/hostapd\/bin/' Makefile # sets output dir
export LDFLAGS="-L$FIN_BIN_DIR/lib -lnl-3 -lnl-genl-3 -lssl -lcrypto" # sets ld flags for the libs
make clean && make -j$(( $(nproc) - 2 )) && make install -j$(( $(nproc) - 2 )) > ../../logs/hostapd-2.10.txt 2>&1 &
wait $!
cd ..
cd ..

# compiles iw as a wifitool for testing
echo -e "-Compiling \033[32miwl\033[0m"
tar -xf iw-5.9.tar.xz &
wait $!
cd iw-5.9
sed -i 's#^PREFIX *=.*/usr#PREFIX = /mnt/SDCARD/App/hostapd#' Makefile #sets prefix
make clean && make -j$(( $(nproc) - 2 )) && make install -j$(( $(nproc) - 2 )) > ../logs/iw-5.9.txt 2>&1 &
wait $!
cd ..

# compiles dnsmasq for DHCP
echo -e "-Compiling \033[32mdnsmasq\033[0m"
tar -xf dnsmasq-2.89.tar.xz &
wait $!
cd dnsmasq-2.89
sed -i 's/PREFIX\s*=\s*\/usr\/local/PREFIX        = \/mnt\/SDCARD\/App\/hostapd/g' Makefile # sets prefix
make clean && make -j$(( $(nproc) - 2 )) && make install -j$(( $(nproc) - 2 )) > ../logs/dnsmasq-2.89.txt 2>&1 &
wait $!
cd ..

if [ -f "$FIN_BIN_DIR/bin/$BIN_NAME" ]; then # Check if the bin file for BINNAME exists. $FIN_BIN_DIR changes to $ROOTDIR here as it gets copied to the workspace.
	echo -e "\n\n"
	echo "Preparing export folder"
	echo -e "\n\n"
	echo "Moving built files to workspace area"
	mkdir -v $ROOTDIR/$BIN_NAME
	cp -r "$FIN_BIN_DIR/"* "$ROOTDIR/$BIN_NAME" &
	wait $!
	
	# Fix some libraries
	rm  $ROOTDIR/$BIN_NAME/lib/libnl-3.so.200
	cp  $ROOTDIR/$BIN_NAME/lib/libnl-3.so.200.20.0 $ROOTDIR/$BIN_NAME/lib/libnl-3.so.200
	rm  $ROOTDIR/$BIN_NAME/lib/libnl-genl-3.so.200
	cp  $ROOTDIR/$BIN_NAME/lib/libnl-genl-3.so.200.20.0 $ROOTDIR/$BIN_NAME/lib/libnl-genl-3.so.200
	
	cp $ROOTDIR/$BIN_NAME/sbin/dnsmasq $ROOTDIR/$BIN_NAME/bin
	cp $ROOTDIR/iw-5.9/iw $ROOTDIR/$BIN_NAME/bin
	
fi	

log_files=(				   					   
	"pkgconfigbuildlog.txt"
	"m4buildlog.txt"
	"bisonbuildlog.txt"
	"flexbuildlog.txt"
	"libnl-3.2.25.txt"
	"openssl.txt"
	"iw-5.9.txt"
	"dnsmasq-2.89.txt"
)

for log_file in "${log_files[@]}"
do
  if [ ! -f "logs/$log_file" ]; then
    echo "$log_file FAILED"
	failed_logs="$failed_logs $log_file"
	else
	echo "$log_file built OK"
  fi
done

# checks if the final product dir was moved to the /workspace/ folder, indicating it built OK
if [ -z "$failed_logs" ]; then
  if [ -d "$ROOTDIR/$BIN_NAME" ]; then
	echo -e "\033[32mComplete - your finished build is in /workspace/$BIN_NAME, this will contain all build products...\033[0m "
  else
	echo -e "Build failed, check ~/workspace/logs/buildtracker.txt for more info"
  fi
else
  if [ -d "$ROOTDIR/$BIN_NAME" ]; then
	echo -e "\033[32mComplete - your finished build is in /workspace/$BIN_NAME, this will contain all build products... "
	echo -e "These packages did not complete\033[31m$failed_logs\033[32m but it has not affected the $BIN_NAME bin being built\033[0m."
  else
	echo -e "Build failed, these packages did not complete \033[31m$failed_logs\033[0m check ~/workspace/logs/buildtracker.txt for more info"
  fi
fi	