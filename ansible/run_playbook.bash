#!/usr/bin/env bash
# This script will install Ansible into a virtual environment as well as required
# Ansible Galaxy roles, then execute ansible-playbook from the environment.
#
# Usage:
#   bash run_playbook.bash playbook.yml
# 
# All arguments/options are passed to the ansible-playbook command.
# Currently only designed for Debian family Linux distributions.
# Made by Kasper Skytte Andersen
# Available at: https://gist.github.com/KasperSkytte/d184d3d163d1e1cfa9b482b2c009a6c0

set -eu
ansible_venv=${ansible_venv:-"ansible-venv"}
requirements_file=${requirements_file:-"roles/requirements.yml"}

message() {
    echo " *** $1..."
}

setup_ansible_venv() {
    message "Checking whether virtual environment already exists at ${ansible_venv}"
    if [ ! -s "${ansible_venv}/bin/activate" ]
    then
        message "Checking for required system packages"
        pkgs="software-properties-common python3-venv"
        if ! dpkg -s $pkgs >/dev/null 2>&1
        then
            message "One or more required system packages are not installed, installing"
            sudo apt-get update -qqy
            sudo apt-get install -y $pkgs
        else
            message "All required system packages are already installed"
        fi
        message "Installing ansible into virtual environment: ${ansible_venv}"
        python3 -m venv "$ansible_venv"
        . "${ansible_venv}/bin/activate"
        #wheel must be installed first, can't be done in the same command
        python3 -m pip install wheel
        python3 -m pip install ansible
        deactivate
    else
        message "Virtual environment already exists"
    fi

    echo
    echo "Activate environment with:"
    echo "  . ${ansible_venv}/bin/activate"
    echo
}

run_playbook() {
    . "${ansible_venv}/bin/activate"
    if [ -s "$requirements_file" ]
    then
        message "Ensuring required Ansible roles are installed (from ${requirements_file})"
        #ansible-galaxy collection install community.general --roles roles
        ansible-galaxy install -r roles/requirements.yml --roles roles/
    fi
    message "Running Ansible playbook from virtual environment"
    ansible-playbook "$@"
    deactivate
}

setup_ansible_venv
run_playbook "$@"
