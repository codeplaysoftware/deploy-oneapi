#!/bin/bash

set -euo pipefail

name=$(basename -- "$0")

install_amd=0
install_nvidia=0

usage() {
  echo "Usage:"
  echo -e "${name}" '[--amd]' '[--nvidia]' '[--help]\n'
  echo "Installs oneAPI and plugins for specified backends"
  echo "API_TOKEN must be in the environment to download plugins from Codeplay"
  exit
}

for arg do
  shift
  case "$arg" in
    (--help)
      usage
      ;;
    (--amd)
      install_amd=1
      ;;
    (--nvidia)
      install_nvidia=1
      ;;
    (*)
      usage
      ;;
  esac
done

# You can get an API token from the Codeplay website
if [[ -z $API_TOKEN && ($install_amd || $install_nvidia) ]]; then
  usage
fi

BASE_DIR=oneapi-release
VERSION=2024.0.1
VERSION_DIR=2024.0
BASEKIT_URL=https://registrationcenter-download.intel.com/akdlm/IRC_NAS/163da6e4-56eb-4948-aba3-debcec61c064/l_BaseKit_p_2024.0.1.46_offline.sh

mkdir -p $BASE_DIR/modulefiles $BASE_DIR/packages $BASE_DIR/public
pushd $BASE_DIR
if [[ ! -e $(basename $BASEKIT_URL) ]]; then
  wget -P packages $BASEKIT_URL
fi
echo "Installing oneAPI BaseKit..."
if [[ ! -e $VERSION_DIR ]]; then
  bash packages/$(basename $BASEKIT_URL) -a -s --install-dir $VERSION_DIR --eula accept
fi

PLUGIN_URL=https://developer.codeplay.com/api/v1/products/download?product=oneapi
LATEST_AMD=oneapi-for-amd-gpus-$VERSION-rocm-5.4.3-linux.sh
LATEST_NVIDIA=oneapi-for-nvidia-gpus-$VERSION-cuda-12.0-linux.sh
if [[ "$install_amd" == "1" ]]; then
  rm -f packages/$LATEST_AMD
  wget -P packages --content-disposition "$PLUGIN_URL&variant=amd&filters[]=linux&aat=$API_TOKEN"
  bash packages/$LATEST_AMD -i $VERSION_DIR
fi
if [[ "$install_nvidia" == "1" ]]; then
  rm -f packages/$LATEST_NVIDIA
  wget -P packages --content-disposition "$PLUGIN_URL&variant=nvidia&filters[]=linux&aat=$API_TOKEN"
  bash packages/$LATEST_NVIDIA -i $VERSION_DIR
fi

# Installs modulefiles. Make sure WD is the install dir. If the modulefiles
# directory exists, the script asks if you'd like to remove the previous files.
# --force would make it remove without asking, but there's no --keep option,
# so we respond "no" but only when asked. This is fragile.
TLD=$PWD
pushd $VERSION_DIR
if [[ -e $TLD/modulefiles ]]; then
  echo n | ./modulefiles-setup.sh --output-dir=$TLD/modulefiles
else
  ./modulefiles-setup.sh --output-dir=$TLD/modulefiles
fi
popd

cat << EOF > public/oneapi-release
#%Module1.0###################################################################
# Meta-module for oneAPI Base ToolKit Releases
#
# oneapi-release modulefile
#
proc ModulesHelp { } {
  puts stderr "\tThe oneapi-release meta-module\n"
  puts stderr "\tMakes available oneAPI Base ToolKit releases modules, use 'compiler' for the SYCL compiler"
}

module use $TLD/modulefiles
EOF
popd
echo "Installation complete! Try:"
echo "module load oneapi-release/public/oneapi-release"
echo "module load tbb compiler-rt oclfpga compiler"
echo "icpx --version"

