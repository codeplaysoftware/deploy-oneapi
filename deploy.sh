#!/bin/bash

set -euo pipefail

name=$(basename -- "$0")

install_basekit=1
install_amd=0
install_nvidia=0
patch_basekit=0
install_modulefiles=1

usage() {
  echo "Usage:"
  echo -e "${name}" '[--amd]' '[--nvidia]' '[--patch]' '[--no-basekit]' '[--no-modulefiles]' '[--help]\n'
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
    (--no-modulefiles)
      install_modulefiles=0
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
VERSION=2024.2.0
VERSION_DIR=2024.2
BASEKIT_URL=https://registrationcenter-download.intel.com/akdlm/IRC_NAS/9a98af19-1c68-46ce-9fdd-e249240c7c42/l_BaseKit_p_2024.2.0.634_offline.sh
HPCKIT_URL=https://registrationcenter-download.intel.com/akdlm/IRC_NAS/d4e49548-1492-45c9-b678-8268cb0f1b05/l_HPCKit_p_2024.2.0.635_offline.sh


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

  # Patch individual components
  if [[ "$patch_basekit" == "1" ]]; then
    DPCPP_URL=https://registrationcenter-download.intel.com/akdlm/IRC_NAS/6780ac84-6256-4b59-a647-330eb65f32b6/l_dpcpp-cpp-compiler_p_2024.2.0.495_offline.sh
    INTEL_GDB_URL=https://registrationcenter-download.intel.com/akdlm/IRC_NAS/39f749d1-78e5-4a14-a4b2-5c17b6963a79/l_dpcpp_dbg_p_2024.2.0.565_offline.sh
    # TODO: fix this failing to install properly
    INTEL_MKL_URL=https://registrationcenter-download.intel.com/akdlm/IRC_NAS/cdff21a5-6ac7-4b41-a7ec-351b5f9ce8fd/l_onemkl_p_2024.2.0.664_offline.sh
    FORTRAN_URL=https://registrationcenter-download.intel.com/akdlm/IRC_NAS/801143de-6c01-4181-9911-57e00fe40181/l_fortran-compiler_p_2024.2.0.426_offline.sh
    get_install $DPCPP_URL "Patching SYCL Compiler"
    get_install $INTEL_GDB_URL "Patching Intel GDB"
    get_install $INTEL_MKL_URL "Patching Intel MKL"
    get_install $FORTRAN_URL "Patching FORTRAN Compiler"
  fi
fi

# Download and install the plugins (but only the ones requested)
# ROCM_VERSION can be 5.4.3, 5.7.1, 6.0.2 or 6.1.0, defaults 5.4.3
: ${ROCM_VERSION:=5.4.3}
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
if [[ "$install_modulefiles" == "1" ]]; then
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
fi

echo "Installation complete! Try:"
echo "module use $TLD/modulefiles"
echo "module load tbb compiler-rt oclfpga compiler"
echo "icpx --version"

