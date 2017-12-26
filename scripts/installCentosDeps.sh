#!/usr/bin/env bash

set -e

SCRIPT=`pwd`/$0
FILENAME=`basename $SCRIPT`
PATHNAME=`dirname $SCRIPT`
ROOT=$PATHNAME/..
BUILD_DIR=$ROOT/build
CURRENT_DIR=`pwd`
NVM_CHECK="$PATHNAME"/checkNvm.sh

LIB_DIR=$BUILD_DIR/libdeps
PREFIX_DIR=$LIB_DIR/build/
FAST_MAKE=''


parse_arguments(){
  while [ "$1" != "" ]; do
    case $1 in
      "--enable-gpl")
        ENABLE_GPL=true
        ;;
      "--cleanup")
        CLEANUP=true
        ;;
      "--fast")
        FAST_MAKE='-j4'
        ;;
    esac
    shift
  done
}

check_proxy(){
  if [ -z "$http_proxy" ]; then
    echo "No http proxy set, doing nothing"
  else
    echo "http proxy configured, configuring npm"
    npm config set proxy $http_proxy
  fi

  if [ -z "$https_proxy" ]; then
    echo "No https proxy set, doing nothing"
  else
    echo "https proxy configured, configuring npm"
    npm config set https-proxy $https_proxy
  fi
}

install_nvm_node() {
  if [ -d $LIB_DIR ]; then
    export NVM_DIR=$(readlink -f "$LIB_DIR/nvm")
    if [ ! -s "$NVM_DIR/nvm.sh" ]; then
      git clone https://github.com/creationix/nvm.git "$NVM_DIR"
      cd "$NVM_DIR"
      git checkout `git describe --abbrev=0 --tags --match "v[0-9]*" origin`
      cd "$CURRENT_DIR"
    fi
    . $NVM_CHECK
    nvm install
  else
    mkdir -p $LIB_DIR
    install_nvm_node
  fi
}

install_yum_deps(){
  install_nvm_node
  nvm use
  npm install
  npm install -g node-gyp gulp-cli
  npm install webpack gulp gulp-eslint@3 run-sequence webpack-stream google-closure-compiler-js del gulp-sourcemaps script-loader expose-loader
  sudo yum install git make gcc gcc-c++ python-devel cmake
  sudo yum install curl wget
  install_rabbitmq
  install_mongodb
  sudo chown -R `whoami` ~/.npm ~/tmp/ || true
}

download_openssl() {
  OPENSSL_VERSION=$1
  OPENSSL_MAJOR="${OPENSSL_VERSION%?}"
  echo "Downloading OpenSSL from https://www.openssl.org/source/$OPENSSL_MAJOR/openssl-$OPENSSL_VERSION.tar.gz"
  curl -OL https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz
  tar -zxvf openssl-$OPENSSL_VERSION.tar.gz || DOWNLOAD_SUCCESS=$?
  if [ "$DOWNLOAD_SUCCESS" -eq 1 ]
  then
    echo "Downloading OpenSSL from https://www.openssl.org/source/old/$OPENSSL_MAJOR/openssl-$OPENSSL_VERSION.tar.gz"
    curl -OL https://www.openssl.org/source/old/$OPENSSL_MAJOR/openssl-$OPENSSL_VERSION.tar.gz
    tar -zxvf openssl-$OPENSSL_VERSION.tar.gz
  fi
}

install_openssl(){
  sudo yum install perl
  if [ -d $LIB_DIR ]; then
    cd $LIB_DIR
    OPENSSL_VERSION=`node -pe process.versions.openssl`
    if [ ! -f ./openssl-$OPENSSL_VERSION.tar.gz ]; then
      download_openssl $OPENSSL_VERSION
      cd openssl-$OPENSSL_VERSION
      ./config --prefix=$PREFIX_DIR --openssldir=$PREFIX_DIR -fPIC
      make $FAST_MAKE -s V=0
      make install_sw
    else
      echo "openssl already installed"
    fi
    cd $CURRENT_DIR
  else
    mkdir -p $LIB_DIR
    install_openssl
  fi
}

