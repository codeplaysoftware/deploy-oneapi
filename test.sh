#!/bin/bash
#
#SBATCH --partition=gpu
#SBATCH --qos=gpu
#SBATCH --gres=gpu:1
#SBATCH --time=00:0:20
#SBATCH --account=

# This file will likely require customisation for the particular system
# it is being submitted to, e.g. partition names, quality of service, billing
# account, and so on.

module load gcc nvidia/nvhpc
module use $ONEAPI_DIR/modulefiles
module load tbb oclfpga compiler-rt compiler

srun sycl-ls
srun test
