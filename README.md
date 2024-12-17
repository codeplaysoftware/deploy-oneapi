# deploy.sh

This script will attempt to download and install given versions of the Intel
oneAPI Basekit using the offline installers. It's designed to work on various
HPC systems which depend on modulefiles to let users choose which packages
they want enabled in any given session.

## Options

* `--install-amd`
* `--install-nvidia`
* `--patch`
* `--no-basekit`
* `--no-modulefiles`

The two install options tell the script to download and install the respective
plugins from the Codeplay website. This will only work if it can find the
Basekit install folder.

`--patch` will patch the components of the oneAPI release to their newer
versions, if available.

`--no-basekit` skips installing the Basekit if (for example) all that needs
updated is which plugin is installed, or to save time when making other
updates.

`--no-modulefiles` can be useful if installing oneAPI to a location from
which it will later be copied, as the generated modulefiles use non-relative
links to point to the modulefiles inside the install directory.

## API Token

An API token can be obtained from the Codeplay website. To stop the token
being saved in the user's history, it is looked for in the environment, as
the token is a secret and shouldn't be shared.
