#!/usr/bin/env bash

echo "here in build_nimbix"

set -e

PROJECT=$1
GIT_COMMIT=$2
GIT_BRANCH=$3
GITHUB_TOKEN=$4
PYTHON_VERSION=$5

if [ "$#" -ne 5 ]
then
  echo "Did not find 5 arguments" >&2
  exit 1
fi

echo "Username: $USER"
echo "Homedir: $HOME"
echo "Home ls:"
ls -alh ~/ || true
echo "Current directory: $(pwd)"
echo "Project: $PROJECT"
echo "Branch: $GIT_BRANCH"
echo "Commit: $GIT_COMMIT"

echo "Installing dependencies"

echo "Disks:"
df -h || true

echo "running nvidia-smi"

nvidia-smi

# install and export ccache
if ! which ccache
then
    sudo apt-get install -y ccache
fi
export PATH=/usr/lib/ccache:$PATH

# add cuda to PATH and LD_LIBRARY_PATH
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

if ! ls /usr/local/cuda-8.0
then
    echo "Downloading CUDA 8.0"
    wget -c https://developer.nvidia.com/compute/cuda/8.0/prod/local_installers/cuda_8.0.44_linux-run -O ~/cuda_8.0.44_linux-run

    echo "Installing CUDA 8.0"
    chmod +x ~/cuda_8.0.44_linux-run
    sudo bash ~/cuda_8.0.44_linux-run --silent --toolkit --no-opengl-libs

    echo "\nDone installing CUDA 8.0"
else
    echo "CUDA 8.0 already installed"
fi

echo "nvcc: $(which nvcc)"

if ! ls /usr/local/cuda/lib64/libcudnn.so.5.1.5
then
    echo "CuDNN 5.1.5 not found. Downloading and copying to /usr/local/cuda"
    mkdir -p /tmp/cudnn-download
    pushd /tmp/cudnn-download
    rm -rf cuda
    wget https://s3.amazonaws.com/pytorch/cudnn-8.0-linux-x64-v5.1.tgz
    tar -xvf cudnn-8.0-linux-x64-v5.1.tgz
    sudo cp cuda/include/* /usr/local/cuda/include/
    sudo cp cuda/lib64/* /usr/local/cuda/lib64/
    popd
    echo "Downloaded and installed CuDNN 5.1.5"
fi

echo "Checking Miniconda"

if ! ls ~/miniconda
then
    echo "Miniconda needs to be installed"
    wget https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh
    bash ~/miniconda.sh -b -p $HOME/miniconda
else
    echo "Miniconda is already installed"
fi

export PATH="$HOME/miniconda/bin:$PATH"


export CONDA_ROOT_PREFIX=$(conda info --root)

# by default we install py3. If requested py2, create env and activate
if [ $PYTHON_VERSION -eq 2 ]
then
    echo "Requested python version 2. Activating conda environment"
    if ! conda info --envs | grep py2k
    then
	# create virtual env and activate it
	conda create -n py2k python=2 -y
    fi
    source activate py2k
    export CONDA_ROOT_PREFIX="$HOME/envs/py2k"
fi

echo "Conda root: $CONDA_ROOT_PREFIX"

if ! which cmake
then
    conda install -y cmake
fi

# install mkl
conda install -y mkl

# add mkl to CMAKE_PREFIX_PATH
export CMAKE_LIBRARY_PATH=$CONDA_ROOT_PREFIX/lib:$CONDA_ROOT_PREFIX/include:$CMAKE_LIBRARY_PATH 
export CMAKE_PREFIX_PATH=$CONDA_ROOT_PREFIX

echo "Python Version:"
python --version

echo "Installing $PROJECT at branch $GIT_BRANCH and commit $GIT_COMMIT"
rm -rf $PROJECT
git clone https://pytorchbot:$GITHUB_TOKEN@github.com/pytorch/$PROJECT --quiet 
cd $PROJECT
git -c core.askpass=true fetch --tags https://pytorchbot:$GITHUB_TOKEN@github.com/pytorch/$PROJECT +refs/pull/*:refs/remotes/origin/pr/* --quiet
git checkout $GIT_BRANCH
pip install -r requirements.txt || true
time python setup.py install

echo "Testing pytorch"
time python test/test_torch.py
time python test/test_legacy_nn.py
time python test/test_nn.py
time python test/test_autograd.py
time python test/test_cuda.py

echo "ALL CHECKS PASSED"

# this is needed, i think because of a bug in nimbix-wrapper.py
# otherwise, ALL CHECKS PASSED is not getting printed out sometimes
sleep 10
