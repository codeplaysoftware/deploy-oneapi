#!/bin/bash

set -euo pipefail

name=$(basename -- "$0")

install_basekit=1
install_amd=0
install_nvidia=0
patch_basekit=0

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
    (--no-basekit)
      install_basekit=0
      ;;
    (--patch)
      patch_basekit=1
      ;;
    (*)
      usage
      ;;
  esac
done

# You can get an API token from the Codeplay website
if [[ -z $API_TOKEN && ($install_amd || $install_nvidia) ]]; then
  echo "API_TOKEN has not been set in the environment!"
  usage
fi

BASE_DIR=oneapi-release
VERSION=2024.1.0
VERSION_DIR=2024.1
BASEKIT_URL=https://registrationcenter-download.intel.com/akdlm/IRC_NAS/fdc7a2bc-b7a8-47eb-8876-de6201297144/l_BaseKit_p_2024.1.0.596_offline.sh


#TODO: functions for these repeating sections
mkdir -p $BASE_DIR/modulefiles $BASE_DIR/packages $BASE_DIR/public
pushd $BASE_DIR
if [[ "$install_basekit" == "1" ]]; then
  if [[ ! -e packages/$(basename $BASEKIT_URL) ]]; then
    wget -P packages $BASEKIT_URL
  fi
  echo "Installing oneAPI BaseKit..."
  if [[ ! -e $VERSION_DIR ]]; then
    bash packages/$(basename $BASEKIT_URL) -a -s --install-dir $VERSION_DIR --eula accept
  fi

  # Patch oneAPI Fortran and SYCL compilers
  if [[ "$patch_basekit" == "1" ]]; then
    # TODO: these URLs are outdated but there's no patch version of the compiler (yet?)
    DPCPP_URL=https://registrationcenter-download.intel.com/akdlm/IRC_NAS/bb99984f-370f-413d-bbec-38928d2458f2/l_dpcpp-cpp-compiler_p_2024.0.2.29_offline.sh
    FORTRAN_URL=https://registrationcenter-download.intel.com/akdlm/IRC_NAS/41df6814-ec4b-4698-a14d-421ee2b02aa7/l_fortran-compiler_p_2024.0.2.28_offline.sh
    if [[ ! -e packages/$(basename $DPCPP_URL) ]]; then
      wget -P packages $DPCPP_URL
    fi
    echo "Patching oneAPI BaseKit SYCL Compiler..."
    if [[ -e $VERSION_DIR ]]; then
      bash packages/$(basename $DPCPP_URL) -a -s --install-dir $VERSION_DIR --eula accept
    else
      echo "Cannot patch when oneAPI Basekit is not installed!"
    fi
    if [[ ! -e packages/$(basename $FORTRAN_URL) ]]; then
      wget -P packages $FORTRAN_URL
    fi
    echo "Patching oneAPI BaseKit Fortran Compiler..."
    if [[ -e $VERSION_DIR ]]; then
      bash packages/$(basename $FORTRAN_URL) -a -s --install-dir $VERSION_DIR --eula accept
    else
      echo "Cannot patch when oneAPI Basekit is not installed!"
    fi
  fi
fi

# Download and install the plugins (but only the ones requested)
PLUGIN_URL=https://developer.codeplay.com/api/v1/products/download?product=oneapi
LATEST_AMD=oneapi-for-amd-gpus-$VERSION-rocm-5.4.3-linux.sh
LATEST_NVIDIA=oneapi-for-nvidia-gpus-$VERSION-cuda-12.0-linux.sh
if [[ "$install_amd" == "1" ]]; then
  rm -f packages/$LATEST_AMD
  wget -P packages --content-disposition "$PLUGIN_URL&variant=amd&version=$VERSION&filters[]=linux&aat=$API_TOKEN"
  bash packages/$LATEST_AMD -i $VERSION_DIR
fi
if [[ "$install_nvidia" == "1" ]]; then
  rm -f packages/$LATEST_NVIDIA
  wget -P packages --content-disposition "$PLUGIN_URL&variant=nvidia&version=$VERSION&filters[]=linux&aat=$API_TOKEN"
  bash packages/$LATEST_NVIDIA -i $VERSION_DIR
fi

# Installs modulefiles. Make sure WD is the install dir. If the modulefiles
# directory exists, the script asks if you'd like to remove the previous files.
# --force would make it remove without asking, but there's no --keep option,
# so we respond "no". This is fragile.
TLD=$PWD
pushd $VERSION_DIR
yes n | ./modulefiles-setup.sh --output-dir=$TLD/modulefiles
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

