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

BASE_DIR=oneapi-release
VERSION=2025.2.0
VERSION_DIR=2025.2
BASEKIT_URL=https://registrationcenter-download.intel.com/akdlm/IRC_NAS/bd1d0273-a931-4f7e-ab76-6a2a67d646c7/intel-oneapi-base-toolkit-2025.2.0.592.sh
HPCKIT_URL=https://registrationcenter-download.intel.com/akdlm/IRC_NAS/e974de81-57b7-4ac1-b039-0512f8df974e/intel-oneapi-hpc-toolkit-2025.2.0.575_offline.sh


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
    DPCPP_URL=
    INTEL_GDB_URL=
    INTEL_MKL_URL=
    FORTRAN_URL=
    # Components not yet patched for 2025.2
    #get_install $DPCPP_URL "Patching SYCL Compiler"
    #get_install $INTEL_GDB_URL "Patching Intel GDB"
    #get_install $INTEL_MKL_URL "Patching Intel MKL"
    #get_install $FORTRAN_URL "Patching FORTRAN Compiler"
  fi
fi

# Download and install the plugins (but only the ones requested)
PLUGIN_URL=https://developer.codeplay.com/api/v1/products/download?product=oneapi
LATEST_AMD=oneapi-for-amd-gpus-$VERSION-linux.sh
LATEST_NVIDIA=oneapi-for-nvidia-gpus-$VERSION-linux.sh
if [[ "$install_amd" == "1" ]]; then
  rm -f packages/$LATEST_AMD
  wget -P packages --content-disposition "$PLUGIN_URL&variant=amd&version=$VERSION&filters[]=linux"
  bash packages/$LATEST_AMD -i $VERSION_DIR -y
fi
if [[ "$install_nvidia" == "1" ]]; then
  rm -f packages/$LATEST_NVIDIA
  wget -P packages --content-disposition "$PLUGIN_URL&variant=nvidia&version=$VERSION&filters[]=linux"
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
  echo "Try:"
  echo "module use $TLD/modulefiles"
  echo "module load tbb compiler-rt umf compiler"
  echo "icpx --version"
fi
echo "Installation complete!"