install_libnice(){
  sudo yum install pkgconfig
  sudo yum install glib2 glib2-devel
  if [ -d $LIB_DIR ]; then
    cd $LIB_DIR
    if [ ! -f ./libnice-0.1.4.tar.gz ]; then
      curl -OL https://nice.freedesktop.org/releases/libnice-0.1.4.tar.gz
      tar -zxvf libnice-0.1.4.tar.gz
      cd libnice-0.1.4
      patch -R ./agent/conncheck.c < $PATHNAME/libnice-014.patch0
      ./configure --prefix=$PREFIX_DIR
      make $FAST_MAKE -s V=0
      make install
    else
      echo "libnice already installed"
    fi
    cd $CURRENT_DIR
  else
    mkdir -p $LIB_DIR
    install_libnice
  fi
}

install_opus(){
  [ -d $LIB_DIR ] || mkdir -p $LIB_DIR
  cd $LIB_DIR
  if [ ! -f ./opus-1.1.tar.gz ]; then
    curl -OL http://downloads.xiph.org/releases/opus/opus-1.1.tar.gz
    tar -zxvf opus-1.1.tar.gz
    cd opus-1.1
    ./configure --prefix=$PREFIX_DIR
    make $FAST_MAKE -s V=0
    make install
  else
    echo "opus already installed"
  fi
  cd $CURRENT_DIR
}

install_mediadeps(){
  install_opus
  install_nasm
  install_x264
  sudo yum install libvpx-devel
  if [ -d $LIB_DIR ]; then
    cd $LIB_DIR
    if [ ! -f ./v11.1.tar.gz ]; then
      curl -O -L https://github.com/libav/libav/archive/v11.1.tar.gz
      tar -zxvf v11.1.tar.gz
      cd libav-11.1
      PKG_CONFIG_PATH=${PREFIX_DIR}/lib/pkgconfig ./configure --prefix=$PREFIX_DIR --enable-shared --enable-gpl --enable-libvpx --enable-libx264 --enable-libopus --disable-doc
      make $FAST_MAKE -s V=0
      make install
    else
      echo "libav already installed"
    fi
    cd $CURRENT_DIR
  else
    mkdir -p $LIB_DIR
    install_mediadeps
  fi

}

install_mediadeps_nogpl(){
  install_opus
  sudo yum install libvpx-devel
  if [ -d $LIB_DIR ]; then
    cd $LIB_DIR
    if [ ! -f ./v11.1.tar.gz ]; then
      curl -O -L https://github.com/libav/libav/archive/v11.1.tar.gz
      tar -zxvf v11.1.tar.gz
      cd libav-11.1
      PKG_CONFIG_PATH=${PREFIX_DIR}/lib/pkgconfig ./configure --prefix=$PREFIX_DIR --enable-shared --enable-gpl --enable-libvpx --enable-libopus --disable-doc
      make $FAST_MAKE -s V=0
      make install
    else
      echo "libav already installed"
    fi
    cd $CURRENT_DIR
  else
    mkdir -p $LIB_DIR
    install_mediadeps_nogpl
  fi
}

install_libsrtp(){
  if [ -d $LIB_DIR ]; then
    cd $LIB_DIR
    curl -o libsrtp-2.1.0.tar.gz https://codeload.github.com/cisco/libsrtp/tar.gz/v2.1.0
    tar -zxvf libsrtp-2.1.0.tar.gz
    cd libsrtp-2.1.0
    CFLAGS="-fPIC" ./configure --enable-openssl --prefix=$PREFIX_DIR --with-openssl-dir=$PREFIX_DIR
    make $FAST_MAKE -s V=0 && make uninstall && make install
    cd $CURRENT_DIR
  else
    mkdir -p $LIB_DIR
    install_libsrtp
  fi
}

install_boost(){
  sudo yum install gcc-c++ python-devel
  if [ -d $LIB_DIR ]; then
    cd $LIB_DIR
    git config --global core.autocrlf input
    git clone --recursive https://github.com/boostorg/boost.git
    cd boost
    ./bootstrap.sh --prefix=$PREFIX_DIR
    ./b2 install --prefix=$PREFIX_DIR
    cd $CURRENT_DIR
  else
    mkdir -p $LIB_DIR
    install_boost
  fi
}

install_nasm(){
  if [ -d $LIB_DIR ]; then
    cd $LIB_DIR
    wget http://www.nasm.us/pub/nasm/releasebuilds/2.13.02/nasm-2.13.02.tar.gz
    tar -zxvf nasm-2.13.02.tar.gz
    cd nasm-2.13.02
    ./configure
    make && make install
    cd $CURRENT_DIR
  else
    mkdir -p $LIB_DIR
    install_nasm
  fi
}

