#!/bin/bash

set -euo pipefail

name=$(basename -- "$0")

install_basekit=1
install_amd=0
install_nvidia=0
patch_basekit=0

usage() {
  echo "Usage:"
  echo -e "${name}" '[--amd]' '[--nvidia]' '[--patch]' '[--help]\n'
  echo "Installs oneAPI and plugins for specified backends"
  echo "API_TOKEN must be in the environment to download plugins from Codeplay"
  exit
}

get_install() {
  if [[ ! -e packages/$(basename $1) ]]; then
    wget -P packages $1
  fi
  echo $2
  if [[ -e $VERSION_DIR ]]; then
    bash packages/$(basename $1) -a -s --install-dir $VERSION_DIR --eula accept
  else
    echo "Cannot patch when oneAPI Basekit is not installed!"
  fi
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
if [[ ($install_amd || $install_nvidia) ]]; then
  echo ${API_TOKEN:?"API_TOKEN must be set in the environment!"} > /dev/null
fi

BASE_DIR=oneapi-release
VERSION=2024.1.0
VERSION_DIR=2024.1
BASEKIT_URL=https://registrationcenter-download.intel.com/akdlm/IRC_NAS/fdc7a2bc-b7a8-47eb-8876-de6201297144/l_BaseKit_p_2024.1.0.596_offline.sh
HPCKIT_URL=https://registrationcenter-download.intel.com/akdlm/IRC_NAS/7f096850-dc7b-4c35-90b5-36c12abd9eaa/l_HPCKit_p_2024.1.0.560_offline.sh


mkdir -p $BASE_DIR/modulefiles $BASE_DIR/packages $BASE_DIR/public
pushd $BASE_DIR
if [[ "$install_basekit" == "1" ]]; then
  if [[ ! -e packages/$(basename $BASEKIT_URL) ]]; then
    wget -P packages $BASEKIT_URL
  fi
  echo "Installing oneAPI BaseKit..."
  if [[ ! -e $VERSION_DIR ]]; then
    bash packages/$(basename $BASEKIT_URL) -a -s --cli --install-dir $VERSION_DIR --eula accept
  fi
  if [[ ! -e packages/$(basename $HPCKIT_URL) ]]; then
    wget -P packages $HPCKIT_URL
  fi
  if [[ ! -e $VERSION_DIR/hpckit ]]; then
    echo "Installing oneAPI HPC Kit..."
    bash packages/$(basename $HPCKIT_URL) -a -s --cli --install-dir $VERSION_DIR --eula accept
  fi

  # Patch oneAPI Fortran and SYCL compilers
  if [[ "$patch_basekit" == "1" ]]; then
    DPCPP_URL=https://registrationcenter-download.intel.com/akdlm/IRC_NAS/b6f11fab-a0ff-4d44-a5a0-ed59d0fa971c/l_dpcpp-cpp-compiler_p_2024.1.2.504_offline.sh
    INTEL_GDB_URL=https://registrationcenter-download.intel.com/akdlm/IRC_NAS/fc87666c-d626-47bc-a861-a1578d2ecbd3/l_dpcpp_dbg_p_2024.1.0.439_offline.sh
    # TODO: fix this failing to install properly
    #INTEL_MKL_URL=https://registrationcenter-download.intel.com/akdlm/IRC_NAS/2f3a5785-1c41-4f65-a2f9-ddf9e0db3ea0/l_onemkl_p_2024.1.0.695_offline.sh
    FORTRAN_URL=https://registrationcenter-download.intel.com/akdlm/IRC_NAS/fd9342bd-7d50-442c-a3e4-f41974e14396/l_fortran-compiler_p_2024.1.0.465_offline.sh
    get_install $DPCPP_URL "Patching SYCL Compiler"
    get_install $INTEL_GDB_URL "Patching Intel GDB"
    #get_install $INTEL_MKL_URL "Patching Intel MKL"
    if [[ -e $VERSION_DIR/hpckit ]]; then
      # TODO: why is this not installing properly? missing ifx from HPC kit
      #get_install $FORTRAN_URL "Patching FORTRAN Compiler"
      echo "Skipping fortran patch step"
    fi
  fi
fi

# Download and install the plugins (but only the ones requested)
ROCM_VERSION=5.4.3
CUDA_VERSION=12.0
PLUGIN_URL=https://developer.codeplay.com/api/v1/products/download?product=oneapi
LATEST_AMD=oneapi-for-amd-gpus-$VERSION-rocm-$ROCM_VERSION-linux.sh
LATEST_NVIDIA=oneapi-for-nvidia-gpus-$VERSION-cuda-$CUDA_VERSION-linux.sh
if [[ "$install_amd" == "1" ]]; then
  rm -f packages/$LATEST_AMD
  wget -P packages --content-disposition "$PLUGIN_URL&variant=amd&version=$VERSION&filters[]=rocm-$ROCM_VERSION&filters[]=linux&aat=$API_TOKEN"
  bash packages/$LATEST_AMD -i $VERSION_DIR -y
fi
if [[ "$install_nvidia" == "1" ]]; then
  rm -f packages/$LATEST_NVIDIA
  wget -P packages --content-disposition "$PLUGIN_URL&variant=nvidia&version=$VERSION&filters[]=cuda-$CUDA_VERSION&filters[]=linux&aat=$API_TOKEN"
  bash packages/$LATEST_NVIDIA -i $VERSION_DIR -y
fi

# Installs modulefiles. Make sure WD is the install dir. If the modulefiles
# directory exists, the script asks if you'd like to remove the previous files.
# --force would make it remove without asking, but there's no --keep option,
# so we respond "no". This is fragile.
TLD=$PWD
pushd $VERSION_DIR
echo n | ./modulefiles-setup.sh --output-dir=$TLD/modulefiles
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

