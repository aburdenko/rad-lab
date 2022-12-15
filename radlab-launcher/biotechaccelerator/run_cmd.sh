#! /usr/bin/bash
pushd /home/aburdenko/rad-lab/modules/alpha_fold
terraform init -lock=false
terraform apply -lock=false
popd