install_x264(){
  if [ -d $LIB_DIR ]; then
    cd $LIB_DIR
    curl -OL ftp://ftp.videolan.org/pub/videolan/x264/snapshots/x264-snapshot-20171225-2245.tar.bz2
    tar -xjf ./x264-snapshot-20171225-2245.tar.bz2
    cd x264-snapshot-20171225-2245
    ./configure --prefix=$PREFIX_DIR --enable-shared --enable-static
    make && make install
    cd $CURRENT_DIR
  else
    mkdir -p $LIB_DIR
    install_x264
  fi
}

install_apr(){
  if [ -d $LIB_DIR ]; then
    cd $LIB_DIR
    curl -OL http://mirrors.hust.edu.cn/apache//apr/apr-1.6.3.tar.gz
    tar -zxvf apr-1.6.3.tar.gz
    cd apr-1.6.3
    ./configure --prefix=$PREFIX_DIR
    make && make install
    cd $CURRENT_DIR
  else
    mkdir -p $LIB_DIR
    install_apr
  fi
}

install_aprutil(){
  install_apr
  sudo yum install expat expat-devel
  if [ -d $LIB_DIR ]; then
    cd $LIB_DIR
    curl -OL http://mirrors.hust.edu.cn/apache//apr/apr-util-1.6.1.tar.gz
    tar -zxvf apr-util-1.6.1.tar.gz
    cd apr-util-1.6.1
    ./configure --prefix=$PREFIX_DIR --with-apr=$PREFIX_DIR
    make && make install
    cd $CURRENT_DIR
  else
    mkdir -p $LIB_DIR
    install_aprutil
  fi
}

install_log4cxx10(){
  install_aprutil
  if [ -d $LIB_DIR ]; then
    cd $LIB_DIR
    curl -OL http://mirrors.tuna.tsinghua.edu.cn/apache/logging/log4cxx/0.10.0/apache-log4cxx-0.10.0.tar.gz
    tar -zxvf apache-log4cxx-0.10.0.tar.gz
    cd apache-log4cxx-0.10.0
    ./configure --prefix=$PREFIX_DIR --with-apr=$PREFIX_DIR --with-apr-util=$PREFIX_DIR
    make && make install
    cd $CURRENT_DIR
  else
    mkdir -p $LIB_DIR
    install_log4cxx10
  fi
}

install_rabbitmq(){
  if [ -d $LIB_DIR ]; then
    cd $LIB_DIR
    wget http://packages.erlang-solutions.com/erlang-solutions-1.0-1.noarch.rpm
    sudo rpm -Uvh erlang-solutions-1.0-1.noarch.rpm
    sudo yum install erlang
    wget https://www.rabbitmq.com/releases/rabbitmq-server/v3.6.1/rabbitmq-server-3.6.1-1.noarch.rpm
    sudo rpm --import https://www.rabbitmq.com/rabbitmq-signing-key-public.asc
    sudo yum install rabbitmq-server-3.6.1-1.noarch.rpm
    cd $CURRENT_DIR
  else
    mkdir -p $LIB_DIR
    install_rabbitmq
  fi
}

install_mongodb(){
  if [ -d $LIB_DIR ]; then
    cd $LIB_DIR
    git clone https://github.com/slkwyy/centos_repo.git
    cp ./centos_repo/mongodb-org-3.6.repo /etc/yum.repos.d/
    sudo yum install -y mongodb-org
    cd $CURRENT_DIR
  else
    mkdir -p $LIB_DIR
    install_mongodb
  fi
}

cleanup(){
  if [ -d $LIB_DIR ]; then
    cd $LIB_DIR
    rm -r libnice*
    rm -r libsrtp*
    rm -r boost*
    rm -r libav*
    rm -r v11*
    rm -r openssl*
    rm -r opus*
    rm -r nasm*
    rm -r x264*
    rm -r apache-log4cxx*
    rm -r apr-util*
    rm -r apr*
    rm -r erlang*
    rm -r rabbitmq-server*
    rm -r centos_repo*
    cd $CURRENT_DIR
  fi
}

parse_arguments $*

mkdir -p $PREFIX_DIR

install_yum_deps
check_proxy
install_openssl
install_libnice
install_libsrtp
install_boost
install_log4cxx10

install_opus
if [ "$ENABLE_GPL" = "true" ]; then
  install_mediadeps
else
  install_mediadeps_nogpl
fi

if [ "$CLEANUP" = "true" ]; then
  echo "Cleaning up..."
  cleanup
fi
